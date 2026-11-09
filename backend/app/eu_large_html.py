"""Bounded-memory recovery of oversized archived HTML; originals stay immutable."""
import argparse
import codecs
import fcntl
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import sqlite3
import tempfile

from .eu_processing import Paragraphs, ExtractionError

PARSER='eu-html-paragraphs-stream-1'


class StreamingParagraphs(Paragraphs):
    def __init__(self):
        super().__init__();self.html_seen=False;self.body_seen=False;self.loose=[]

    def flush_loose(self):
        text=re.sub(r'\s+',' ',''.join(self.loose)).strip()
        if text:self.rows.append({'text':text,'sourceAnchor':None})
        self.loose.clear()

    def handle_endtag(self,tag):
        self.flush_loose();super().handle_endtag(tag)

    def handle_starttag(self,tag,attrs):
        self.flush_loose()
        if tag=='html':self.html_seen=True
        if tag=='body':self.body_seen=True
        super().handle_starttag(tag,attrs)

    def handle_data(self,value):
        # The ordinary parser's fallback duplicates all body text in memory.
        if self.body and not self.skip:
            if self.depth:self.parts.append(value)
            else:self.loose.append(value)


def extract_stream(source,sink,content_type,expected_hash,chunk_size=65536):
    if 'html' not in content_type.lower():raise ExtractionError('deferred_format')
    match=re.search(r'charset\s*=\s*["\']?([\w-]+)',content_type,re.I)
    encoding=match.group(1).lower() if match else 'utf-8-sig'
    if encoding not in ('utf-8','utf8','utf-8-sig','iso-8859-1','windows-1252'):
        raise ExtractionError('unsupported_encoding')
    decoder=codecs.getincrementaldecoder(encoding)(errors='strict')
    parser=StreamingParagraphs();raw_digest=hashlib.sha256();derived_digest=hashlib.sha256()
    metadata={'schemaVersion':1,'parser':PARSER,'contentKind':'automatic_source_extraction',
              'reviewState':'pending','legalReview':'not_performed','language':'es',
              'informative':True,'unitsAreLegalArticles':False,'rawSha256':expected_hash,
              'attribution':'Fuente: Oficina de Publicaciones de la Unión Europea',
              'licenceUrl':'https://op.europa.eu/en/web/about-us/legal-notices/publications-office-reuse-policy'}
    def write(data):sink.write(data);derived_digest.update(data)
    write(json.dumps(metadata,ensure_ascii=False).encode()[:-1]+b',"paragraphs":[')
    count=0;characters=0;total=0
    def flush():
        nonlocal count,characters
        for row in parser.rows:
            text=row['text']
            if count:write(b',')
            count+=1;characters+=len(text)
            write(json.dumps({'id':f'source-paragraph-{count}',**row},ensure_ascii=False).encode())
        parser.rows.clear()
    while chunk:=source.read(chunk_size):
        total+=len(chunk)
        if total>1024**3:raise ExtractionError('stream_source_size_limit')
        raw_digest.update(chunk);parser.feed(decoder.decode(chunk));flush()
        if sum(map(len,parser.parts))+sum(map(len,parser.loose))>4*1024**2:raise ExtractionError('paragraph_size_limit')
    parser.feed(decoder.decode(b'',final=True));parser.close();parser.flush_loose();parser.flush();flush()
    if raw_digest.hexdigest()!=expected_hash:raise ExtractionError('source_hash_mismatch')
    if not parser.html_seen or not parser.body_seen:raise ExtractionError('invalid_html_document')
    if characters<40:raise ExtractionError('insufficient_text')
    write(b']}')
    return derived_digest.hexdigest(),count


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archive',type=Path,default=Path('/workspace/lexmemoria-eu-corpus'))
    p.add_argument('--processed',type=Path,default=Path('/workspace/lexmemoria-eu-processed'))
    args=p.parse_args();archive=args.archive.resolve();output=args.processed.resolve()
    if archive==output or archive in output.parents or output in archive.parents:p.error('Separate source and output')
    with (output/'large-html.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        db=sqlite3.connect(output/'processing.sqlite3');db.row_factory=sqlite3.Row
        rows=db.execute("SELECT * FROM processed WHERE state='failed' AND error='source_size_limit' ORDER BY url").fetchall()
        with sqlite3.connect((archive/'archive.sqlite3').as_uri()+'?mode=ro',uri=True) as original:
            for row in rows:
                fd,tmp=tempfile.mkstemp(dir=output,suffix='.large.tmp')
                handle=os.fdopen(fd,'wb')
                try:
                    path=original.execute('SELECT o.path,d.content_type FROM objects o JOIN eu_documents d ON d.hash=o.hash WHERE o.hash=? AND d.url=?',(row['raw_hash'],row['url'])).fetchone()
                    if path is None:raise ExtractionError('missing_source')
                    source=(archive/path[0]).resolve()
                    if archive not in source.parents:raise ExtractionError('invalid_source_path')
                    with handle as file:
                        with gzip.open(source,'rb') as raw,gzip.GzipFile(fileobj=file,mode='wb',mtime=0) as derived:
                            digest,count=extract_stream(raw,derived,path[1],row['raw_hash'])
                        file.flush();os.fsync(file.fileno())
                    relative=f"objects/{row['raw_hash'][:2]}/{digest}.json.gz"
                    target=output/relative;target.parent.mkdir(parents=True,exist_ok=True)
                    check=hashlib.sha256()
                    with gzip.open(tmp,'rb') as file:
                        while chunk:=file.read(1024**2):check.update(chunk)
                    if check.hexdigest()!=digest:raise ExtractionError('derived_hash_mismatch')
                    os.replace(tmp,target)
                    with db:
                        changed=db.execute("UPDATE processed SET state='extracted',parser=?,output_path=?,output_hash=?,error=NULL WHERE url=? AND raw_hash=? AND state='failed' AND error='source_size_limit'",(PARSER,relative,digest,row['url'],row['raw_hash'])).rowcount
                    print(json.dumps({'celex':row['celex'],'state':'extracted' if changed else 'source_changed','paragraphs':count}),flush=True)
                except (OSError,ValueError,UnicodeError,EOFError) as exc:
                    print(json.dumps({'celex':row['celex'],'state':'failed','error':str(exc)[:120]}),flush=True)
                finally:
                    handle.close()
                    if os.path.exists(tmp):os.unlink(tmp)
        db.close()

if __name__=='__main__':main()
