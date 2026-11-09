#!/usr/bin/env python3
"""Archive official CDM base-act relations for every consolidated EU record."""
import fcntl
import json
from pathlib import Path
import re
import sqlite3
import sys
import time
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backend'))
from app.eu_bulk import EuropeanArchive,ENDPOINT,PREFIX
from app.bulk import DownloadError,utc


def main():
    root=Path('/workspace/lexmemoria-eu-parents');root.mkdir(exist_ok=True)
    with (root/'parents.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        archive=EuropeanArchive();db=sqlite3.connect(root/'parents.sqlite3')
        db.execute('CREATE TABLE IF NOT EXISTS parents(work TEXT PRIMARY KEY,celex TEXT,parents TEXT,resources TEXT,query_hash TEXT,observed_at TEXT)')
        known={r[0] for r in db.execute('SELECT work FROM parents')}
        with archive.db() as source:all_works=[dict(r) for r in source.execute("SELECT work,celex FROM eu_works WHERE celex LIKE '0%' ORDER BY work")]
        pending=[r for r in all_works if r['work'] not in known]
        for start in range(0,len(pending),500):
            batch=pending[start:start+500]
            for row in batch:
                if not row['work'].startswith('http://publications.europa.eu/resource/cellar/') or any(c in row['work'] for c in '<>"\r\n'):raise ValueError('Invalid work URI')
            query='SELECT ?w ?parent ?celex WHERE { VALUES ?w {'+' '.join('<'+r['work']+'>' for r in batch)+'} OPTIONAL { ?w cdm:act_consolidated_based_on_resource_legal ?parent . OPTIONAL { ?parent cdm:resource_legal_id_celex ?celex . } } }'
            for attempt in range(6):
                archive.acquire_source();response=archive.client.post(ENDPOINT,data={'query':PREFIX+query,'format':'application/sparql-results+json'});digest=archive.store(response.content)
                if response.status_code==200:break
                if response.status_code in (401,403):raise DownloadError('http_'+str(response.status_code))
                if response.status_code==429 or response.status_code>=500:
                    wait=response.headers.get('Retry-After','60');wait=int(wait) if wait.isdigit() else 60
                    archive.defer_source(min(wait,3600),throttled=response.status_code==429)
                    if attempt<5:time.sleep(min(wait,60));continue
                raise DownloadError('http_'+str(response.status_code))
            values={r['work']:{'parents':set(),'resources':set()} for r in batch}
            for value in response.json()['results']['bindings']:
                work=value['w']['value']
                if work not in values:raise ValueError('Unexpected source work')
                if 'parent' in value:values[work]['resources'].add(value['parent']['value'])
                if 'celex' in value:
                    code=value['celex']['value'].strip()
                    if re.fullmatch(r'(?:[1-9]\d{4}[A-Z].*|[CL]/\d{4}/\d+)',code):values[work]['parents'].add(code)
            with db:
                for row in batch:
                    value=values[row['work']]
                    db.execute('INSERT INTO parents VALUES (?,?,?,?,?,?)',(row['work'],row['celex'],json.dumps(sorted(value['parents'])),json.dumps(sorted(value['resources'])),digest,utc()))
            report={'checked':db.execute('SELECT COUNT(*) FROM parents').fetchone()[0],'consolidatedRecords':len(all_works),'source':'CDM act_consolidated_based_on_resource_legal','observedAt':utc()}
            temporary=root/'status.tmp';temporary.write_text(json.dumps(report,indent=2)+'\n');temporary.replace(root/'status.json');print(json.dumps(report),flush=True)
        db.close();archive.client.close()

if __name__=='__main__':main()
