import fcntl
import json
import time
from unittest.mock import Mock

import httpx
import pytest

from app.bulk import DownloadError, utc
from app.eu_bulk import EuropeanArchive, transient_error
from app.eu_supervisor import Supervisor, recoverable_blocker, worker_active


def test_recovery_classifies_only_temporary_failures():
    for code in ('http_429','http_502','http_503','network_ReadTimeout','network_ProxyError'):
        assert transient_error(code)
        assert recoverable_blocker('discovery_DownloadError:'+code)
    for code in ('http_403','http_401','http_404','insufficient_disk','redirect_domain_not_allowed','object_integrity',None):
        assert not transient_error(code)
        assert not recoverable_blocker(code)
    assert not recoverable_blocker('worker_OperationalError')


def test_retry_after_survives_a_worker_restart(tmp_path):
    a=EuropeanArchive(tmp_path)
    a.client=httpx.Client(transport=httpx.MockTransport(lambda _:httpx.Response(429,content=b'busy',headers={'Retry-After':'120'})))
    with pytest.raises(DownloadError):a.fetch('https://publications.europa.eu/test')
    assert a.setting('eu_source_resume_after')>=time.time()+115
    reopened=EuropeanArchive(tmp_path)
    assert reopened.rate.next_at>=time.monotonic()+115


def test_inventory_drift_retains_original_count_and_requires_actual_reconciliation(tmp_path):
    a=EuropeanArchive(tmp_path)
    a.set('eu_expected_works',1);a.set('eu_discovery_complete',True)
    with a.db() as db:
        db.executemany("INSERT INTO eu_works(work,celex,items,status) VALUES (?,?,?,'metadata_only')",[('a','a','[]'),('b','b','[]')])
    a.query=lambda _: ([{'count':{'value':'2'}}],a.store(b'actual source response'))
    result=a.reconcile_inventory()
    assert result['consistent'] and result['initial_source_count']==1
    assert a.status()['all_available_records_archived'] is True
    assert a.status()['all_texts_archived'] is False
    a.query=lambda _: ([{'count':{'value':'3'}}],a.store(b'newer source response'))
    assert not a.reconcile_inventory()['consistent']
    assert a.setting('eu_expected_works')==2
    assert not a.status()['all_available_records_archived']
    assert a.setting('eu_initial_expected_works')==1


def test_new_retry_round_preserves_nontransient_failures_and_audit(tmp_path):
    a=EuropeanArchive(tmp_path)
    with a.db() as db:
        db.executemany("INSERT INTO eu_works(work,celex,items,status,error,attempts,next_attempt) VALUES (?,?,?,'failed',?,8,?)",
            [('temporary','a','[]','http_502',0),('denied','b','[]','http_403',0),('later','c','[]','http_503',500)])
    assert a.requeue_transient_failures(at=100)==1
    assert a.requeue_transient_failures(at=100)==0
    with a.db() as db:
        rows={r['work']:dict(r) for r in db.execute('SELECT * FROM eu_works')}
        audit=db.execute("SELECT * FROM incidents WHERE stage='eu_retry_round'").fetchall()
    assert rows['temporary']['status']=='retry' and rows['temporary']['next_attempt']==400
    assert rows['denied']['status']=='failed' and rows['later']['status']=='failed'
    assert len(audit)==1 and audit[0]['code']=='http_502:after_8'


def test_supervisor_adopts_a_live_worker_and_does_not_spawn_another(tmp_path,monkeypatch):
    s=Supervisor(tmp_path)
    spawn=Mock();monkeypatch.setattr('app.eu_supervisor.subprocess.Popen',spawn)
    with (tmp_path/'eu-worker.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        assert worker_active(tmp_path)
        assert s.tick()['state']=='running'
    spawn.assert_not_called()
    assert not worker_active(tmp_path)


def test_supervisor_respects_blockers_and_source_backoff(tmp_path,monkeypatch):
    s=Supervisor(tmp_path)
    spawn=Mock();monkeypatch.setattr('app.eu_supervisor.subprocess.Popen',spawn)
    s.archive.set('eu_blocker','http_403')
    assert s.tick()['state']=='needs_attention'
    assert s.archive.setting('eu_blocker')=='http_403'
    s.archive.set('eu_blocker','discovery_DownloadError:http_503')
    assert s.tick()['state']=='retry_scheduled'
    assert s.archive.setting('eu_blocker') is not None
    s.archive.set('eu_blocker',None)
    s.archive.set('eu_source_resume_after',time.time()+600)
    assert s.tick()['state']=='retry_scheduled'
    spawn.assert_not_called()


def test_supervisor_restarts_a_crashed_worker_with_backoff(tmp_path,monkeypatch):
    s=Supervisor(tmp_path)
    with s.archive.db() as db:db.execute("INSERT INTO eu_works(work,celex,items) VALUES ('work','celex','[]')")
    child=Mock();child.pid=123;child.poll.return_value=None
    spawn=Mock(return_value=child);monkeypatch.setattr('app.eu_supervisor.subprocess.Popen',spawn)
    assert s.tick()['state']=='starting_worker'
    assert s.tick()['state']=='starting_worker'
    assert spawn.call_count==1
    child.poll.return_value=1;child.returncode=1
    assert s.tick()['state']=='retry_scheduled'
    assert spawn.call_count==1
    s.archive.set('eu_worker_restart_after',0)
    assert s.tick()['state']=='starting_worker'
    assert spawn.call_count==2


def test_supervisor_refuses_false_completion_and_refreshes_inventory(tmp_path,monkeypatch):
    s=Supervisor(tmp_path)
    s.archive.set('eu_discovery_complete',True)
    s.archive.set('eu_expected_works',1)
    with s.archive.db() as db:db.execute("INSERT INTO eu_works(work,celex,items,status) VALUES ('work','celex','[]','metadata_only')")
    s.archive.query=lambda _: ([{'count':{'value':'2'}}],s.archive.store(b'source count'))
    child=Mock();child.pid=123;child.poll.return_value=None
    monkeypatch.setattr('app.eu_supervisor.subprocess.Popen',Mock(return_value=child))
    assert s.tick()['state']=='starting_worker'
    assert s.archive.setting('eu_discovery_complete') is False
    with s.archive.db() as db:assert db.execute('SELECT count(*) FROM eu_works').fetchone()[0]==1
    assert not s.archive.status()['all_available_records_archived']


def test_reconciliation_scan_reuses_existing_objects_and_fetches_only_new_manifestations(tmp_path):
    a=EuropeanArchive(tmp_path);a.set('eu_expected_works',2)
    first='http://publications.europa.eu/resource/cellar/a'
    second='http://publications.europa.eu/resource/cellar/b'
    payload=b'%PDF-1.7\n';digest=a.store(payload)
    files=json.dumps([{'type':'pdf','url':'https://publications.europa.eu/a'}])
    with a.db() as db:
        db.execute("INSERT INTO eu_works(work,celex,items,status) VALUES (?,?,?,'complete')",(first,'1',files))
        db.execute('INSERT INTO eu_documents VALUES (?,?,?,?,?)',('https://publications.europa.eu/a',first,digest,'application/pdf',utc()))
    answers=[
        [{'w':{'value':first},'celex':{'value':'1'}},{'w':{'value':second},'celex':{'value':'2'}}],
        [],[],
    ]
    queries=[]
    def query(value):
        queries.append(value)
        return answers.pop(0),a.store(value.encode())
    a.query=query
    a.discovery()
    assert '<'+first+'>' not in queries[1] and '<'+second+'>' in queries[1]
    with a.db() as db:assert db.execute('SELECT count(*) FROM eu_works').fetchone()[0]==2
    assert a.status()['inventory_complete']
    with a.db() as db:assert db.execute('SELECT hash FROM eu_documents WHERE work=?',(first,)).fetchone()[0]==digest


def test_ordered_queue_skips_future_retries_and_keeps_attempt_priority(tmp_path):
    a=EuropeanArchive(tmp_path)
    with a.db() as db:
        for name,attempts,due in [('a',0,time.time()+10000),('b',1,0),('c',0,0)]:
            db.execute('INSERT INTO eu_works(work,celex,items,attempts,next_attempt) VALUES (?,?,?,?,?)',
                (name,name,json.dumps([{'type':'pdf','url':'https://publications.europa.eu/'+name}]),attempts,due))
    calls=[]
    def fetch(url):
        calls.append(url.rsplit('/',1)[-1]);return b'%PDF-1.7\n','application/pdf'
    a.fetch=fetch
    assert a.download_one() and a.download_one()
    assert calls==['c','b']
    assert not a.download_one()
    with a.db() as db:db.execute("UPDATE eu_works SET next_attempt=0 WHERE work='a'")
    assert a.download_one() and calls==['c','b','a']


def test_inventory_lock_wait_can_be_cancelled_without_touching_checkpoints(tmp_path):
    a=EuropeanArchive(tmp_path)
    a.set('eu_cursor','saved')
    with (tmp_path/'eu-inventory.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        a.stop.set()
        a.discovery()
    assert a.setting('eu_cursor')=='saved'


def test_completion_distinguishes_verified_metadata_from_full_text(tmp_path):
    s=Supervisor(tmp_path)
    s.archive.set('eu_discovery_complete',True)
    s.archive.set('eu_expected_works',1)
    s.archive.set('eu_discovery_finished_at',utc())
    with s.archive.db() as db:db.execute("INSERT INTO eu_works(work,celex,items,status) VALUES ('work','celex','[]','metadata_only')")
    s.archive.query=lambda _: ([{'count':{'value':'1'}}],s.archive.store(b'source count'))
    result=s.tick()
    assert result['state']=='watching_source' and result['verification_passed']
    assert result['all_texts_archived'] is False


def test_empty_inventory_cannot_be_reported_as_a_complete_archive(tmp_path):
    s=Supervisor(tmp_path)
    s.archive.set('eu_discovery_complete',True)
    s.archive.set('eu_expected_works',0)
    s.archive.set('eu_discovery_finished_at',utc())
    s.archive.query=lambda _: ([{'count':{'value':'0'}}],s.archive.store(b'source count'))
    assert s.tick()['state']=='needs_attention'


def test_refresh_recovers_a_previously_unavailable_translation(tmp_path):
    a=EuropeanArchive(tmp_path);a.set('eu_expected_works',1);a.set('eu_discovery_complete',True)
    work='http://publications.europa.eu/resource/cellar/a'
    with a.db() as db:db.execute("INSERT INTO eu_works(work,celex,items,status) VALUES (?,?,?,'metadata_only')",(work,'celex','[]'))
    answers=[
        [{'w':{'value':work},'celex':{'value':'celex'}}],
        [{'w':{'value':work},'type':{'value':'pdf'},'i':{'value':'https://publications.europa.eu/a'}}],[],
    ]
    a.query=lambda _: (answers.pop(0),a.store(b'source response'))
    a.discovery(refresh=True)
    assert a.status()['states']=={'pending':1}
    a.fetch=lambda _: (b'%PDF-1.7\n','application/pdf')
    assert a.download_one() and a.status()['states']=={'complete':1}
    assert a.verify()['verification_passed']


def test_final_inventory_must_be_newer_than_the_last_download(tmp_path,monkeypatch):
    s=Supervisor(tmp_path)
    s.archive.set('eu_discovery_complete',True);s.archive.set('eu_expected_works',1)
    s.archive.set('eu_discovery_finished_at','2026-01-01T00:00:00+00:00')
    with s.archive.db() as db:db.execute("INSERT INTO eu_works(work,celex,items,status,finished_at) VALUES ('work','celex','[]','complete','2026-01-02T00:00:00+00:00')")
    child=Mock();child.pid=123;child.poll.return_value=None
    monkeypatch.setattr('app.eu_supervisor.subprocess.Popen',Mock(return_value=child))
    assert s.tick()['state']=='starting_worker'
    assert s.archive.setting('eu_discovery_complete') is False


def test_verified_archive_stays_under_watch_and_rescans_when_due(tmp_path,monkeypatch):
    s=Supervisor(tmp_path)
    a=s.archive;a.set('eu_discovery_complete',True);a.set('eu_expected_works',1)
    a.set('eu_discovery_finished_at',utc())
    with a.db() as db:db.execute("INSERT INTO eu_works(work,celex,items,status) VALUES ('work','celex','[]','metadata_only')")
    query=Mock(return_value=([{'count':{'value':'1'}}],a.store(b'source count')));a.query=query
    assert s.tick()['state']=='watching_source'
    assert s.tick()['state']=='watching_source'
    assert query.call_count==1
    a.set('eu_next_inventory_refresh',time.time()-1)
    child=Mock();child.pid=123;child.poll.return_value=None
    monkeypatch.setattr('app.eu_supervisor.subprocess.Popen',Mock(return_value=child))
    assert s.tick()['state']=='starting_worker'
    assert a.setting('eu_discovery_complete') is False
