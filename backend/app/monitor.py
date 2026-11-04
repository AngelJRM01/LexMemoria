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
