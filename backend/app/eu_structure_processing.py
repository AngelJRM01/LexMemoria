"""Incremental local structure candidates; never publishes study content."""
import argparse
from datetime import datetime, timezone
import fcntl
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import time
from .eu_structure import PARSER, UnitCursor, structure_document


class Processor:
    parser=PARSER
    structure=staticmethod(structure_document)
    cursor_class=UnitCursor
    memory_limit=128*1024**2
    def __init__(self, source, output):
        self.source=Path(source).resolve();self.output=Path(output).resolve()
        if self.source==self.output or self.source in self.output.parents or self.output in self.source.parents:
            raise ValueError('Keep output separate from source')
        self.output.mkdir(parents=True,exist_ok=True)
        self.lock=(self.output/'structure.lock').open('a')
        try:fcntl.flock(self.lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BaseException:self.lock.close();raise
        self.db=sqlite3.connect((self.output/'structure.sqlite3').as_uri(),uri=True)
        self.db.executescript('''PRAGMA journal_mode=WAL;
          CREATE TABLE IF NOT EXISTS results(source_row INTEGER PRIMARY KEY,url TEXT,
          celex TEXT,state TEXT,path TEXT,articles INTEGER,paragraphs INTEGER,warnings TEXT,error TEXT);
          CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY,value TEXT);
          CREATE INDEX IF NOT EXISTS result_states ON results(state);''')
        columns={r[1] for r in self.db.execute('PRAGMA table_info(results)')}
        if 'source_output_hash' not in columns:
            with self.db:self.db.execute('ALTER TABLE results ADD COLUMN source_output_hash TEXT')
            src=self.source/'processing.sqlite3'
            if src.exists():
                self.db.execute('ATTACH DATABASE ? AS source_hashes',(src.as_uri()+'?mode=ro',))
                with self.db:self.db.execute('UPDATE results SET source_output_hash=(SELECT output_hash FROM source_hashes.processed p WHERE p.url=results.url)')
                self.db.execute('DETACH DATABASE source_hashes')
        previous=self.db.execute("SELECT value FROM settings WHERE key='parser'").fetchone()
        if previous and previous[0]!=self.parser:
            self.close();raise ValueError('Parser changed: use a new output directory')
        with self.db:self.db.execute("INSERT OR IGNORE INTO settings VALUES ('parser',?)",(self.parser,))

    def batch(self,limit=100):
        if shutil.disk_usage(self.output).free<2*1024**3:return 0
        cursor=self.db.execute('SELECT COALESCE(MAX(source_row),0) FROM results').fetchone()[0]
        with sqlite3.connect((self.source/'processing.sqlite3').as_uri()+'?mode=ro',uri=True) as db:
            db.row_factory=sqlite3.Row
            rows=db.execute('SELECT rowid AS cursor,* FROM processed WHERE rowid>? ORDER BY rowid LIMIT ?',(cursor,limit)).fetchall()
            if not rows:
                # A previously oversized original can become extracted without
                # changing its rowid. Revisit skipped rows after catching up.
                db.execute('ATTACH DATABASE ? AS derived_index', ((self.output/'structure.sqlite3').as_uri()+'?mode=ro',))
                rows=db.execute("SELECT p.rowid AS cursor,p.* FROM derived_index.results r JOIN processed p ON p.rowid=r.source_row WHERE p.state='extracted' AND (r.state='skipped' OR r.source_output_hash IS NOT p.output_hash) ORDER BY p.rowid LIMIT ?",(limit,)).fetchall()
        for row in rows:
            state='skipped';path=None;articles=paragraphs=0;warnings=[];error=None
            try:
                if row['state']=='extracted':
                    source=(self.source/row['output_path']).resolve()
                    if self.source not in source.parents:raise ValueError('invalid_source_path')
                    with gzip.open(source,'rb') as f:encoded=f.read(self.memory_limit+1)
                    if len(encoded)>self.memory_limit:
                        del encoded
                        from .eu_paged_structure import prepare
                        path,result=prepare(source,self.output,row,cursor_class=self.cursor_class,parser_version=self.parser)
                        paragraphs=result['paragraphs'];warnings=result['warnings']
                        articles=sum(u['kind']=='article_candidate' for u in result['units'])
                    else:
                        if hashlib.sha256(encoded).hexdigest()!=row['output_hash']:raise ValueError('source_hash_mismatch')
                        original=json.loads(encoded)
                        if original['rawSha256']!=row['raw_hash']:raise ValueError('raw_hash_mismatch')
                        result=self.structure(original,row['celex'] or '',row['url']);result['paragraphSourceSha256']=row['output_hash']
                        flat=[p for u in result['units'] for p in u['paragraphs']]
                        if flat!=original['paragraphs']:raise ValueError('paragraph_loss_or_reordering')
                        paragraphs=len(flat);warnings=result['warnings']
                        articles=sum(u['kind']=='article_candidate' for u in result['units'])
                        data=json.dumps(result,ensure_ascii=False,sort_keys=True).encode()
                        digest=hashlib.sha256(data).hexdigest()
                        path=f'objects/{digest[:2]}/{digest}.json.gz'
                        target=self.output/path;target.parent.mkdir(parents=True,exist_ok=True)
                        if not target.exists():
                            temporary=target.with_suffix('.tmp')
                            temporary.write_bytes(gzip.compress(data,mtime=0));temporary.replace(target)
                        if hashlib.sha256(gzip.decompress(target.read_bytes())).hexdigest()!=digest:raise ValueError('output_hash_mismatch')
                    state='candidate'
            except (OSError,ValueError,KeyError,TypeError,EOFError) as exc:
                state='failed';error=str(exc) if isinstance(exc,ValueError) else type(exc).__name__
            with self.db:
                self.db.execute('DELETE FROM results WHERE url=? AND source_row!=?',(row['url'],row['cursor']))
                self.db.execute('INSERT OR REPLACE INTO results VALUES (?,?,?,?,?,?,?,?,?,?)',
                    (row['cursor'],row['url'],row['celex'],state,path,articles,paragraphs,json.dumps(warnings),error,row['output_hash']))
        return len(rows)

    def status(self):
        states=dict(self.db.execute('SELECT state,COUNT(*) FROM results GROUP BY state'))
        a,p=self.db.execute("SELECT COALESCE(SUM(articles),0),COALESCE(SUM(paragraphs),0) FROM results WHERE state='candidate'").fetchone()
        w=self.db.execute("SELECT COUNT(*) FROM results WHERE state='candidate' AND warnings!='[]'").fetchone()[0]
        result={'parser':self.parser,'observedAt':datetime.now(timezone.utc).isoformat(),'states':states,
                'articleCandidates':a,'paragraphsPreserved':p,'documentsWithWarnings':w,
                'clientIntegrated':False,'legalReview':'not_performed',
                'pausedLowDisk':shutil.disk_usage(self.output).free<2*1024**3}
        tmp=self.output/'status.tmp';tmp.write_text(json.dumps(result,indent=2)+'\n');tmp.replace(self.output/'status.json')
        return result

    def close(self):self.db.close();self.lock.close()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--processed',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--watch',action='store_true')
    parser.add_argument('--limit',type=int,default=100)
    args=parser.parse_args()
    if not 1<=args.limit<=1000:parser.error('limit must be 1..1000')
    processor=Processor(args.processed,args.output)
    try:
        while True:
            count=processor.batch(args.limit);print(json.dumps(processor.status()),flush=True)
            if not args.watch:break
            time.sleep(1 if count else 30)
    finally:processor.close()

if __name__=='__main__':main()
