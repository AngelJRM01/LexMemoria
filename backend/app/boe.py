"""BOE XML connector. No automatic legal or educational certification."""
import hashlib
import random
import time
from datetime import datetime, timezone
from defusedxml import ElementTree as ET
from defusedxml.common import DefusedXmlException
import httpx
from sqlalchemy import select
from .catalogue import index_norm
from .db import Record, Audit, uid, now

BASE = 'https://www.boe.es/datosabiertos/api'
PARSER = 'boe-xml-1'


class SourceError(Exception):
    def __init__(self, message, *, retryable=False, payload=None, source_url=None):
        super().__init__(message)
        self.retryable = retryable
        self.payload = payload
        self.source_url = source_url


class BoeClient:
    def __init__(self, client=None, sleep=time.sleep):
        self.client = client or httpx.Client(timeout=30, headers={
            'Accept': 'application/xml', 'User-Agent': 'LexMemoria/0.1 (educational legal catalogue)'})
        self.sleep = sleep

    def get(self, path):
        url = BASE + path
        for attempt in range(4):
            try:
                response = self.client.get(url)
            except httpx.RequestError as exc:
                if attempt == 3:
                    raise SourceError('BOE no disponible', retryable=True, source_url=url) from exc
                self.sleep(2 ** attempt + random.random())
                continue
            transient = response.status_code == 429 or response.status_code >= 500
            if transient and attempt < 3:
                retry_after = response.headers.get('Retry-After', '')
                delay = min(60, int(retry_after)) if retry_after.isdigit() else 2 ** attempt + random.random()
                self.sleep(max(.25, delay))
                continue
            try:
                response.raise_for_status()
            except httpx.HTTPStatusError as exc:
                raise SourceError('BOE no disponible', retryable=transient,
                                  payload=response.content, source_url=url) from exc
            try:
                root = ET.fromstring(response.content)
                status = root.findtext('./status/code')
                if status is not None and status != '200':
                    raise SourceError('BOE devuelve estado ' + status, retryable=status == '429' or status.startswith('5'),
                                      payload=response.content, source_url=url)
            except (ET.ParseError, DefusedXmlException, ValueError) as exc:
                raise SourceError('XML de BOE no válido; cuarentena', payload=response.content, source_url=url) from exc
            self.sleep(.25)
            return response.content
        raise SourceError('BOE no disponible', retryable=True, source_url=url)

    def catalogue(self, offset=0, limit=100, start=None, end=None):
        if not 0 <= offset or not 1 <= limit <= 1000:
            raise ValueError('Invalid pagination')
        query = f'/legislacion-consolidada?offset={offset}&limit={limit}'
        for key, value in [('from', start), ('to', end)]:
            if value is not None:
                datetime.strptime(value, '%Y%m%d')
                query += '&' + key + '=' + value
        return self.get(query)

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
                    eliUri=text_of(metadata, 'url_eli'), kind=text_of(metadata, 'rango'),
                    authority=text_of(metadata, 'departamento'), sourceUpdatedAt=text_of(metadata, 'fecha_actualizacion'),
                    sourceConsolidationState=text_of(metadata, 'estado_consolidacion'),
                    licenceUrl='https://www.boe.es/informacion/aviso_legal/index.php#reutilizacion',
                    effectiveFrom=text_of(metadata, 'fecha_vigencia'),
                    coverage='imported', reviewState='pending', checkedAt=now(),
                    latestVersion=version_id, blocks=len(blocks), consolidatedInformative=True)
        index_norm(session, official_id, data)
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
                    'rawXml': (payload or getattr(exc, 'payload', None)).decode(errors='replace') if (payload or getattr(exc, 'payload', None)) else None,
                    'rawMetadata': meta.decode(errors='replace') if meta else None}
        session.commit()
        raise
