#!/usr/bin/env python3
"""Read-only online BOE cross-check: current inventory and all bundled core laws.

Official responses are retained outside Git. This is source reconciliation,
not legal certification. Existing archives are never changed by this command.
"""
import argparse,gzip,hashlib,json,sqlite3,sys
from pathlib import Path
from datetime import datetime
from zoneinfo import ZoneInfo
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'backend'))
from app.bulk import OfficialClient,xml_root,BASE,utc
from app.boe import parse_text
from app.prepared import body_text
from defusedxml import ElementTree as ET


def main():
    p=argparse.ArgumentParser();p.add_argument('--output',type=Path,default=Path('/workspace/lexmemoria-legal-review-20261107'));args=p.parse_args()
    args.output.mkdir(exist_ok=True);client=OfficialClient(interval=.5)
    requests=[]
    def fetch(path,key):
        target=args.output/(key+'.xml.gz');evidence=args.output/(key+'.json')
        if target.exists() and evidence.exists():
            raw=gzip.decompress(target.read_bytes());meta=json.loads(evidence.read_text())
            if hashlib.sha256(raw).hexdigest()!=meta['sha256']:raise ValueError('Cached response is corrupt')
        else:
            raw,headers=client.fetch(path)
            meta={'url':BASE+path,'sha256':hashlib.sha256(raw).hexdigest(),'observedAt':utc(),'headers':headers}
            target.write_bytes(gzip.compress(raw,mtime=0));evidence.write_text(json.dumps(meta,indent=2)+'\n')
        requests.append(meta);return raw
    day=datetime.now(ZoneInfo('Europe/Madrid')).date().isoformat();catalogue={};offset=0
    while True:
        path=f'/legislacion-consolidada?offset={offset}&limit=1000&to={day.replace("-","")}'
        root=xml_root(fetch(path,f'catalogue-{offset}'));items=root.findall('./data/item')
        for item in items:
            fields={node.tag:''.join(node.itertext()).strip() for node in item}
            identifier=fields['identificador']
            if identifier in catalogue:raise ValueError('Duplicate current inventory record')
            catalogue[identifier]=fields
        print(json.dumps({'phase':'official_inventory','offset':offset,'records':len(catalogue)}),flush=True)
        offset+=len(items)
        if len(items)<1000:break
    archive=sqlite3.connect('file:/workspace/lexmemoria-corpus/archive.sqlite3?mode=ro',uri=True);archive.row_factory=sqlite3.Row
    local={r['id']:dict(r) for r in archive.execute('SELECT id,metadata,source_updated,hash FROM inventory')}
    new_ids=sorted(set(catalogue)-set(local));missing=sorted(set(local)-set(catalogue))
    updated=[{'normId':id_,'archivedUpdated':local[id_]['source_updated'],'officialUpdated':fields.get('fecha_actualizacion')} for id_,fields in catalogue.items() if id_ in local and fields.get('fecha_actualizacion','')>(local[id_]['source_updated'] or '')]
    core=json.loads((ROOT/'mobile/assets/legal-catalogue.json').read_text())['items'];checks=[]
    for norm in core:
        id_=norm['id'];raw=fetch(f'/legislacion-consolidada/id/{id_}/texto',id_)
        current=parse_text(raw);packed=json.loads(gzip.decompress((ROOT/'mobile'/norm['bundledAsset']).read_bytes()))
        old={u['id']:u for u in packed['items']};new={u['id']:u for u in current}
        changed=[];notes=[]
        for unit_id,u in new.items():
            prior=old.get(unit_id)
            if prior is None or body_text(u['versions'][-1])!=body_text(prior['versions'][-1]):changed.append(unit_id)
            v=ET.fromstring(u['versions'][-1]['xml'])
            for node in v.iter('p'):
                if node.get('class')=='nota_pie':
                    text=''.join(node.itertext()).strip()
                    notes.append({'unitId':unit_id,'title':u['title'],'text':text})
        check={'normId':id_,'title':norm['title'],'sourceUrl':f'https://www.boe.es/buscar/act.php?id={id_}',
          'officialTextSha256':hashlib.sha256(raw).hexdigest(),'archiveTextSha256':packed['sourceHash'],
          'exactSourceHashMatches':hashlib.sha256(raw).hexdigest()==packed['sourceHash'],
          'latestBodyChangedUnits':changed,'removedUnits':sorted(set(old)-set(new)),'editorialNotes':notes,
          'officialUnits':len(current),'latestBodiesMatch':not changed and set(old)==set(new)}
        checks.append(check);print(json.dumps({k:v for k,v in check.items() if k not in ('editorialNotes','title')}),flush=True)
    report={'civilDate':day,'inventoryRecords':len(catalogue),'archivedRecords':len(local),'newIdentifiers':new_ids,
      'missingFromCurrentInventory':missing,'sourceUpdatedSinceArchive':updated,'coreLawsChecked':len(checks),
      'coreLaws':checks,'requests':requests,'originalArchiveModified':False,'humanLegalReview':'not_certified',
      'scope':'Official current BOE inventory plus complete current texts of the twenty bundled laws'}
    (args.output/'review.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'inventoryRecords':len(catalogue),'coreLawsChecked':len(checks),'changedCoreBodies':sum(not c['latestBodiesMatch'] for c in checks),'newIdentifiers':len(new_ids),'updatedSources':len(updated)}),flush=True)
if __name__=='__main__':main()
