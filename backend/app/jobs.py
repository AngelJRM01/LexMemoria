"""Durable BOE import queue with bounded retries, leases and resumable batches."""
import hashlib
import re
from datetime import datetime, timedelta, timezone
from sqlalchemy import select
from sqlalchemy.orm.exc import StaleDataError
from .db import Record, now, uid
from .boe import import_norm, SourceError


OFFICIAL_ID = re.compile(r'^BOE-A-\d{4}-\d+$')


def enqueue(session, official_ids, batch_key=None):
    ids = list(dict.fromkeys(official_ids))
    if not ids or len(ids) > 10000 or any(not OFFICIAL_ID.fullmatch(i) for i in ids):
        raise ValueError('Entre 1 y 10000 identificadores BOE válidos por lote')
    digest = hashlib.sha256('\n'.join(ids).encode()).hexdigest()
    batch_id = 'batch:' + (hashlib.sha256(batch_key.encode()).hexdigest() if batch_key else digest)
    batch = session.get(Record, batch_id)
    if batch:
        if batch.data['inventoryHash'] != digest:
            raise ValueError('La clave de lote pertenece a otro inventario')
        return batch.id
    session.add(Record(id=batch_id, kind='import_batch', data={
        'inventoryHash': digest, 'total': len(ids), 'createdAt': now()}))
    for position, official_id in enumerate(ids):
        job_id = 'job:' + hashlib.sha256((batch_id + ':' + official_id).encode()).hexdigest()
        session.add(Record(id=job_id, kind='import_job', data={
            'batchId': batch_id, 'officialId': official_id, 'position': position,
            'status': 'pending', 'attempts': 0, 'nextAttemptAt': now()}))
    session.commit()
    return batch_id


def batch_status(session, batch_id):
    batch = session.get(Record, batch_id)
    if not batch or batch.kind != 'import_batch':
        raise ValueError('Lote no encontrado')
    jobs = list(session.scalars(select(Record).where(
        Record.kind == 'import_job', Record.data['batchId'].as_string() == batch_id)))
    counts = {key: sum(j.data['status'] == key for j in jobs)
              for key in ['pending', 'running', 'complete', 'failed', 'quarantined']}
    if sum(counts.values()) != batch.data['total']:
        raise RuntimeError('El inventario del lote no coincide con sus trabajos persistidos')
    return {'id': batch_id, 'total': batch.data['total'], **counts,
            'finished': counts['complete'] + counts['failed'] + counts['quarantined'] == batch.data['total']}


def run_worker(factory, client, limit=20, batch_id=None, at=None, max_attempts=4):
    if not 1 <= limit <= 1000:
        raise ValueError('Límite de trabajos entre 1 y 1000')
    current = at or datetime.now(timezone.utc)
    handled = []
    while len(handled) < limit:
        with factory() as s:
            statement = select(Record).where(Record.kind == 'import_job').order_by(Record.created_at, Record.id)
            if batch_id:
                statement = statement.where(Record.data['batchId'].as_string() == batch_id)
            job = None
            for candidate in s.scalars(statement):
                data = candidate.data
                status = data['status']
                eligible = status == 'pending' and datetime.fromisoformat(data['nextAttemptAt']) <= current
                expired = status == 'running' and datetime.fromisoformat(data['leaseUntil']) <= current
                if eligible or expired:
                    job = candidate
                    break
            if job is None:
                break
            lease = uid()
            job.data = {**job.data, 'status': 'running', 'lease': lease,
                        'leaseUntil': (current + timedelta(minutes=10)).isoformat(),
                        'attempts': job.data['attempts'] + 1, 'startedAt': current.isoformat()}
            try:
                s.commit()  # Optimistic version claim prevents two workers taking the same lease.
            except StaleDataError:
                s.rollback()
                continue
            job_id = job.id
            try:
                version = import_norm(s, client, job.data['officialId'])
                job = s.get(Record, job_id)
                s.refresh(job)
                if job.data.get('lease') != lease:
                    raise RuntimeError('Lease expired while importing')
                job.data = {**job.data, 'status': 'complete', 'versionId': version, 'finishedAt': now()}
            except Exception as exc:
                s.rollback()
                job = s.get(Record, job_id)
                s.refresh(job)
                if job.data.get('lease') != lease:
                    continue
                attempt = job.data['attempts']
                # Parser/security failures remain quarantined; network/source failures retry.
                source_problem = isinstance(exc, SourceError) and exc.retryable
                status = 'pending' if source_problem and attempt < max_attempts else 'failed' if source_problem else 'quarantined'
                job.data = {**job.data, 'status': status, 'errorType': type(exc).__name__,
                            'nextAttemptAt': (current + timedelta(seconds=min(3600, 30 * 2 ** (attempt - 1)))).isoformat(),
                            'finishedAt': now() if status != 'pending' else None}
            s.commit()
            handled.append({'id': job.id, 'status': job.data['status']})
    return handled


def retry_quarantined(session, job_id):
    job = session.get(Record, job_id)
    if not job or job.kind != 'import_job' or job.data['status'] not in ['failed', 'quarantined']:
        raise ValueError('Solo se reintentan trabajos fallidos o en cuarentena tras corregir la causa')
    job.data = {**job.data, 'status': 'pending', 'nextAttemptAt': now(), 'attempts': 0}
    session.commit()
