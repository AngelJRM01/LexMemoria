"""Daily BOE sumario capture and source-document events; no inferred amendments."""
import hashlib
import re
from datetime import date, datetime, timedelta
from zoneinfo import ZoneInfo
from defusedxml import ElementTree as ET
from .db import Record, now
from .boe import SourceError


def madrid_day(instant=None):
    return (instant or datetime.now(ZoneInfo('Europe/Madrid'))).astimezone(ZoneInfo('Europe/Madrid')).date()


def parse_summary(raw):
    root = ET.fromstring(raw)
    documents = []
    seen = set()
    for item in root.findall('.//item'):
        identifier = item.get('identificador') or item.get('id') or item.findtext('identificador')
        if not identifier or not re.fullmatch(r'BOE-[ABC]-\d{4}-\d+', identifier):
            raise SourceError('Sumario con identificador desconocido; cuarentena')
        if identifier in seen:
            continue
        seen.add(identifier)
        title = item.findtext('titulo')
        if not title or not title.strip():
            raise SourceError('Sumario con disposición sin título; cuarentena')
        documents.append({'officialId': identifier, 'title': title.strip(),
                          'sourceUrl': 'https://www.boe.es/diario_boe/txt.php?id=' + identifier})
    # An empty, structurally valid daily sumario is distinct from an unknown response.
    if root.find('.//sumario') is None and root.tag != 'sumario':
        raise SourceError('Estructura de sumario desconocida')
    return documents


def watch_day(session, client, day):
    civil = date.fromisoformat(day) if isinstance(day, str) and '-' in day else datetime.strptime(str(day), '%Y%m%d').date() if not isinstance(day, date) else day
    key = 'daily:' + civil.isoformat()
    old = session.get(Record, key)
    if old and old.data.get('status') == 'complete':
        return old.data
    run = old or Record(id=key, kind='daily_run', data={})
    run.data = {**run.data, 'day': civil.isoformat(), 'status': 'running', 'startedAt': now()}
    session.add(run)
    session.commit()
    raw = None
    try:
        raw = client.daily(civil.strftime('%Y%m%d'))
        docs = parse_summary(raw)
        created = 0
        for doc in docs:
            # A document appearing twice or in a retry never creates two events.
            event_id = 'publication:' + doc['officialId']
            if not session.get(Record, event_id):
                session.add(Record(id=event_id, kind='legal_event', data={**doc,
                    'type': 'document_published', 'publicationDate': civil.isoformat(),
                    'effectiveFrom': None, 'impact': 'possible', 'editorialState': 'pending',
                    'detectedAt': now(), 'classification': 'requires_analysis'}))
                created += 1
        run.data = {**run.data, 'status': 'complete', 'rawXml': raw.decode(),
                    'hash': hashlib.sha256(raw).hexdigest(), 'documents': len(docs),
                    'eventsCreated': created, 'finishedAt': now(), 'parser': 'boe-summary-1'}
        session.commit()
        return run.data
    except Exception as exc:
        session.rollback()
        run = session.get(Record, key)
        run.data = {**run.data, 'status': 'failed', 'rawXml': (raw or getattr(exc, 'payload', None)).decode(errors='replace') if (raw or getattr(exc, 'payload', None)) else None,
                    'errorType': type(exc).__name__, 'finishedAt': now()}
        session.commit()
        raise


def backfill(session, client, start, end, limit=31):
    first, last = date.fromisoformat(start), date.fromisoformat(end)
    if last < first or (last - first).days + 1 > limit:
        raise ValueError(f'Rango máximo {limit} días, en orden cronológico')
    results = []
    day = first
    while day <= last:
        try:
            run = watch_day(session, client, day)
            results.append({'day': day.isoformat(), 'status': run['status']})
        except Exception:
            results.append({'day': day.isoformat(), 'status': 'failed'})
        day += timedelta(days=1)
    return results


def watch_consolidations(session, client, day, page_size=100, max_pages=100):
    """Resume catalogue updates by offset; queue imports, never certify changes."""
    from sqlalchemy import select
    from .jobs import enqueue
    civil = date.fromisoformat(day) if isinstance(day, str) else day
    key = 'consolidated:' + civil.isoformat()
    run = session.get(Record, key)
    if run and run.data.get('status') == 'complete':
        return run.data
    run = run or Record(id=key, kind='catalogue_run', data={'day': civil.isoformat(), 'offset': 0, 'documents': 0})
    run.data = {**run.data, 'status': 'running', 'startedAt': now()}
    session.add(run); session.commit()
    try:
        for _ in range(max_pages):
            offset = run.data['offset']
            raw = client.catalogue(offset, page_size, start=civil.strftime('%Y%m%d'), end=civil.strftime('%Y%m%d'))
            root = ET.fromstring(raw)
            data = root.find('./data')
            if data is None:
                raise SourceError('Catálogo sin estructura conocida', payload=raw)
            items = data.findall('./item')
            identifiers = []
            for item in items:
                id_ = item.findtext('identificador')
                stamp = item.findtext('fecha_actualizacion')
                if not id_ or not re.fullmatch(r'BOE-A-\d{4}-\d+', id_) or not stamp:
                    raise SourceError('Catálogo con identificador o fecha ausente', payload=raw)
                event_id = 'catalogue:' + hashlib.sha256((id_ + ':' + stamp).encode()).hexdigest()
                if not session.get(Record, event_id):
                    session.add(Record(id=event_id, kind='legal_event', data={
                        'normId': id_, 'title': item.findtext('titulo'), 'type': 'consolidation_detected',
                        'sourceUpdatedAt': stamp, 'detectedAt': now(), 'impact': 'possible', 'editorialState': 'pending',
                        'sourceUrl': 'https://www.boe.es/buscar/act.php?id=' + id_}))
                # Only refresh norms already in the selected corpus, avoiding uncontrolled mass downloads.
                norm = session.get(Record, id_)
                if norm and norm.kind == 'norm': identifiers.append(id_)
            if identifiers:
                enqueue(session, identifiers, 'consolidated:' + civil.isoformat() + ':' + str(offset))
            page_id = key + ':page:' + str(offset)
            if not session.get(Record, page_id):
                session.add(Record(id=page_id, kind='raw_catalogue_page', data={
                    'day': civil.isoformat(), 'offset': offset, 'rawXml': raw.decode(),
                    'hash': hashlib.sha256(raw).hexdigest(), 'downloadedAt': now()}))
            run.data = {**run.data, 'offset': offset + len(items), 'documents': run.data['documents'] + len(items),
                        'status': 'complete' if len(items) < page_size else 'running', 'finishedAt': now()}
            session.commit()
            if run.data['status'] == 'complete': return run.data
        run.data = {**run.data, 'status': 'paused', 'reason': 'page_budget'}
        session.commit()
        return run.data
    except Exception as exc:
        session.rollback(); run = session.get(Record, key)
        run.data = {**run.data, 'status': 'failed', 'errorType': type(exc).__name__, 'finishedAt': now()}
        session.commit(); raise


def daily_cycle(session, client, day=None):
    civil = day or madrid_day() - timedelta(days=1)
    return {'summary': {k: v for k, v in watch_day(session, client, civil).items() if k != 'rawXml'},
            'consolidations': watch_consolidations(session, client, civil)}
