from datetime import datetime, timedelta, timezone
import pytest
from sqlalchemy import select
from app.db import connect, Record
from app.jobs import enqueue, run_worker, batch_status, retry_quarantined
from app.monitor import watch_day, backfill, madrid_day, parse_summary
from app.boe import SourceError

TEXT = b'<response><bloque id="a1" titulo="Articulo"><version fecha_vigencia="20260101"><p>Texto</p></version></bloque></response>'
META = b'<response><titulo>Norma de prueba</titulo></response>'
SUMMARY = b'<response><sumario><item identificador="BOE-A-2026-1"><titulo>Disposicion publicada</titulo></item></sumario></response>'
class Source:
    fail = False
    malformed = False
    def get(self, path):
        if self.fail: raise SourceError('BOE no disponible', retryable=True)
        if path.endswith('metadatos'): return META
        return b'<response/>' if self.malformed else TEXT
    def daily(self, day):
        if self.fail: raise SourceError('BOE no disponible', retryable=True)
        return b'<changed/>' if self.malformed else SUMMARY
@pytest.fixture
def db(tmp_path): return connect('sqlite:///' + str(tmp_path / 'db'))[1]

def test_batch_resume(db):
    with db() as s:
        batch = enqueue(s, ['BOE-A-2026-1', 'BOE-A-2026-2', 'BOE-A-2026-1'])
        assert enqueue(s, ['BOE-A-2026-1', 'BOE-A-2026-2']) == batch
    assert len(run_worker(db, Source(), limit=1, batch_id=batch)) == 1
    with db() as s: assert batch_status(s, batch)['complete'] == 1
    run_worker(db, Source(), batch_id=batch)
    assert run_worker(db, Source(), batch_id=batch) == []
    with db() as s:
        result = batch_status(s, batch)
        assert result['complete'] == result['total'] == 2 and result['finished']

def test_backoff(db):
    with db() as s: batch = enqueue(s, ['BOE-A-2026-1'])
    at = datetime.now(timezone.utc) + timedelta(seconds=1)
    source = Source(); source.fail = True
    assert run_worker(db, source, batch_id=batch, at=at)[0]['status'] == 'pending'
    assert run_worker(db, source, batch_id=batch, at=at) == []
    source.fail = False
    assert run_worker(db, source, batch_id=batch, at=at + timedelta(seconds=31))[0]['status'] == 'complete'

def test_quarantine_retry(db):
    with db() as s: batch = enqueue(s, ['BOE-A-2026-1'])
    source = Source(); source.malformed = True
    job = run_worker(db, source, batch_id=batch)[0]
    assert job['status'] == 'quarantined'
    assert run_worker(db, source, batch_id=batch) == []
    source.malformed = False
    with db() as s: retry_quarantined(s, job['id'])
    assert run_worker(db, source, batch_id=batch)[0]['status'] == 'complete'

def test_expired_lease(db):
    with db() as s:
        batch = enqueue(s, ['BOE-A-2026-1'])
        job = s.scalar(select(Record).where(Record.kind == 'import_job'))
        job.data = {**job.data, 'status': 'running', 'lease': 'old', 'leaseUntil': '2020-01-01T00:00:00+00:00'}; s.commit()
    assert run_worker(db, Source(), batch_id=batch)[0]['status'] == 'complete'

def test_daily_deduplication(db):
    with db() as s:
        first = watch_day(s, Source(), '2026-11-04')
        assert first['documents'] == first['eventsCreated'] == 1
        assert watch_day(s, Source(), '2026-11-04') == first
        assert watch_day(s, Source(), '2026-11-05')['eventsCreated'] == 0
        events = list(s.scalars(select(Record).where(Record.kind == 'legal_event')))
        assert len(events) == 1
        assert events[0].data['effectiveFrom'] is None
        assert events[0].data['editorialState'] == 'pending'

def test_backfill_retries_failed_dates(db):
    source = Source(); source.fail = True
    with db() as s:
        result = backfill(s, source, '2026-11-01', '2026-11-03')
        assert len(result) == 3 and all(r['status'] == 'failed' for r in result)
        source.fail = False
        assert all(r['status'] == 'complete' for r in backfill(s, source, '2026-11-01', '2026-11-03'))
        with pytest.raises(ValueError): backfill(s, source, '2026-01-01', '2026-12-31')

def test_unknown_structure_quarantined(db):
    with pytest.raises(SourceError): parse_summary(b'<response><sumario><item><titulo>X</titulo></item></sumario></response>')
    assert parse_summary(b'<response><sumario/></response>') == []
    source = Source(); source.malformed = True
    with db() as s:
        with pytest.raises(SourceError): watch_day(s, source, '2026-11-04')
        assert s.get(Record, 'daily:2026-11-04').data['status'] == 'failed'

def test_madrid_dst_day_does_not_repeat():
    a = datetime(2026, 10, 25, 0, 30, tzinfo=timezone.utc)
    b = datetime(2026, 10, 25, 1, 30, tzinfo=timezone.utc)
    assert madrid_day(a) == madrid_day(b)

def test_legal_event_cursor_has_no_duplicates(tmp_path):
    from app.main import create_app
    from fastapi.testclient import TestClient
    app = create_app('sqlite:///' + str(tmp_path / 'api'))
    with app.state.factory() as s:
        for i in range(5): s.add(Record(id=f'event-{i}', kind='legal_event', data={'type': 'document_published'}))
        s.commit()
    c = TestClient(app)
    first = c.get('/v1/legal-updates?limit=2').json()
    second = c.get('/v1/legal-updates', params={'limit': 2, 'cursor': first['nextCursor']}).json()
    assert len(first['items']) == len(second['items']) == 2
    assert not {v['id'] for v in first['items']} & {v['id'] for v in second['items']}
    assert c.get('/v1/legal-updates?limit=0').status_code == 422
