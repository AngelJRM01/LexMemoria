#!/usr/bin/env python3
"""Audit advertised Spanish files; absence here is not global unavailability."""
import argparse
from datetime import datetime, timezone
import json
import fcntl
from pathlib import Path
import sqlite3
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backend'))
from app.eu_bulk import EuropeanArchive


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archive',type=Path,default=Path('/workspace/lexmemoria-eu-corpus'))
    p.add_argument('--output',type=Path,default=Path('/workspace/lexmemoria-eu-recovery/metadata-audit'))
    args=p.parse_args()
    args.archive=args.archive.resolve();args.output=args.output.resolve()
    if args.archive==args.output or args.archive in args.output.parents or args.output in args.archive.parents:
        p.error('Keep audit output separate from the source archive')
    args.output.mkdir(parents=True,exist_ok=True)
    lock=(args.output/'audit.lock').open('a')
    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
    archive=EuropeanArchive(args.archive)
    with archive.db() as source:works=[dict(r) for r in source.execute("SELECT work,celex FROM eu_works WHERE status='metadata_only' ORDER BY work")]
    db=sqlite3.connect(args.output/'audit.sqlite3')
    db.execute('CREATE TABLE IF NOT EXISTS checked(work TEXT PRIMARY KEY,celex TEXT,state TEXT,evidence TEXT,query_hash TEXT,observed_at TEXT)')
    checked={r[0] for r in db.execute('SELECT work FROM checked')}
    remaining=[r for r in works if r['work'] not in checked]
    for start in range(0,len(remaining),25):
        batch=remaining[start:start+25]
        for row in batch:
            if not row['work'].startswith('http://publications.europa.eu/resource/cellar/') or any(c in row['work'] for c in '<>"\n\r'):
                raise ValueError('Invalid work URI')
        values=' '.join('<'+r['work']+'>' for r in batch)
        query='''SELECT ?w ?title (COUNT(DISTINCT ?m) AS ?manifestations) (COUNT(DISTINCT ?i) AS ?items) WHERE {
          VALUES ?w {'''+values+'''}
          ?e cdm:expression_belongs_to_work ?w ; cdm:expression_uses_language <http://publications.europa.eu/resource/authority/language/SPA> .
          OPTIONAL { ?e cdm:expression_title ?title }
          OPTIONAL { ?m cdm:manifestation_manifests_expression ?e . OPTIONAL { ?i cdm:item_belongs_to_manifestation ?m } }
        } GROUP BY ?w ?title'''
        rows,digest=archive.query(query)
        by_work={r['work']:[] for r in batch}
        for row in rows:
            if row['w']['value'] not in by_work:raise ValueError('Unexpected work')
            by_work[row['w']['value']].append(row)
        at=datetime.now(timezone.utc).isoformat()
        with db:
            for work in batch:
                evidence=by_work[work['work']]
                state=('spanish_expression_missing' if not evidence else
                       'files_advertised' if any(int(r['items']['value']) for r in evidence) else
                       'manifestation_without_item' if any(int(r['manifestations']['value']) for r in evidence) else
                       'no_spanish_manifestation_advertised')
                db.execute('INSERT INTO checked VALUES (?,?,?,?,?,?)',(work['work'],work['celex'],state,json.dumps(evidence,ensure_ascii=False),digest,at))
        report={'observedAt':at,'scope':'Current metadata-only records; CDM advertised Spanish expressions and items only',
                'snapshotRecords':len(works),'checkedRecords':db.execute('SELECT count(*) FROM checked').fetchone()[0],
                'states':dict(db.execute('SELECT state,count(*) FROM checked GROUP BY state')),
                'globalUnavailabilityProven':False,'legalReview':'not_performed'}
        tmp=args.output/'status.tmp';tmp.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');tmp.replace(args.output/'status.json')
        print(json.dumps(report),flush=True)
    db.close();archive.client.close();lock.close()

if __name__=='__main__':main()
