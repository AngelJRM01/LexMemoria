#!/usr/bin/env python3
"""Check every published reading pack against the retained official source."""
import gzip
import hashlib
import json
from pathlib import Path
import sqlite3
import sys
from datetime import datetime, timezone
from defusedxml import ElementTree as ET

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'backend'))
from app.prepared import count_cards

output=Path('/workspace/lexmemoria-distribution')
source=Path('/workspace/lexmemoria-corpus')
catalogue=json.loads(gzip.decompress((output/'catalogue.json.gz').read_bytes()))
db=sqlite3.connect(source/'archive.sqlite3')
rows={r[0]:r[1:] for r in db.execute('SELECT i.id,i.hash,o.path FROM inventory i JOIN objects o ON o.hash=i.hash')}
bundled={n['id']:n for n in json.loads((ROOT/'mobile/assets/legal-catalogue.json').read_text())['items']}
assert set(rows)=={e['id'] for e in catalogue['items']}
cards=0;versions=0;largest=0
for i,entry in enumerate(catalogue['items']):
    data=(output/'boe'/(entry['id']+'.json.gz')).read_bytes()
    assert len(data)==entry['packBytes'] and hashlib.sha256(data).hexdigest()==entry['packHash']
    raw=gzip.decompress(data);largest=max(largest,len(raw));pack=json.loads(raw)
    assert pack['schemaVersion']==1 and pack['norm']['id']==entry['id']
    assert pack['norm']['latestVersion']==entry['latestVersion']
    assert entry['sourceUrl'].startswith('https://')
    actual={u['id']:[v['hash'] for v in u['versions']] for u in pack['items']}
    assert len(actual)==len(pack['items'])
    for unit in pack['items']:
        for version in unit['versions']:
            assert hashlib.sha256(version['xml'].encode()).hexdigest()==version['hash'];versions+=1
            node=ET.fromstring(version['xml'])
            assert version['text']=='\n'.join(''.join(p.itertext()) for p in node)
    if entry['id'] in bundled:
        expected=json.loads(gzip.decompress((ROOT/'mobile'/bundled[entry['id']]['bundledAsset']).read_bytes()))
        assert pack['items']==expected['items'] and pack['sourceHash']==expected['sourceHash']
    else:
        digest,path=rows[entry['id']];official=gzip.decompress((source/path).read_bytes())
        assert hashlib.sha256(official).hexdigest()==digest==pack['sourceHash']
        root=ET.fromstring(official)
        expected={b.get('id'):[hashlib.sha256(ET.tostring(v,encoding='unicode').encode()).hexdigest() for v in b.findall('./version')] for b in root.findall('./data/texto//bloque')}
        assert actual==expected
    n=count_cards(pack['items']);assert n==entry['count'];cards+=n
    if (i+1)%1000==0:print('Verified',i+1,flush=True)
assert cards==catalogue['literalCards'] and len(rows)==catalogue['norms']
report={'verified_at':datetime.now(timezone.utc).isoformat(),'norms':len(rows),'literal_fragments':cards,
        'block_versions':versions,'largest_uncompressed_pack':largest,'verification_passed':True,
        'scope':'Observed BOE consolidated catalogue, not universal legal coverage',
        'legal_review':'not_performed'}
(output/'verification.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')
print(json.dumps(report),flush=True)
