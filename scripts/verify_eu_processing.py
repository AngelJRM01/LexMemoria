#!/usr/bin/env python3
"""Independently verify a reproducible sample of persisted EU extractions."""
import argparse
from datetime import datetime, timezone
import gzip
import hashlib
import json
from pathlib import Path
import sqlite3


def verify(archive,output,limit):
    with sqlite3.connect((output/'processing.sqlite3').as_uri()+'?mode=ro',uri=True) as db:
        db.row_factory=sqlite3.Row
        rows=db.execute("SELECT * FROM processed WHERE state='extracted' ORDER BY url LIMIT ?",(limit,)).fetchall()
    checks=[]
    with sqlite3.connect((archive/'archive.sqlite3').as_uri()+'?mode=ro',uri=True) as db:
        for row in rows:
            path=db.execute('SELECT path FROM objects WHERE hash=?',(row['raw_hash'],)).fetchone()
            if not path:raise ValueError('Missing archived original')
            raw_path=(archive/path[0]).resolve();derived_path=(output/row['output_path']).resolve()
            if archive not in raw_path.parents or output not in derived_path.parents:
                raise ValueError('Path outside requested archive/output')
            original=gzip.decompress(raw_path.read_bytes())
            derived=gzip.decompress(derived_path.read_bytes())
            data=json.loads(derived)
            assert hashlib.sha256(original).hexdigest()==row['raw_hash']
            assert hashlib.sha256(derived).hexdigest()==row['output_hash']
            assert data['rawSha256']==row['raw_hash']
            assert data['parser']==row['parser']
            assert data['reviewState']=='pending' and data['legalReview']=='not_performed'
            assert data['unitsAreLegalArticles'] is False
            assert data['paragraphs'] and all(p['text'].strip() for p in data['paragraphs'])
            checks.append({'celex':row['celex'],'rawSha256':row['raw_hash'],
                'derivedSha256':row['output_hash'],'paragraphs':len(data['paragraphs'])})
    return {'observedAt':datetime.now(timezone.utc).isoformat(),'checked':len(checks),
        'scope':'First extracted documents ordered by source URL; sample, not entire EU corpus',
        'allPassed':bool(checks),'clientIntegrated':False,'legalReview':'not_performed','checks':checks}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive',type=Path,required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--report',type=Path,required=True)
    parser.add_argument('--limit',type=int,default=100)
    args=parser.parse_args()
    if not 1<=args.limit<=10000:parser.error('limit must be 1..10000')
    result=verify(args.archive.resolve(),args.output.resolve(),args.limit)
    args.report.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({k:v for k,v in result.items() if k!='checks'}))
