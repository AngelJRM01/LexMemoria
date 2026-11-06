#!/usr/bin/env python3
"""Reproducible literal recall cards from attributed, hashed offline BOE packs."""
import gzip
import hashlib
import json
from pathlib import Path
import re
import uuid
import sys
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'backend'))
from app.prepared import passages,study_units,body_text,chunks as legacy_chunks

ROOT=Path(__file__).resolve().parents[1]/'mobile'
output=ROOT/'assets/ready';output.mkdir(exist_ok=True)
catalogue=json.loads((ROOT/'assets/legal-catalogue.json').read_text())['items']
manifest=[];starter=[]
model=(ROOT/'lib/models.dart').read_text()
subjects=dict(re.findall(r"'id': '(BOE-[^']+)'.*?'subject': '([^']+)'",model,re.S))
names=dict(re.findall(r"'id': '(BOE-[^']+)'.*?'short': '([^']+)'",model,re.S))
for norm in catalogue:
    title=norm.get('short',names.get(norm['id'],norm['title']))
    compressed=(ROOT/norm['bundledAsset']).read_bytes()
    assert hashlib.sha256(compressed).hexdigest()==norm['bundledHash']
    pack=json.loads(gzip.decompress(compressed));cards=[];legacy=[]
    for old_unit in pack['items']:
        if not re.match(r'^(?:Art[íi]culo|Art\.?)\s',old_unit['title'],re.I) or not old_unit.get('versions'):continue
        for old_i,_ in enumerate(legacy_chunks(old_unit['title'],old_unit['versions'][-1].get('text',''))):
            legacy.append(str(uuid.uuid5(uuid.NAMESPACE_URL,f"lexmemoria:{norm['id']}:{norm['latestVersion']}:{old_unit['id']}:{old_i}")))
    for unit in study_units(pack['items']):
        if not re.match(r'^(?:Art[íi]culo|Art\.?)\s',unit['title'],re.I):continue
        versions=unit.get('versions',[])
        if not versions:continue
        version=versions[-1];text=body_text(version).strip()
        if not text or text.lower() in ('(derogado)','(derogada)','derogado.','derogada.'):continue
        chunks=passages(unit['title'],text)
        for i,chunk in enumerate(chunks):
            assert len(chunk)<=1200
            cue=' '.join(chunk.split()[:5])
            prompt=f"Completa de memoria esta regla de {unit['title']} de {title}.\n\n{cue}…"
            cards.append({'id':str(uuid.uuid5(uuid.NAMESPACE_URL,f"lexmemoria:{norm['id']}:{norm['latestVersion']}:{unit['id']}:{i}:qa-v3")),
                'deck':title,'front':prompt,'back':chunk,
                'explanation':'Respuesta literal de la fuente. Practica recordarla antes de mostrarla; consulta el artículo para el contexto completo.',
                'type':'qa','normId':norm['id'],'unitId':unit['id'],'versionId':norm['latestVersion'],
                'unitVersionHash':version.get('hash',''),'editorialState':'source_literal','revision':1,'blocked':False})
    asset='assets/ready/'+norm['id']+'.json.gz'
    data=gzip.compress(json.dumps({'cards':cards,'legacyIds':legacy},ensure_ascii=False,separators=(',',':')).encode(),mtime=0)
    (ROOT/asset).write_bytes(data)
    manifest.append({'id':norm['id'],'title':title,'subject':norm.get('subject',subjects.get(norm['id'],'Normativa')),
                     'count':len(cards),'asset':asset,'hash':hashlib.sha256(data).hexdigest()})
    if norm['id']=='BOE-A-1978-31229':starter=cards[:20]
data=gzip.compress(json.dumps({'cards':starter},ensure_ascii=False,separators=(',',':')).encode(),mtime=0)
(output/'starter.json.gz').write_bytes(data)
(output/'index.json').write_text(json.dumps({'items':manifest,'starter':{'asset':'assets/ready/starter.json.gz','hash':hashlib.sha256(data).hexdigest()},
    'attribution':'Fuente: Agencia Estatal Boletín Oficial del Estado. Texto consolidado informativo; ejercicios literales sin revisión editorial.'},ensure_ascii=False,separators=(',',':'))+'\n')
print(json.dumps({'decks':len(manifest),'cards':sum(m['count'] for m in manifest),'starter':len(starter)}))
