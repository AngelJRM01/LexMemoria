#!/usr/bin/env python3
"""Build source-cited per-norm reading packs and a complete mobile catalogue.

Content is published in a dedicated Git branch. Only the compact catalogue is
bundled in the application; each content file has its own SHA-256 verification.
"""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import sqlite3
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'backend'))
from app.boe import parse_text
from app.prepared import count_cards


def build(archive, output, branch):
    output.mkdir(parents=True,exist_ok=True);(output/'boe').mkdir(exist_ok=True)
    mobile=ROOT/'mobile'
    bundled={n['id']:n for n in json.loads((mobile/'assets/legal-catalogue.json').read_text())['items']}
    db=sqlite3.connect(archive/'archive.sqlite3');db.row_factory=sqlite3.Row
    rows=list(db.execute("SELECT i.id,i.metadata,i.hash,o.path FROM inventory i JOIN objects o ON o.hash=i.hash WHERE i.status='complete' ORDER BY i.id"))
    expected=db.execute('SELECT count(*) FROM inventory').fetchone()[0]
    if len(rows)!=expected:raise ValueError('Source archive still contains gaps')
    entries=[];total=0
    for i,row in enumerate(rows):
        identifier=row['id'];metadata=json.loads(row['metadata'])
        if identifier in bundled:
            pack_bytes=(mobile/bundled[identifier]['bundledAsset']).read_bytes()
            pack=json.loads(gzip.decompress(pack_bytes))
            norm=pack['norm'];units=pack['items']
        else:
            raw=gzip.decompress((archive/row['path']).read_bytes())
            if hashlib.sha256(raw).hexdigest()!=row['hash']:raise ValueError('Corrupt source: '+identifier)
            units=parse_text(raw)
            version=identifier+':archive:'+row['hash'][:24]
            norm={'id':identifier,'title':metadata.get('titulo',identifier),'latestVersion':version,
                  'sourceUrl':metadata.get('url_html_consolidada') or 'https://www.boe.es/buscar/act.php?id='+identifier,
                  'jurisdiction':metadata.get('ambito','No indicado'),'subject':'Normativa',
                  'publicationDate':metadata.get('fecha_publicacion'),'sourceUpdatedAt':metadata.get('fecha_actualizacion'),
                  'effectiveFrom':metadata.get('fecha_vigencia'),'exhausted':metadata.get('vigencia_agotada')=='S',
                  'sourceStatus':metadata.get('estado_consolidacion'),'coverage':'archived','reviewState':'pending',
                  'attribution':'Fuente: Agencia Estatal Boletín Oficial del Estado','informative':True,
                  'licenceUrl':'https://www.boe.es/informacion/aviso_legal/index.php#reutilizacion'}
            pack_bytes=gzip.compress(json.dumps({'schemaVersion':1,'norm':norm,'sourceHash':row['hash'],'items':units},ensure_ascii=False,separators=(',',':')).encode(),mtime=0)
        filename='boe/'+identifier+'.json.gz';(output/filename).write_bytes(pack_bytes)
        count=count_cards(units);total+=count
        entries.append({**norm,'authority':metadata.get('departamento'),'count':count,'packHash':hashlib.sha256(pack_bytes).hexdigest(),
                        'packBytes':len(pack_bytes),'packUrl':f'https://raw.githubusercontent.com/AngelJRM01/LexMemoria/{branch}/{filename}'})
        if (i+1)%250==0:print(json.dumps({'built':i+1,'total':len(rows),'cards':total}),flush=True)
    catalogue={'schemaVersion':1,'source':'BOE','catalogueDay':'2026-11-05','items':entries,
               'norms':len(entries),'literalCards':total,'reviewState':'pending',
               'attribution':'Fuente: Agencia Estatal Boletín Oficial del Estado. Textos consolidados informativos.'}
    encoded=json.dumps(catalogue,ensure_ascii=False,separators=(',',':')).encode()
    (output/'catalogue.json.gz').write_bytes(gzip.compress(encoded,mtime=0))
    (mobile/'assets/corpus-catalogue.json.gz').write_bytes(gzip.compress(encoded,mtime=0))
    (output/'README.md').write_text('# LexMemoria · corpus BOE\n\n'+str(len(entries))+' normas del catálogo consolidado observado el 05/11/2026. Paquetes estructurados con texto e historial de bloques, atribución, fuente y SHA-256. No es cobertura universal ni revisión editorial.\n\nFuente y condiciones: https://www.boe.es/informacion/aviso_legal/index.php#reutilizacion\n\nEl catálogo incorporado en la app permite preparar '+str(total)+' tarjetas base de recuerdo literal. Los formatos de huecos, test literal y reconocimiento de artículos se derivan de fragmentos con fuente, sin inferir interpretación jurídica.\n')
    print(json.dumps({'norms':len(entries),'literalCards':total,'bytes':sum(e['packBytes'] for e in entries)}),flush=True)


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--archive',type=Path,default=Path('/workspace/lexmemoria-corpus'))
    p.add_argument('--output',type=Path,default=Path('/workspace/lexmemoria-distribution'))
    p.add_argument('--branch',default='legal-corpus-20261105')
    args=p.parse_args();build(args.archive,args.output,args.branch)
