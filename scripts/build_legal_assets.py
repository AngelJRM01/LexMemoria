#!/usr/bin/env python3
"""Build attributed, immutable offline packs from successfully imported BOE data."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT/'backend'))
from app.db import connect, Record
from app.boe import text_of
from defusedxml import ElementTree as ET

p = argparse.ArgumentParser()
p.add_argument('--database-url', default='sqlite:///' + str(ROOT/'backend/lexmemoria.db'))
args = p.parse_args()
_, factory = connect(args.database_url)
ids = [v.strip() for v in (ROOT/'docs/normas-iniciales.txt').read_text().splitlines() if v.strip() and not v.startswith('#')]
output = ROOT/'mobile/assets'; (output/'legal').mkdir(parents=True, exist_ok=True)
index = []
with factory() as s:
    for id_ in ids:
        norm = s.get(Record, id_)
        if not norm or norm.kind != 'norm': raise SystemExit('Falta importar: ' + id_)
        version = s.get(Record, norm.data['latestVersion'])
        if not version or version.kind != 'norm_version': raise SystemExit('Versión incompleta: ' + id_)
        if hashlib.sha256(version.data['rawXml'].encode()).hexdigest() != version.data['hash']:
            raise SystemExit('Hash de fuente no válido: ' + id_)
        meta = ET.fromstring(version.data['rawMetadata'])
        data = {**norm.data, 'id': id_, 'eliUri': text_of(meta, 'url_eli'), 'sourceUpdatedAt': text_of(meta, 'fecha_actualizacion'),
                'kind': text_of(meta, 'rango'), 'authority': text_of(meta, 'departamento'),
                'licenceUrl': 'https://www.boe.es/informacion/aviso_legal/index.php#reutilizacion',
                'attribution': 'Basado en datos de la Agencia Estatal Boletín Oficial del Estado',
                'attributionUrl': 'https://www.boe.es', 'informative': True,
                'adaptation': 'Extracción estructurada para lectura; XML de bloque preservado. No es una publicación oficial.'}
        raw = json.dumps({'schemaVersion': 1, 'norm': data, 'sourceHash': version.data['hash'], 'items': version.data['blocks']}, ensure_ascii=False, separators=(',', ':')).encode()
        compressed = gzip.compress(raw, mtime=0)
        asset = 'assets/legal/' + id_ + '.json.gz'
        (ROOT/'mobile'/asset).write_bytes(compressed)
        index.append({**data, 'bundledAsset': asset, 'bundledHash': hashlib.sha256(compressed).hexdigest()})
manifest = {'schemaVersion': 1, 'items': index, 'certified': False}
(output/'legal-catalogue.json').write_text(json.dumps(manifest,ensure_ascii=False,separators=(',', ':'))+'\n')
print(f'{len(index)} paquetes BOE con hashes y atribución; no se certifica vigencia ni contenido educativo.')
