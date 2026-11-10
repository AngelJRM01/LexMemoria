#!/usr/bin/env python3
"""Repeatable synthetic database workload; never connects to production."""
import argparse,gzip,json,sys,time,statistics
from pathlib import Path
from sqlalchemy import event,select,text,insert
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'backend'))
from app.catalogue import rebuild_index
from app.db import connect,Record

def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=Path,required=True);p.add_argument('--database',type=Path,default=Path('/workspace/lexmemoria-performance.sqlite3'));args=p.parse_args()
 engine,factory=connect('sqlite:///'+str(args.database))
 with engine.begin() as c:
  if not c.execute(select(Record.id).limit(1)).first():
   norms=json.loads(gzip.decompress((ROOT/'mobile/assets/corpus-catalogue.json.gz').read_bytes()))['items']
   for start in range(0,len(norms),500):c.execute(insert(Record),[{'id':'law:'+n['id'],'kind':'norm','owner':None,'data':n} for n in norms[start:start+500]])
   for start in range(0,50000,1000):c.execute(insert(Record),[{'id':f'card-{i:08}','kind':'card','owner':'benchmark-owner','data':{'clientId':f'local-{i:08}','front':'Pregunta de prueba '*12,'back':'Respuesta literal '*12}} for i in range(start,start+1000)])
 counter=[0]
 def count(*_):counter[0]+=1
 event.listen(engine,'before_cursor_execute',count)
 results=[]
 for _ in range(2):
  counter[0]=0;t=time.perf_counter()
  with factory() as s:rebuild_index(s)
  results.append({'milliseconds':round((time.perf_counter()-t)*1000,3),'statements':counter[0]})
 client_id=getattr(Record,'client_id',Record.data['clientId'].as_string());query=select(Record).where(Record.owner=='benchmark-owner',Record.kind=='card',client_id=='local-00049999')
 with factory() as s:
  s.scalar(query);timings=[]
  for _ in range(30):
   t=time.perf_counter();assert s.scalar(query).id=='card-00049999';timings.append((time.perf_counter()-t)*1000)
  sql=str(query.compile(engine,compile_kwargs={'literal_binds':True}));plan=[list(r) for r in s.execute(text('EXPLAIN QUERY PLAN '+sql))]
 report={'norms':12457,'cards':50000,'database':'SQLite synthetic fixture, not Render','indexRebuild':results,'cardLookupMedianMs':round(statistics.median(timings),3),'cardLookupP95Ms':round(sorted(timings)[28],3),'lookupPlan':plan}
 args.output.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report));engine.dispose()
if __name__=='__main__':main()
