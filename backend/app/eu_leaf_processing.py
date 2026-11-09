"""Second-pass HTML extraction: preserve leaf paragraphs inside layout tables."""
import argparse
import fcntl
import gzip
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import shutil
import tempfile
import time
from .eu_processing import Processor,ExtractionError
from .eu_large_html import StreamingParagraphs,extract_stream

PARSER='eu-html-leaf-paragraphs-2'


class LeafParagraphs(StreamingParagraphs):
    blocks=StreamingParagraphs.blocks | {'div','section','article','blockquote'}
    def __init__(self):
        super().__init__();self.frames=[]

    def emit(self):
        if not self.frames:return
        frame=self.frames[-1];text=' '.join(''.join(frame['parts']).split())
        if text:self.rows.append({'text':text,'sourceAnchor':frame['anchor']})
        frame['parts'].clear()

    def handle_starttag(self,tag,attrs):
        if tag=='html':self.html_seen=True
        if tag=='body':self.body=True;self.body_seen=True
        if tag in self.ignored:self.skip+=1;return
        if not self.body or self.skip:return
        if tag in self.blocks:
            self.flush_loose();self.emit()
            if self.frames and tag in ('p','li') and self.frames[-1]['tag']==tag:self.frames.pop()
            self.frames.append({'tag':tag,'parts':[],'anchor':dict(attrs).get('id')})
            self.parts=self.frames[-1]['parts']
        elif tag=='br':
            self.emit();self.flush_loose()

    def handle_endtag(self,tag):
        if tag in self.ignored:self.skip=max(0,self.skip-1);return
        if not self.body or self.skip:return
        if tag in self.blocks:
            matches=[i for i,f in enumerate(self.frames) if f['tag']==tag]
            if matches:
                target=matches[-1]
                while len(self.frames)>target:self.emit();self.frames.pop()
                self.parts=self.frames[-1]['parts'] if self.frames else []
        if tag=='body':self.flush();self.body=False

    def handle_data(self,value):
        if self.body and not self.skip:
            if self.frames:self.frames[-1]['parts'].append(value)
            else:self.loose.append(value)

    def flush(self):
        self.flush_loose()
        while self.frames:self.emit();self.frames.pop()
        self.parts=[]


class LeafProcessor(Processor):
    parser=PARSER

    def batch(self,limit=100):
        if shutil.disk_usage(self.output).free<2*1024**3:return 0
        with sqlite3.connect((self.archive/'archive.sqlite3').as_uri()+'?mode=ro',uri=True) as source:
            source.row_factory=sqlite3.Row
            checkpoint=self.db.execute('SELECT value FROM checkpoint WHERE id=1').fetchone()
            cursor=checkpoint[0] if checkpoint else 0
            rows=source.execute('''SELECT d.rowid AS cursor,d.url,d.work,d.hash,d.content_type,
                w.celex,o.path FROM eu_documents d JOIN eu_works w ON w.work=d.work
                JOIN objects o ON o.hash=d.hash WHERE d.rowid>? ORDER BY d.rowid LIMIT ?''',(cursor,limit)).fetchall()
        for row in rows:
            state='extracted';relative=digest=error=None;temporary=None
            try:
                if 'html' not in row['content_type'].lower():raise ExtractionError('deferred_format')
                path=(self.archive/row['path']).resolve()
                if self.archive not in path.parents:raise ExtractionError('invalid_source_path')
                fd,temporary=tempfile.mkstemp(dir=self.output,suffix='.leaf.tmp')
                with os.fdopen(fd,'wb') as file:
                    with gzip.open(path,'rb') as raw,gzip.GzipFile(fileobj=file,mode='wb',mtime=0) as derived:
                        digest,_=extract_stream(raw,derived,row['content_type'],row['hash'],parser_class=LeafParagraphs,parser_version=PARSER,clean_nuls=True)
                    file.flush();os.fsync(file.fileno())
                check=hashlib.sha256()
                with gzip.open(temporary,'rb') as file:
                    while chunk:=file.read(1024**2):check.update(chunk)
                if check.hexdigest()!=digest:raise ExtractionError('derived_hash_mismatch')
                relative=f"objects/{row['hash'][:2]}/{digest}.json.gz"
                target=self.output/relative;target.parent.mkdir(parents=True,exist_ok=True);os.replace(temporary,target)
            except (OSError,ValueError,EOFError) as exc:
                error=str(exc) if isinstance(exc,ExtractionError) else type(exc).__name__
                state='deferred' if error=='deferred_format' else 'failed'
            finally:
                if temporary and os.path.exists(temporary):os.unlink(temporary)
            with self.db:
                self.db.execute('INSERT OR REPLACE INTO processed VALUES (?,?,?,?,?,?,?,?,?)',(row['url'],row['work'],row['celex'],row['hash'],PARSER,state,relative,digest,error))
                self.db.execute('INSERT OR REPLACE INTO checkpoint VALUES (1,?)',(row['cursor'],))
        return len(rows)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive',type=Path,default=Path('/workspace/lexmemoria-eu-corpus'))
    parser.add_argument('--output',type=Path,default=Path('/workspace/lexmemoria-eu-leaf-processed'))
    parser.add_argument('--watch',action='store_true');args=parser.parse_args()
    processor=LeafProcessor(args.archive,args.output)
    with (processor.output/'processor.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        try:
            while True:
                count=processor.batch(100);print(json.dumps(processor.status()),flush=True)
                if not args.watch:break
                time.sleep(.5 if count else 30)
        finally:processor.close()

if __name__=='__main__':main()
