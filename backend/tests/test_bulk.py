from pathlib import Path
import gzip
import hashlib
import threading
import pytest
from app.bulk import Archive, DownloadError, OfficialClient, xml_root


def catalogue(*ids):
    return ('<response><status><code>200</code></status><data>'+''.join(
        f'<item><identificador>{i}</identificador><fecha_actualizacion>20260101T000000Z</fecha_actualizacion><titulo>Norma</titulo></item>' for i in ids)+'</data></response>').encode()


def document(identifier, blocks=True):
    text='<texto><bloque id="a1"><version><p>Texto original</p></version></bloque></texto>' if blocks else '<texto/>'
    return f'<response><status><code>200</code></status><data><metadatos><identificador>{identifier}</identificador><fecha_actualizacion>20260101T000000Z</fecha_actualizacion></metadatos><analisis/><metadata-eli/>{text}</data></response>'.encode()


class Source:
    def __init__(self):
        self.calls=[]; self.lock=threading.Lock(); self.failure=None
    def fetch(self,path):
        with self.lock:self.calls.append(path)
        if self.failure:raise self.failure
        return document(path.rsplit('/',1)[-1]), {'etag':'test'}


def seed(archive,*ids):
    archive.add_page(catalogue(*ids),0,1,'https://www.boe.es/catalogue')
    archive.set('discovery_1',{'offset':len(ids),'complete':True})


def test_inventory_pagination_passes_ten_thousand_and_resumes(tmp_path):
    archive=Archive(tmp_path)
    class Pages:
        fail=True
        offsets=[]
        def fetch(self,path):
            from urllib.parse import parse_qs,urlparse
            offset=int(parse_qs(urlparse(path).query)['offset'][0]);self.offsets.append(offset)
            if offset==2 and self.fail:raise DownloadError('network',retryable=True)
            return (catalogue('BOE-A-2026-1','DOCM-q-2023-90063') if offset==0 else catalogue('BOE-A-2026-2')),{}
    source=Pages()
    with pytest.raises(DownloadError):archive.discover(source,day='2026-11-05',page_size=2)
    assert archive.setting('discovery_1')['offset']==2
    assert archive.summary()['inventory_complete'] is False
    source.fail=False
    archive.discover(source,day='2026-11-05',page_size=2)
    assert source.offsets==[0,2,2]
    assert archive.summary()['identified']==3 and archive.summary()['inventory_complete']
    # A capped initial response does not imply completion: continue at its actual offset.
    archive.set('discovery_2',{'offset':10000,'complete':False})
    class Tail:
        def fetch(self,path):
            assert 'offset=10000' in path
            return catalogue('BOE-A-2026-3'),{}
    archive.discover(Tail(),day='2026-11-05',pass_number=2)
    assert archive.summary()['identified']==4


def test_concurrent_downloads_are_unique_and_raw_xml_is_immutable(tmp_path):
    archive=Archive(tmp_path);seed(archive,'BOE-A-2026-1','BOE-A-2026-2','DOGC-f-2008-90017')
    source=Source();result=archive.run(source,min_free_gb=0)
    assert result['states']=={'complete':3} and result['all_downloads_successful']
    assert len(source.calls)==len(set(source.calls))==3
    assert archive.run(source,min_free_gb=0)['states']=={'complete':3}
    assert len(source.calls)==3
    with archive.db() as db:
        row=db.execute('SELECT * FROM snapshots LIMIT 1').fetchone()
        object_=db.execute('SELECT * FROM objects WHERE hash=?',(row['hash'],)).fetchone()
    raw=gzip.decompress((tmp_path/object_['path']).read_bytes())
    assert raw==document(row['id']) and hashlib.sha256(raw).hexdigest()==row['hash']


def test_retry_releases_job_and_preserves_attempt_count(tmp_path):
    archive=Archive(tmp_path);seed(archive,'BOE-A-2026-1');source=Source();source.failure=DownloadError('http_429',retryable=True,retry_after=60)
    assert archive.run(source,max_jobs=1,min_free_gb=0)['states']=={'retry':1}
    source.failure=None
    with archive.db() as db:db.execute('UPDATE inventory SET next_attempt=0')
    assert archive.run(source,max_jobs=1,min_free_gb=0)['states']=={'complete':1}
    with archive.db() as db:assert db.execute('SELECT attempts FROM inventory').fetchone()[0]==2


def test_metadata_only_and_mismatch_are_not_counted_as_complete(tmp_path):
    archive=Archive(tmp_path);seed(archive,'BOE-A-2026-1','BOE-A-2026-2')
    class Limited:
        def fetch(self,path):
            return (document('BOE-A-2026-1',blocks=False) if path.endswith('-1') else document('BOE-A-2026-999')),{}
    status=archive.run(Limited(),min_free_gb=0)
    assert status['states']=={'metadata_only':1,'quarantined':1}
    assert status['all_downloads_successful'] is False
    with archive.db() as db:
        assert db.execute('SELECT count(*) FROM incidents').fetchone()[0]==1
        assert db.execute('SELECT count(*) FROM objects').fetchone()[0]==3


def test_existing_corrupt_object_cannot_be_silently_reused(tmp_path):
    archive=Archive(tmp_path);raw=document('BOE-A-2026-1');digest=archive.store(raw)
    path=tmp_path/'objects'/digest[:2]/(digest+'.xml.gz');path.write_bytes(b'corrupted')
    with pytest.raises(DownloadError,match='existing_object_integrity'):archive.store(raw)
    assert path.read_bytes()==b'corrupted'


def test_updated_inventory_queues_new_snapshot(tmp_path):
    archive=Archive(tmp_path);seed(archive,'BOE-A-2026-1');archive.run(Source(),min_free_gb=0)
    archive.add_page(catalogue('BOE-A-2026-1').replace(b'20260101',b'20260102'),0,2,'https://www.boe.es/catalogue')
    assert archive.summary()['states']=={'pending':1}
    with archive.db() as db:assert db.execute('SELECT count(*) FROM snapshots').fetchone()[0]==1


def test_policy_denial_stops_worker_instead_of_hitting_whole_catalogue(tmp_path):
    archive=Archive(tmp_path);seed(archive,'BOE-A-2026-1','BOE-A-2026-2','BOE-A-2026-3')
    source=Source();source.failure=DownloadError('http_403')
    status=archive.run(source,min_free_gb=0)
    assert status['blocker']=='http_403' and len(source.calls)<=2
    with pytest.raises(RuntimeError,match='blocker'):archive.run(source,min_free_gb=0)


def test_unsafe_xml_is_rejected():
    with pytest.raises(DownloadError):xml_root(b'<!DOCTYPE r [<!ENTITY x "bad">]><response>&x;</response>')

def test_verify_detects_corruption_and_does_not_claim_completion(tmp_path):
    archive=Archive(tmp_path);seed(archive,'BOE-A-2026-1','BOE-A-2026-2')
    archive.run(Source(),max_jobs=1,min_free_gb=0)
    result=archive.verify()
    assert result['verification_passed'] and not result['download_complete']
    with archive.db() as db:path=db.execute('SELECT path FROM objects WHERE hash=(SELECT hash FROM snapshots LIMIT 1)').fetchone()[0]
    (tmp_path/path).write_bytes(b'bad file')
    result=archive.verify()
    assert not result['verification_passed'] and result['errors'][0]['code']=='object_integrity'

def test_http_error_response_is_preserved_without_publishing_snapshot(tmp_path):
    import httpx
    raw=b'<response><status><code>404</code></status><data/></response>'
    transport=httpx.MockTransport(lambda request:httpx.Response(404,content=raw))
    client=OfficialClient(interval=0,client=httpx.Client(transport=transport))
    archive=Archive(tmp_path);seed(archive,'BOE-A-2026-1')
    result=archive.run(client,max_jobs=1,min_free_gb=0)
    assert result['states']=={'quarantined':1} and result['archived_snapshots']==0
    with archive.db() as db:
        incident=db.execute('SELECT * FROM incidents').fetchone()
        record=db.execute('SELECT path FROM objects WHERE hash=?',(incident['hash'],)).fetchone()
    assert incident['code']=='http_404' and gzip.decompress((tmp_path/record['path']).read_bytes())==raw
