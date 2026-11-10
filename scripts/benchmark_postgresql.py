#!/usr/bin/env python3
"""Synthetic benchmark for the disposable localhost:55433 PostgreSQL fixture only.

Run on an empty lexmemoria_performance database; inserts synthetic data.
Never accepts production URLs or credentials.
"""
import json,gzip,time,statistics,sys
from pathlib import Path
from sqlalchemy import select,insert,event,text
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'backend'))
from app.catalogue import rebuild_index,index_norm
from app.db import connect,Record,RECORD_QUERY_INDEXES
url='postgresql+psycopg://postgres@127.0.0.1:55433/lexmemoria_performance'
e,f=connect(url);catalogue=json.loads(gzip.decompress((ROOT/'mobile/assets/corpus-catalogue.json.gz').read_bytes()))['items']
with e.begin() as c:
 for index in RECORD_QUERY_INDEXES:index.drop(c)
 for start in range(0,len(catalogue),500):c.execute(insert(Record),[{'id':'law:'+n['id'],'kind':'norm','data':n} for n in catalogue[start:start+500]])
 for start in range(0,50000,1000):c.execute(insert(Record),[{'id':f'card-{i:08}','kind':'card','owner':'benchmark-owner','data':{'clientId':f'local-{i:08}','front':'Pregunta '*20,'back':'Respuesta '*20}} for i in range(start,start+1000)])
count=[0]
def track(*_):count[0]+=1
event.listen(e,'before_cursor_execute',track)
def measure(rebuild):
 count[0]=0;t=time.perf_counter()
 with f() as s:rebuild(s)
 statements=count[0];elapsed=(time.perf_counter()-t)*1000
 q=select(Record).where(Record.owner=='benchmark-owner',Record.kind=='card',Record.client_id=='local-00049999')
 with f() as s:
  timings=[]
  for _ in range(30):
   t=time.perf_counter();assert s.scalar(q).id=='card-00049999';timings.append((time.perf_counter()-t)*1000)
  plan=s.execute(text('EXPLAIN '+str(q.compile(e,compile_kwargs={'literal_binds':True})))).scalars().all()
 return {'rebuildMs':elapsed,'rebuildStatements':statements,'lookupMedianMs':statistics.median(timings),'plan':plan}
def old(s):
 for norm in s.scalars(select(Record).where(Record.kind=='norm')):index_norm(s,norm.id,norm.data)
 s.commit()
before=measure(old)
with e.begin() as c:
 from sqlalchemy.schema import CreateIndex
 for index in RECORD_QUERY_INDEXES:c.execute(CreateIndex(index,if_not_exists=True))
after=measure(rebuild_index)
# Transaction hooks and lookup still isolate account even for shared client IDs.
with e.begin() as c:c.execute(insert(Record),[{'id':'other-owner','kind':'card','owner':'different','data':{'clientId':'local-00049999'}}])
with f() as s:assert s.scalar(select(Record).where(Record.owner=='different',Record.kind=='card',Record.client_id=='local-00049999')).id=='other-owner'
report={'engine':'PostgreSQL 18 local disposable container, not Render','norms':len(catalogue),'cards':50000,'before':before,'after':after,'ownerIsolationPassed':True}
(ROOT/'docs/validation/0.8.2/postgresql-performance.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report));e.dispose()
