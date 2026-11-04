"""BOE XML connector. No automatic legal or educational certification."""
import hashlib
import random
import time
from datetime import datetime, timezone
from defusedxml import ElementTree as ET
import httpx
from sqlalchemy import select
from .db import Record, Audit, uid, now

BASE = 'https://www.boe.es/datosabiertos/api'
PARSER = 'boe-xml-1'


class SourceError(Exception):
    pass


class BoeClient:
    def __init__(self, client=None, sleep=time.sleep):
        self.client = client or httpx.Client(timeout=30, headers={
            'Accept': 'application/xml', 'User-Agent': 'LexMemoria/0.1 (educational legal catalogue)'})
        self.sleep = sleep

    def get(self, path):
        for attempt in range(4):
            try:
                r = self.client.get(BASE + path)
                if r.status_code == 429 or r.status_code >= 500:
                    if attempt < 3:
                        self.sleep(min(60, 2 ** attempt + random.random()))
                        continue
                r.raise_for_status()
                ET.fromstring(r.content)
                self.sleep(.25)
                return r.content
            except (httpx.HTTPError, ET.ParseError, ValueError) as exc:
                if attempt == 3 or isinstance(exc, ET.ParseError):
                    raise SourceError('BOE no disponible o XML no válido') from exc
                self.sleep(2 ** attempt)
        raise SourceError('BOE sin respuesta')

    def catalogue(self, offset=0, limit=100):
        if not 0 <= offset or not 1 <= limit <= 1000:
            raise ValueError('Invalid pagination')
        return self.get(f'/legislacion-consolidada?offset={offset}&limit={limit}')

    def daily(self, civil_date):
        datetime.strptime(civil_date, '%Y%m%d')
        return self.get('/boe/sumario/' + civil_date)


def text_of(root, name):
    node = root.find('.//' + name)
    return ''.join(node.itertext()).strip() if node is not None else None


def parse_text(payload):
    root = ET.fromstring(payload)
    blocks = []
    for block in root.findall('.//bloque'):
        stable = block.get('id')
        if not stable:
            raise SourceError('Bloque sin identificador estable: importación en cuarentena')
        versions = []
        for v in block.findall('./version'):
            # Preserve original markup, including tables and notes.
            xml = ET.tostring(v, encoding='unicode')
            versions.append(dict(publicationDate=v.get('fecha_publicacion'),
                                 effectiveFrom=v.get('fecha_vigencia'),
                                 text='\n'.join(''.join(p.itertext()) for p in v),
                                 xml=xml, hash=hashlib.sha256(xml.encode()).hexdigest()))
        if not versions:
            raise SourceError('Bloque sin versiones: importación en cuarentena')
        blocks.append(dict(id=stable, title=block.get('titulo', stable),
                           type=block.get('tipo', 'unknown'), versions=versions))
    if not blocks:
        raise SourceError('No se han encontrado bloques completos')
    return blocks


def import_norm(session, client, official_id):
    import re
    if not re.fullmatch(r'BOE-A-\d{4}-\d+', official_id):
        raise ValueError('Identificador BOE inválido')
    run = Record(kind='ingestion', data={'officialId': official_id, 'status': 'running', 'parser': PARSER})
    session.add(run)
    session.commit()
    meta = payload = None
    try:
        meta = client.get(f'/legislacion-consolidada/id/{official_id}/metadatos')
        payload = client.get(f'/legislacion-consolidada/id/{official_id}/texto')
        blocks = parse_text(payload)
        metadata = ET.fromstring(meta)
        digest = hashlib.sha256(payload).hexdigest()
        version_id = official_id + ':' + digest[:24]
        if session.get(Record, version_id):
            run.data = {**run.data, 'status': 'duplicate', 'finishedAt': now()}
            session.commit()
            return version_id
        source_url = f'https://www.boe.es/buscar/act.php?id={official_id}'
        session.add(Record(id=version_id, kind='norm_version', data={
            'normId': official_id, 'hash': digest, 'rawXml': payload.decode(),
            'rawMetadata': meta.decode(), 'blocks': blocks, 'downloadedAt': now(),
            'sourceUrl': source_url, 'parser': PARSER, 'reviewState': 'imported'}))
        norm = session.get(Record, official_id)
        data = dict(officialId=official_id, title=text_of(metadata, 'titulo') or official_id,
                    sourceUrl=source_url, source='BOE', jurisdiction='Estado',
                    publicationDate=text_of(metadata, 'fecha_publicacion'),
                    effectiveFrom=text_of(metadata, 'fecha_vigencia'),
                    coverage='imported', reviewState='pending', checkedAt=now(),
                    latestVersion=version_id, blocks=len(blocks), consolidatedInformative=True)
        if norm:
            old_version = norm.data.get('latestVersion')
            # Invalidate dependent cards before making the new snapshot visible.
            for card in session.scalars(select(Record).where(Record.kind == 'card')):
                if any(c.get('normId') == official_id for c in card.data.get('citations', [])):
                    card.data = {**card.data, 'editorialState': 'pending', 'blocked': True}
                    card.revision += 1
            session.add(Record(kind='legal_event', data={
                'normId': official_id, 'fromVersion': old_version, 'toVersion': version_id,
                'type': 'consolidation_available', 'impact': 'possible', 'editorialState': 'pending',
                'sourceUrl': source_url, 'detectedAt': now()}))
            norm.data = data
            norm.revision += 1
        else:
            session.add(Record(id=official_id, kind='norm', data=data))
        run.data = {**run.data, 'status': 'complete', 'versionId': version_id, 'finishedAt': now()}
        session.commit()
        return version_id
    except Exception as exc:
        session.rollback()
        run = session.get(Record, run.id)
        run.data = {**run.data, 'status': 'quarantined', 'error': type(exc).__name__, 'finishedAt': now(),
                    'rawXml': payload.decode(errors='replace') if payload else None,
                    'rawMetadata': meta.decode(errors='replace') if meta else None}
        session.commit()
        raise
