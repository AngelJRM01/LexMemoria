"""Incremental, local-only EU HTML extraction. Never changes the source archive.

Outputs are derived paragraphs pending legal review, NOT structured legal articles
or client-ready banks. Other formats remain explicitly deferred.
"""
import argparse
from datetime import datetime, timezone
import fcntl
import gzip
import hashlib
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import sqlite3
import tempfile
import time

PARSER='eu-html-paragraphs-1'
MAX_RAW=128*1024*1024

class ExtractionError(ValueError): pass

class Paragraphs(HTMLParser):
    blocks={'p','h1','h2','h3','h4','li','dt','dd','td','th','pre'}
    ignored={'script','style','head','noscript','template'}
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.body=False; self.skip=0; self.depth=0; self.parts=[]
        self.rows=[]; self.anchor=None; self.fallback=[]
    def handle_starttag(self,tag,attrs):
        if tag=='body':self.body=True
        if tag in self.ignored:self.skip+=1
        if not self.body or self.skip:return
        if tag in self.blocks:
            if self.depth==0:self.parts=[];self.anchor=dict(attrs).get('id')
            else:self.parts.append(' ')
            self.depth+=1
        if tag=='br':self.handle_data(' ')
    def handle_endtag(self,tag):
        if tag in self.ignored:
            self.skip=max(0,self.skip-1);return
        if not self.body or self.skip:return
        if tag in self.blocks and self.depth:
            self.depth-=1
            if not self.depth:
                self.flush()
        if tag=='body':
            self.flush();self.body=False
    def handle_data(self,value):
        if self.body and not self.skip:
            self.fallback.append(value)
            if self.depth:self.parts.append(value)
            elif value.strip():self.rows.append({'text':re.sub(r'\s+',' ',value).strip(),'sourceAnchor':None})
    def flush(self):
        text=re.sub(r'\s+',' ',''.join(self.parts)).strip()
        if text:self.rows.append({'text':text,'sourceAnchor':self.anchor})
        self.parts=[]

def extract_html(raw,content_type):
    if 'html' not in content_type.lower():raise ExtractionError('deferred_format')
    encoding=re.search(r'charset\s*=\s*["\']?([\w-]+)',content_type,re.I)
    encoding=encoding.group(1).lower() if encoding else 'utf-8-sig'
    if encoding not in ('utf-8','utf8','utf-8-sig','iso-8859-1','windows-1252'):
        raise ExtractionError('unsupported_encoding')
    try:text=raw.decode(encoding,errors='strict')
    except UnicodeError as exc:raise ExtractionError('invalid_encoding') from exc
    if '<html' not in text.lower() or '<body' not in text.lower():
        raise ExtractionError('invalid_html_document')
    parser=Paragraphs();parser.feed(text);parser.close();parser.flush()
    rows=parser.rows
    if not rows:
        text=re.sub(r'\s+',' ',''.join(parser.fallback)).strip()
        if text:rows=[{'text':text,'sourceAnchor':None}]
    if sum(len(row['text']) for row in rows)<40:raise ExtractionError('insufficient_text')
    return {'schemaVersion':1,'parser':PARSER,'contentKind':'automatic_source_extraction',
        'reviewState':'pending','legalReview':'not_performed','language':'es',
        'informative':True,'unitsAreLegalArticles':False,
        'attribution':'Fuente: Oficina de Publicaciones de la Unión Europea',
        'licenceUrl':'https://op.europa.eu/en/web/about-us/legal-notices/publications-office-reuse-policy',
        'paragraphs':[{'id':f'source-paragraph-{i+1}',**row} for i,row in enumerate(rows)]}

class Processor:
    parser=PARSER
    def __init__(self,archive,output):
        self.archive=Path(archive).resolve(); self.output=Path(output).resolve()
        if self.output==self.archive or self.archive in self.output.parents:
            raise ValueError('Keep derived output outside the original source archive')
        self.output.mkdir(parents=True,exist_ok=True)
        self.db=sqlite3.connect(self.output/'processing.sqlite3')
        self.db.row_factory=sqlite3.Row
        self.db.executescript('''PRAGMA journal_mode=WAL;
          CREATE TABLE IF NOT EXISTS processed(url TEXT PRIMARY KEY,work TEXT,celex TEXT,
            raw_hash TEXT,parser TEXT,state TEXT,output_path TEXT,output_hash TEXT,error TEXT);
          CREATE TABLE IF NOT EXISTS checkpoint(id INTEGER PRIMARY KEY,value INTEGER NOT NULL);''')
    def batch(self,limit=100):
        with sqlite3.connect((self.archive/'archive.sqlite3').as_uri()+'?mode=ro',uri=True) as source:
            source.row_factory=sqlite3.Row
            checkpoint=self.db.execute('SELECT value FROM checkpoint WHERE id=1').fetchone()
            cursor=checkpoint[0] if checkpoint else 0
            rows=source.execute('''SELECT d.rowid AS cursor,d.url,d.work,d.hash,d.content_type,
                w.celex,o.path FROM eu_documents d JOIN eu_works w ON w.work=d.work
                JOIN objects o ON o.hash=d.hash WHERE d.rowid>? ORDER BY d.rowid LIMIT ?''',
                (cursor,limit)).fetchall()
        for row in rows:
            error=None; state='extracted'; relative=None; derived_hash=None
            try:
                if 'html' not in row['content_type'].lower():raise ExtractionError('deferred_format')
                path=(self.archive/row['path']).resolve()
                if self.archive not in path.parents:raise ExtractionError('source_path_outside_archive')
                with gzip.open(path,'rb') as file:raw=file.read(MAX_RAW+1)
                if len(raw)>MAX_RAW:raise ExtractionError('source_size_limit')
                if hashlib.sha256(raw).hexdigest()!=row['hash']:raise ExtractionError('source_hash_mismatch')
                result=extract_html(raw,row['content_type']);result['rawSha256']=row['hash']
                encoded=json.dumps(result,ensure_ascii=False,sort_keys=True).encode()
                derived_hash=hashlib.sha256(encoded).hexdigest()
                relative=f"objects/{row['hash'][:2]}/{derived_hash}.json.gz"
                target=self.output/relative;target.parent.mkdir(parents=True,exist_ok=True)
                if not target.exists():
                    fd,temporary=tempfile.mkstemp(dir=target.parent,suffix='.tmp')
                    try:
                        with os.fdopen(fd,'wb') as file:
                            file.write(gzip.compress(encoded,mtime=0));file.flush();os.fsync(file.fileno())
                        os.replace(temporary,target)
                    finally:
                        if os.path.exists(temporary):os.unlink(temporary)
                # Check the exact persisted object before committing its index.
                if hashlib.sha256(gzip.decompress(target.read_bytes())).hexdigest()!=derived_hash:
                    raise ExtractionError('derived_hash_mismatch')
            except (ExtractionError,OSError,ValueError,EOFError) as exc:
                error=str(exc) if isinstance(exc,ExtractionError) else type(exc).__name__
                state='deferred' if error=='deferred_format' else 'failed'
            with self.db:
                self.db.execute('INSERT OR REPLACE INTO processed VALUES (?,?,?,?,?,?,?,?,?)',
                    (row['url'],row['work'],row['celex'],row['hash'],PARSER,state,relative,derived_hash,error))
                self.db.execute('INSERT OR REPLACE INTO checkpoint VALUES (1,?)',(row['cursor'],))
        return len(rows)
    def status(self):
        states=dict(self.db.execute('SELECT state,count(*) FROM processed GROUP BY state').fetchall())
        report={'parser':self.parser,'observedAt':datetime.now(timezone.utc).isoformat(),
            'states':states,'clientIntegrated':False,'legalReview':'not_performed',
            'scope':'Derived HTML paragraphs only; non-HTML files deferred; original archive unchanged'}
        target=self.output/'status.json';temporary=target.with_suffix('.tmp')
        temporary.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');os.replace(temporary,target)
        return report
    def close(self):self.db.close()

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--watch',action='store_true')
    parser.add_argument('--limit',type=int,default=100)
    args=parser.parse_args()
    if not 1<=args.limit<=1000:parser.error('limit must be 1..1000')
    processor=Processor(args.archive,args.output)
    lock=open(processor.output/'processor.lock','a')
    try:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        while True:
            count=processor.batch(args.limit);print(json.dumps(processor.status()),flush=True)
            if not args.watch:break
            time.sleep(.5 if count else 15)
    except KeyboardInterrupt:pass
    finally:processor.close();lock.close()

if __name__=='__main__':main()
