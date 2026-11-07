#!/usr/bin/env python3
"""Create a dated BOE snapshot from a verified read-only online inventory.

SQLite backup + hardlinks to immutable objects preserve the prior archive.
Only new or source-updated documents are fetched, through the existing limiter.
"""
import argparse,gzip,hashlib,json,os,sqlite3,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'backend'))
from app.bulk import Archive,OfficialClient,BASE,utc


def main():
    p=argparse.ArgumentParser();p.add_argument('--review',type=Path,default=Path('/workspace/lexmemoria-legal-review-20261107'));p.add_argument('--source',type=Path,default=Path('/workspace/lexmemoria-corpus'));p.add_argument('--output',type=Path,default=Path('/workspace/lexmemoria-corpus-20261107'));args=p.parse_args()
    if args.source.resolve()==args.output.resolve():raise ValueError('A dated snapshot must have a distinct directory')
    review=json.loads((args.review/'review.json').read_text());day=review['civilDate']
    args.output.mkdir(exist_ok=True)
    target=args.output/'archive.sqlite3'
    if not target.exists():
        with sqlite3.connect('file:'+str(args.source/'archive.sqlite3')+'?mode=ro',uri=True) as source:
            with sqlite3.connect(target) as destination:source.backup(destination)
    for original in (args.source/'objects').rglob('*.gz'):
        destination=args.output/original.relative_to(args.source);destination.parent.mkdir(parents=True,exist_ok=True)
        if not destination.exists():os.link(original,destination)
    archive=Archive(args.output);offset=0
    while True:
        raw=gzip.decompress((args.review/f'catalogue-{offset}.xml.gz').read_bytes())
        evidence=json.loads((args.review/f'catalogue-{offset}.json').read_text())
        if hashlib.sha256(raw).hexdigest()!=evidence['sha256']:raise ValueError('Online response integrity failed')
        count=archive.add_page(raw,offset,3,evidence['url']);offset+=count
        if count<1000:break
    if offset!=review['inventoryRecords']:raise ValueError('Inventory reconciliation incomplete')
    archive.set('catalogue_day',day);archive.set('discovery_1',{'offset':offset,'complete':True,'finished_at':utc(),'source':'online_review_pass_3'})
    archive.set('snapshot_parent',{'path':str(args.source),'preserved':True})
    print(json.dumps(archive.write_status()),flush=True)
    result=archive.run(OfficialClient(interval=.5),workers=2)
    print(json.dumps(result),flush=True)
    verification=archive.verify();print(json.dumps(verification),flush=True)
    if not verification['verification_passed'] or not result['all_available_sources_archived']:raise SystemExit(2)
if __name__=='__main__':main()
