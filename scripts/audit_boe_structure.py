#!/usr/bin/env python3
"""Audit every archived BOE reading pack without modifying official originals."""
import argparse,gzip,hashlib,json,sys,time
from pathlib import Path
from collections import Counter
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'backend'))
from app.prepared import unit_kind,study_units,count_cards

def main():
    p=argparse.ArgumentParser();p.add_argument('--distribution',type=Path,default=Path('/workspace/lexmemoria-distribution'));p.add_argument('--report',type=Path,default=ROOT/'docs/validation/boe-structure-0.7.0.json');p.add_argument('--refresh-catalogue',action='store_true');args=p.parse_args()
    manifest=json.loads(gzip.decompress((args.distribution/'catalogue.json.gz').read_bytes()))
    kinds=Counter();rows=[];issues=[];started=time.monotonic()
    for i,norm in enumerate(manifest['items']):
        path=args.distribution/'boe'/(norm['id']+'.json.gz');raw=path.read_bytes()
        if hashlib.sha256(raw).hexdigest()!=norm['packHash']:raise ValueError('Pack hash mismatch: '+norm['id'])
        pack=json.loads(gzip.decompress(raw));units=pack['items'];counts=Counter(unit_kind(u) for u in units);kinds.update(counts)
        articles=study_units(units);ids=[u['id'] for u in units]
        if len(ids)!=len(set(ids)):issues.append({'normId':norm['id'],'issue':'duplicate_unit_id'})
        rows.append({'normId':norm['id'],'units':len(units),'classification':dict(counts),'eligibleArticles':len(articles),'qaBefore':norm['count'],'qaArticlesOnly':count_cards(units)})
        if (i+1)%250==0:print(json.dumps({'checked':i+1,'total':len(manifest['items']),'elapsedSeconds':round(time.monotonic()-started,1)}),flush=True)
    report={'normsChecked':len(rows),'allNormsChecked':len(rows)==manifest['norms'],'source':'BOE consolidated archive','packHashesVerified':True,'originalsModified':False,'classification':dict(kinds),'issues':issues,'norms':rows,'elapsedSeconds':round(time.monotonic()-started,2),'legalReview':'not_performed'}
    if args.refresh_catalogue:
        by_id={r['normId']:r for r in rows}
        for item in manifest['items']:
            item['count']=by_id[item['id']]['qaArticlesOnly']
            item['articleCount']=by_id[item['id']]['eligibleArticles']
        manifest['literalCards']=sum(i['count'] for i in manifest['items'])
        manifest['exerciseGenerator']='article-passages-v3'
        encoded=gzip.compress(json.dumps(manifest,ensure_ascii=False,separators=(',',':')).encode(),mtime=0)
        (args.distribution/'catalogue.json.gz').write_bytes(encoded)
        (ROOT/'mobile/assets/corpus-catalogue.json.gz').write_bytes(encoded)
    args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n');print(json.dumps({k:v for k,v in report.items() if k!='norms'}),flush=True)
if __name__=='__main__':main()
