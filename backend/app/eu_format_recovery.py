"""Recover OCR, legacy Word and large Formex as traceable, unreviewed text."""
import argparse
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
from .eu_other_processing import write_document
from .eu_processing import ExtractionError

ROOT=Path('/workspace/lexmemoria-eu-other-processed')
TESSDATA=Path('/workspace/tools/tessdata')
ANTIWORD=Path('/workspace/tools/antiword/usr/bin/antiword')


def formex_stream(path):
    selected=0;depth=0;active_chars=0;legal=False;found=False;correction=False;bib=0
    blocks={'TI.ART','TI.ANNEX','TI.GRSEQ','ALINEA','PARAG','GR.CONSID'}
    for event,node in ET.iterparse(path,events=('start','end'),forbid_dtd=True,forbid_entities=True):
        tag=node.tag.rsplit('}',1)[-1]
        if event=='start':
            depth+=1
            if tag=='CORR':correction=True;legal=True
            if correction and tag=='BIB.INSTANCE':bib=depth
            if tag in ('ACT','CONS.ACT','ARTICLE'):legal=True
            if not selected and not bib and (tag in blocks or (correction and tag in ('TITLE','P','ROW'))):selected=depth;active_chars=0
        else:
            if selected:
                active_chars+=len(node.text or '')+len(node.tail or '')
                if active_chars>4*1024**2:raise ExtractionError('xml_paragraph_size_limit')
                if depth==selected:
                    text=' '.join(' '.join(node.itertext()).split())
                    if text:
                        found=True;yield {'text':text,'sourceAnchor':node.attrib.get('ID') or node.attrib.get('IDENTIFIER')}
                    node.clear();selected=0
            else:node.clear()
            if depth==bib:bib=0
            depth-=1
    if not legal or not found:raise ExtractionError('xml_manifest_metadata_only')


def zip_formex_stream(path):
    with zipfile.ZipFile(path) as package:
        entries=[e for e in package.infolist() if e.filename.lower().endswith('.xml')]
        if sum(e.file_size for e in entries)>2*1024**3:raise ExtractionError('zip_requires_large_document_job')
        any_text=False
        for entry in entries:
            try:
                with package.open(entry) as member:
                    for paragraph in formex_stream(member):
                        any_text=True;yield {**paragraph,'sourceContainer':entry.filename}
            except ExtractionError as exc:
                if str(exc)!='xml_manifest_metadata_only':raise
        if not any_text:raise ExtractionError('xml_manifest_metadata_only')


def word_lines(path):
    if not ANTIWORD.exists():raise ExtractionError('word_converter_unavailable')
    env={**os.environ,'ANTIWORDHOME':'/workspace/tools/antiword/usr/share/antiword'}
    result=subprocess.run([str(ANTIWORD),'-m','UTF-8.txt',str(path)],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=60)
    if result.returncode:raise ExtractionError('word_requires_manual_conversion')
    for i,line in enumerate(result.stdout.decode('utf-8',errors='strict').splitlines(),1):
        text=' '.join(line.split())
        if text:yield {'text':text,'sourceAnchor':None,'sourceLine':i}


def ocr_lines(path,metadata):
    if not (TESSDATA/'spa.traineddata').exists():raise ExtractionError('spanish_ocr_model_unavailable')
    info=subprocess.run(['pdfinfo',str(path)],stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=30)
    match=re.search(rb'^Pages:\s+(\d+)',info.stdout,re.M)
    if not match:raise ExtractionError('pdf_page_count_unavailable')
    pages=int(match[1])
    if pages>500:raise ExtractionError('ocr_requires_large_document_job')
    metadata['pageCount']=pages;metadata['qualityWarnings']=['ocr_requires_review'];empty=[]
    metadata['ocrLanguage']='spa'
    metadata['ocrModelSha256']=hashlib.sha256((TESSDATA/'spa.traineddata').read_bytes()).hexdigest()
    with tempfile.TemporaryDirectory(prefix='lex-eu-ocr-') as folder:
        prefix=Path(folder)/'page'
        for page in range(1,pages+1):
            command=['pdftoppm','-f',str(page),'-l',str(page),'-r','200','-png','-singlefile',str(path),str(prefix)]
            converted=subprocess.run(command,stdout=subprocess.DEVNULL,stderr=subprocess.PIPE,timeout=120)
            if converted.returncode:raise ExtractionError('pdf_raster_conversion_failed')
            image=prefix.with_suffix('.png')
            result=subprocess.run(['tesseract',str(image),'stdout','--tessdata-dir',str(TESSDATA),'-l','spa'],
                env={**os.environ,'OMP_THREAD_LIMIT':'1'},stdout=subprocess.PIPE,stderr=subprocess.PIPE,timeout=120)
            if result.returncode:raise ExtractionError('ocr_conversion_failed')
            text=result.stdout.decode('utf-8',errors='strict');nonempty=False
            for line in text.splitlines():
                value=' '.join(line.split())
                if value:nonempty=True;yield {'text':value,'sourceAnchor':None,'sourcePage':page,'ocr':True}
            if not nonempty:empty.append(page)
            image.unlink(missing_ok=True)
    metadata['pagesWithLittleText']=empty


def main():
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--watch',action='store_true');args=p.parse_args()
    ROOT.mkdir(exist_ok=True)
    with (ROOT/'format-recovery.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        db=sqlite3.connect(ROOT/'processing.sqlite3');db.row_factory=sqlite3.Row
        db.execute('CREATE TABLE IF NOT EXISTS recovery_attempts(url TEXT PRIMARY KEY,raw_hash TEXT,state TEXT,error TEXT)')
        with sqlite3.connect('file:/workspace/lexmemoria-eu-corpus/archive.sqlite3?mode=ro',uri=True) as source:
            source.row_factory=sqlite3.Row
            while True:
                rows=db.execute("SELECT p.* FROM processed p LEFT JOIN recovery_attempts r ON r.url=p.url AND r.raw_hash=p.raw_hash WHERE p.state='deferred' AND p.error IN ('pdf_requires_ocr','pdf_conversion_failed','format_requires_converter','xml_size_limit','zip_text_size_limit','zip_requires_specific_parser') AND r.url IS NULL ORDER BY p.rowid LIMIT 10").fetchall()
                for row in rows:
                    if shutil.disk_usage(ROOT).free<2*1024**3:raise RuntimeError('insufficient_disk')
                    error=None;state='recovered';relative=digest=None
                    try:
                        original=source.execute('SELECT o.path,d.content_type FROM objects o JOIN eu_documents d ON d.hash=o.hash WHERE d.url=? AND o.hash=?',(row['url'],row['raw_hash'])).fetchone()
                        if original is None:raise ExtractionError('source_changed')
                        mime=original['content_type'].split(';')[0].lower()
                        if row['error']=='format_requires_converter' and mime!='application/msword':raise ExtractionError('unsupported_original_format')
                        path=(Path('/workspace/lexmemoria-eu-corpus')/original['path']).resolve()
                        if Path('/workspace/lexmemoria-eu-corpus') not in path.parents:raise ExtractionError('invalid_source_path')
                        with tempfile.TemporaryDirectory(prefix='lex-eu-recovery-') as folder:
                            raw=Path(folder)/'original';hash_=hashlib.sha256();size=0
                            with gzip.open(path,'rb') as archived,raw.open('wb') as file:
                                while chunk:=archived.read(1024**2):
                                    size+=len(chunk)
                                    if size>1024**3:raise ExtractionError('source_size_limit')
                                    hash_.update(chunk);file.write(chunk)
                            if hash_.hexdigest()!=row['raw_hash']:raise ExtractionError('source_hash_mismatch')
                            parser='eu-pdf-ocr-spa-1' if row['error'] in ('pdf_requires_ocr','pdf_conversion_failed') else 'eu-formex-stream-1' if row['error'] in ('xml_size_limit','zip_text_size_limit','zip_requires_specific_parser') else 'eu-word-text-1'
                            metadata={'schemaVersion':1,'parser':parser,'rawSha256':row['raw_hash'],'language':'es',
                              'contentKind':'automatic_source_extraction','reviewState':'pending','legalReview':'not_performed',
                              'informative':True,'unitsAreLegalArticles':False,'sourceFormat':mime,
                              'attribution':'Fuente: Oficina de Publicaciones de la Unión Europea'}
                            paragraphs=ocr_lines(raw,metadata) if row['error'] in ('pdf_requires_ocr','pdf_conversion_failed') else (zip_formex_stream(raw) if 'zip' in mime else formex_stream(raw)) if row['error'] in ('xml_size_limit','zip_text_size_limit','zip_requires_specific_parser') else word_lines(raw)
                            temporary=Path(folder)/'derived.gz'
                            with temporary.open('wb') as file:
                                with gzip.GzipFile(fileobj=file,mode='wb',mtime=0) as output:digest=write_document(paragraphs,metadata,output)
                            check=hashlib.sha256()
                            with gzip.open(temporary,'rb') as file:
                                while chunk:=file.read(1024**2):check.update(chunk)
                            if check.hexdigest()!=digest:raise ExtractionError('derived_hash_mismatch')
                            relative=f"objects/{row['raw_hash'][:2]}/{digest}.json.gz";target=ROOT/relative;target.parent.mkdir(parents=True,exist_ok=True)
                            pending=target.with_suffix('.tmp');shutil.copyfile(temporary,pending);pending.replace(target)
                            with db:db.execute("UPDATE processed SET parser=?,state='extracted',output_path=?,output_hash=?,error=NULL WHERE url=? AND raw_hash=? AND state='deferred'",(parser,relative,digest,row['url'],row['raw_hash']))
                    except Exception as exc:
                        if isinstance(exc,ExtractionError) and str(exc) in ('source_hash_mismatch','derived_hash_mismatch','invalid_source_path'):raise
                        state='manual_review';error=str(exc)[:160]
                    with db:db.execute('INSERT OR REPLACE INTO recovery_attempts VALUES (?,?,?,?)',(row['url'],row['raw_hash'],state,error))
                    print(json.dumps({'celex':row['celex'],'state':state,'error':error}),flush=True)
                report={'attempts':dict(db.execute('SELECT state,COUNT(*) FROM recovery_attempts GROUP BY state')),
                    'remainingDeferred':dict(db.execute("SELECT error,COUNT(*) FROM processed WHERE state='deferred' GROUP BY error")),'legalReview':'not_performed'}
                temporary=ROOT/'recovery-status.tmp';temporary.write_text(json.dumps(report,indent=2)+'\n');temporary.replace(ROOT/'recovery-status.json')
                if not args.watch:break
                time.sleep(5 if rows else 30)
        db.close()

if __name__=='__main__':main()
