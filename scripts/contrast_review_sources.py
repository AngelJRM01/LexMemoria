#!/usr/bin/env python3
"""Fresh official evidence for a content review; does not certify manual reading."""
from pathlib import Path
import gzip,hashlib,io,json,sqlite3,sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backend'))
from app.bulk import OfficialClient,utc
from app.boe import parse_text
from app.prepared import body_text
from app.eu_bulk import EuropeanArchive
ROOT=Path('/workspace/lexmemoria-content-review-20261109');ROOT.mkdir(exist_ok=True)

def save(name,raw,url):
    (ROOT/(name+'.gz')).write_bytes(gzip.compress(raw,mtime=0))
    return {'url':url,'sha256':hashlib.sha256(raw).hexdigest(),'observedAt':utc()}

def main():
    online=json.loads(Path('/workspace/lexmemoria-legal-review-20261109/review.json').read_text());client=OfficialClient();checks=[]
    for entry in online['sourceUpdatedSinceArchive']:
        code=entry['normId'];path='/legislacion-consolidada/id/'+code+'/texto';raw,_=client.fetch(path)
        meta=save(code,raw,'https://www.boe.es/datosabiertos/api'+path)
        old=json.loads(gzip.decompress((Path('/workspace/lexmemoria-distribution-20261107/boe')/(code+'.json.gz')).read_bytes()))
        current=parse_text(raw);before={u['id']:u for u in old['items']};after={u['id']:u for u in current}
        changed=[u for u in after if u not in before or body_text(after[u]['versions'][-1])!=body_text(before[u]['versions'][-1])]
        row={**meta,'identifier':code,'bodyChangedUnits':changed,'removedUnits':sorted(set(before)-set(after)),'exactSourceMatches':meta['sha256']==old['sourceHash']}
        checks.append(row);(ROOT/'boe-delta-checks.json').write_text(json.dumps(checks,ensure_ascii=False,indent=2)+'\n');print(json.dumps({'source':'BOE','identifier':code,'changed':len(changed),'exactSourceMatches':row['exactSourceMatches']}),flush=True)
    archive=EuropeanArchive();eu=[]
    with archive.db() as db:
        for code in ['32016R0679','32019L1152','32021D0914']:
            row=db.execute("SELECT d.url,d.hash,d.content_type FROM eu_documents d JOIN eu_works w ON w.work=d.work WHERE w.celex=? AND d.content_type LIKE '%html%' LIMIT 1",(code,)).fetchone()
            raw,mime=archive.fetch(row['url']);meta=save(code+'-official',raw,row['url'].replace('http://','https://',1));eu.append({**meta,'identifier':code,'archivedSha256':row['hash'],'exactSourceMatches':meta['sha256']==row['hash'],'mime':mime})
            (ROOT/'eu-fresh-checks.json').write_text(json.dumps(eu,ensure_ascii=False,indent=2)+'\n');print(json.dumps(eu[-1]),flush=True)
    archive.client.close()
if __name__=='__main__':main()
