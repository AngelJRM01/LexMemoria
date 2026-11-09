"""Local PDF/Formex extraction with provenance; images are retained source assets."""
import argparse
from collections import Counter
import fcntl
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
import tempfile
import time
import zipfile
from defusedxml import ElementTree as ET
from defusedxml.common import DefusedXmlException
from xml.etree.ElementTree import ParseError
from .eu_processing import Processor,ExtractionError

PARSER='eu-pdf-formex-source-2'


def xml_paragraphs(raw,origin=None):
    if len(raw)>64*1024**2:raise ExtractionError('xml_size_limit')
    root=ET.fromstring(raw,forbid_dtd=True,forbid_entities=True)
    local=lambda node:node.tag.rsplit('}',1)[-1]
    if not any(local(n) in ('ACT','CONS.ACT','ARTICLE') for n in root.iter()):
        raise ExtractionError('xml_manifest_metadata_only')
    blocks={'TI.ART','TI.ANNEX','TI.GRSEQ','ALINEA','PARAG','GR.CONSID'}
    def walk(node):
        if local(node) in blocks:
            text=' '.join(' '.join(node.itertext()).split())
            if text:yield {'text':text,'sourceAnchor':node.attrib.get('IDENTIFIER') or node.attrib.get('ID'),'sourceContainer':origin}
        else:
            for child in node:yield from walk(child)
    yield from walk(root)


def pdf_paragraphs(path,metadata):
    with tempfile.TemporaryDirectory(prefix='lex-eu-pdf-') as folder:
        target=Path(folder)/'text.txt'
        result=subprocess.run(['pdftotext','-layout','-enc','UTF-8',str(path),str(target)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=60)
        if result.returncode:raise ExtractionError('pdf_conversion_failed')
        if target.stat().st_size>128*1024**2:raise ExtractionError('pdf_text_size_limit')
        page=1;letters=0;page_letters=Counter();pending=[]
        heading=re.compile(r'^(?:Art[íi]culo\s+(?:\d+[a-z]*|único)[.º°]*|(?:CAPÍTULO|TÍTULO|SECCIÓN|ANEXO)(?:\s+[IVXLCDM\d]+)?)$',re.I)
        numbered=re.compile(r'^(?:\d+[.)]|[a-z]\))\s')
        with target.open(encoding='utf-8',errors='strict') as text:
            for line in text:
                for i,part in enumerate(line.split('\f')):
                    if i:
                        if pending:yield {'text':' '.join(pending),'sourceAnchor':None,'sourcePage':page};pending=[]
                        page+=1
                    value=' '.join(part.split())
                    if not value:
                        if pending:yield {'text':' '.join(pending),'sourceAnchor':None,'sourcePage':page};pending=[]
                        continue
                    alpha=sum(c.isalpha() for c in value);letters+=alpha;page_letters[page]+=alpha
                    if heading.fullmatch(value):
                        if pending:yield {'text':' '.join(pending),'sourceAnchor':None,'sourcePage':page};pending=[]
                        yield {'text':value,'sourceAnchor':None,'sourcePage':page}
                    else:
                        if numbered.match(value) and pending:yield {'text':' '.join(pending),'sourceAnchor':None,'sourcePage':page};pending=[]
                        pending.append(value)
            if pending:yield {'text':' '.join(pending),'sourceAnchor':None,'sourcePage':page}
        if letters<40:raise ExtractionError('pdf_requires_ocr')
        last=max(page_letters,default=page)
        metadata['lastTextPage']=last
        metadata['pagesWithLittleText']=[p for p in range(1,last+1) if page_letters[p]<20]
        metadata['qualityWarnings']=['pages_may_require_ocr'] if metadata['pagesWithLittleText'] else []


def zip_paragraphs(path):
    with zipfile.ZipFile(path) as package:
        entries=[e for e in package.infolist() if e.filename.lower().endswith('.xml')]
        if sum(e.file_size for e in entries)>512*1024**2:raise ExtractionError('zip_text_size_limit')
        yielded=False
        for entry in entries:
            if entry.file_size>64*1024**2:raise ExtractionError('xml_size_limit')
            try:
                for paragraph in xml_paragraphs(package.read(entry),entry.filename):yielded=True;yield paragraph
            except ExtractionError as exc:
                if str(exc)!='xml_manifest_metadata_only':raise
        if not yielded:raise ExtractionError('zip_requires_specific_parser')


def write_document(paragraphs,metadata,file):
    digest=hashlib.sha256();count=0
    def write(data):file.write(data);digest.update(data)
    header={k:v for k,v in metadata.items() if k not in ('lastTextPage','pagesWithLittleText','qualityWarnings')}
    write(json.dumps(header,ensure_ascii=False).encode()[:-1]+b',"paragraphs":[')
    for paragraph in paragraphs:
        if len(paragraph['text'])>4*1024**2:raise ExtractionError('paragraph_size_limit')
        if count:write(b',')
        count+=1;write(json.dumps({'id':f'source-paragraph-{count}',**paragraph},ensure_ascii=False).encode())
    if not count:raise ExtractionError('no_extractable_text')
    write(b']')
    for key in metadata:
        if key not in header:write(b','+json.dumps(key).encode()+b':'+json.dumps(metadata[key]).encode())
    write(b'}');return digest.hexdigest()


class OtherProcessor(Processor):
    parser=PARSER
    pdf_only=False
    def status(self):
        report=super().status()
        report['scope']='PDF/Formex source extraction; image assets retained; OCR and Word conversions remain explicit'
        temporary=self.output/'status.formats.tmp'
        temporary.write_text(json.dumps(report,indent=2)+'\n');temporary.replace(self.output/'status.json')
        return report

    def batch(self,limit=100):
        if shutil.disk_usage(self.output).free<2*1024**3:return 0
        checkpoint=self.db.execute('SELECT value FROM checkpoint WHERE id=1').fetchone();cursor=checkpoint[0] if checkpoint else 0
        with sqlite3.connect((self.archive/'archive.sqlite3').as_uri()+'?mode=ro',uri=True) as source:
            source.row_factory=sqlite3.Row
            rows=source.execute('''SELECT d.rowid AS cursor,d.*,w.celex,o.path FROM eu_documents d
                JOIN eu_works w ON w.work=d.work JOIN objects o ON o.hash=d.hash
                WHERE d.rowid>? ORDER BY d.rowid LIMIT ?''',(cursor,limit)).fetchall()
        for row in rows:
            relative=digest=error=None;state='deferred';mime=row['content_type'].split(';')[0].lower()
            existing=self.db.execute('SELECT parser,state FROM processed WHERE url=?',(row['url'],)).fetchone() if self.pdf_only else None
            if self.pdf_only and (mime!='application/pdf' or (existing is not None and existing['state']=='extracted' and existing['parser']=='eu-pdf-ocr-spa-1')):
                with self.db:self.db.execute('INSERT OR REPLACE INTO checkpoint VALUES (1,?)',(row['cursor'],))
                continue
            try:
                if mime.startswith('image/') or mime=='text/css':state='source_asset'
                elif 'html' in mime:state='handled_by_html_pipeline'
                elif mime not in ('application/pdf','application/xml','text/xml','application/zip','application/x-zip-compressed'):
                    error='format_requires_converter'
                else:
                    source_path=(self.archive/row['path']).resolve()
                    if self.archive not in source_path.parents:raise ExtractionError('invalid_source_path')
                    with tempfile.TemporaryDirectory(prefix='lex-eu-source-') as folder:
                        original=Path(folder)/('source.pdf' if mime=='application/pdf' else 'source.bin')
                        raw_hash=hashlib.sha256();size=0
                        with gzip.open(source_path,'rb') as compressed,original.open('wb') as target:
                            while chunk:=compressed.read(1024**2):
                                size+=len(chunk)
                                if size>1024**3:raise ExtractionError('source_size_limit')
                                raw_hash.update(chunk);target.write(chunk)
                        if raw_hash.hexdigest()!=row['hash']:raise ExtractionError('source_hash_mismatch')
                        metadata={'schemaVersion':1,'parser':PARSER,'rawSha256':row['hash'],'language':'es',
                                  'contentKind':'automatic_source_extraction','reviewState':'pending','legalReview':'not_performed',
                                  'informative':True,'unitsAreLegalArticles':False,'sourceFormat':mime,
                                  'attribution':'Fuente: Oficina de Publicaciones de la Unión Europea',
                                  'licenceUrl':'https://op.europa.eu/en/web/about-us/legal-notices/publications-office-reuse-policy'}
                        if mime=='application/pdf':paragraphs=pdf_paragraphs(original,metadata)
                        elif 'zip' in mime:paragraphs=zip_paragraphs(original)
                        else:
                            if size>64*1024**2:raise ExtractionError('xml_size_limit')
                            paragraphs=xml_paragraphs(original.read_bytes())
                        temporary=Path(folder)/'derived.gz'
                        with temporary.open('wb') as file:
                            with gzip.GzipFile(fileobj=file,mode='wb',mtime=0) as sink:digest=write_document(paragraphs,metadata,sink)
                        check=hashlib.sha256()
                        with gzip.open(temporary,'rb') as file:
                            while chunk:=file.read(1024**2):check.update(chunk)
                        if check.hexdigest()!=digest:raise ExtractionError('derived_hash_mismatch')
                        relative=f"objects/{row['hash'][:2]}/{digest}.json.gz";target=self.output/relative
                        target.parent.mkdir(parents=True,exist_ok=True)
                        # The temp directory may be on another filesystem.
                        pending=target.with_suffix('.tmp');shutil.copyfile(temporary,pending);pending.replace(target)
                        state='extracted'
            except ExtractionError as exc:
                error=str(exc);state='failed' if 'hash_mismatch' in error or error=='invalid_source_path' else 'deferred'
            except (OSError,ValueError,EOFError,subprocess.TimeoutExpired,zipfile.BadZipFile,DefusedXmlException,ParseError) as exc:
                state='deferred';error=type(exc).__name__
            with self.db:
                self.db.execute('INSERT OR REPLACE INTO processed VALUES (?,?,?,?,?,?,?,?,?)',(row['url'],row['work'],row['celex'],row['hash'],PARSER,state,relative,digest,error))
                self.db.execute('INSERT OR REPLACE INTO checkpoint VALUES (1,?)',(row['cursor'],))
        return len(rows)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive',type=Path,default=Path('/workspace/lexmemoria-eu-corpus'))
    parser.add_argument('--output',type=Path,default=Path('/workspace/lexmemoria-eu-other-processed'))
    parser.add_argument('--watch',action='store_true');parser.add_argument('--pdf-only',action='store_true');args=parser.parse_args()
    processor=OtherProcessor(args.archive,args.output);processor.pdf_only=args.pdf_only
    with (processor.output/'processor.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:
            while True:
                count=processor.batch(100);print(json.dumps(processor.status()),flush=True)
                if not args.watch:break
                time.sleep(.5 if count else 30)
        finally:processor.close()

if __name__=='__main__':main()
