#!/usr/bin/env python3
"""Resumable official Spanish titles for the complete archived European inventory."""
import json
from pathlib import Path
import sqlite3
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backend'))
from app.eu_bulk import EuropeanArchive,ENDPOINT,PREFIX
from app.bulk import DownloadError,utc


def main():
    root=Path('/workspace/lexmemoria-eu-titles');root.mkdir(exist_ok=True)
    import fcntl
    with (root/'titles.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        archive=EuropeanArchive();db=sqlite3.connect(root/'titles.sqlite3')
        db.execute('CREATE TABLE IF NOT EXISTS titles(work TEXT PRIMARY KEY,celex TEXT,title TEXT,query_hash TEXT,observed_at TEXT)')
        known={r[0] for r in db.execute('SELECT work FROM titles')}
        with archive.db() as source:works=[dict(r) for r in source.execute('SELECT work,celex FROM eu_works ORDER BY work') if r['work'] not in known]
        for start in range(0,len(works),500):
            batch=works[start:start+500]
            for row in batch:
                if not row['work'].startswith('http://publications.europa.eu/resource/cellar/') or any(c in row['work'] for c in '<>"\r\n'):raise ValueError('Invalid work URI')
            query='SELECT ?w ?title WHERE { VALUES ?w {'+' '.join('<'+r['work']+'>' for r in batch)+'} ?e cdm:expression_belongs_to_work ?w ; cdm:expression_uses_language <http://publications.europa.eu/resource/authority/language/SPA> ; cdm:expression_title ?title . }'
            for attempt in range(6):
                archive.acquire_source()
                response=archive.client.post(ENDPOINT,data={'query':PREFIX+query,'format':'application/sparql-results+json'})
                digest=archive.store(response.content)
                if response.status_code==200:break
                if response.status_code in (401,403):raise DownloadError('http_'+str(response.status_code))
                if response.status_code==429 or response.status_code>=500:
                    wait=response.headers.get('Retry-After','60');wait=int(wait) if wait.isdigit() else 60
                    archive.defer_source(min(wait,3600),throttled=response.status_code==429)
                    if attempt<5:time.sleep(min(wait,60));continue
                raise DownloadError('http_'+str(response.status_code))
            values={r['work']:[] for r in batch}
            for value in response.json()['results']['bindings']:
                if value['w']['value'] not in values:raise ValueError('Unexpected source work')
                values[value['w']['value']].append(value['title']['value'])
            with db:
                for row in batch:
                    # Keep every official variant in provenance, choose a stable
                    # nonempty title; never generate a title from legal prose.
                    titles=sorted(set(t for t in values[row['work']] if t.strip()))
                    db.execute('INSERT INTO titles VALUES (?,?,?,?,?)',(row['work'],row['celex'],json.dumps(titles,ensure_ascii=False),digest,utc()))
            report={'observedAt':utc(),'checked':db.execute('SELECT COUNT(*) FROM titles').fetchone()[0],'inventoryRecords':len(known)+len(works),'source':'Publications Office CDM Spanish expression titles'}
            temporary=root/'status.tmp';temporary.write_text(json.dumps(report,indent=2)+'\n');temporary.replace(root/'status.json')
            print(json.dumps(report),flush=True)
        db.close();archive.client.close()

if __name__=='__main__':main()
