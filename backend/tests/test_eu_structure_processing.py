import gzip
import hashlib
import json
import sqlite3
import pytest
from app.eu_structure_processing import Processor


def source(tmp_path):
    root=tmp_path/'source';root.mkdir()
    doc={'paragraphs':[{'id':'a','text':'Artículo 1','sourceAnchor':'a'},
                       {'id':'b','text':'Una regla.','sourceAnchor':None}],
         'rawSha256':'original','parser':'fixture','language':'es'}
    encoded=json.dumps(doc).encode();(root/'source.gz').write_bytes(gzip.compress(encoded))
    with sqlite3.connect(root/'processing.sqlite3') as db:
        db.execute('CREATE TABLE processed(url TEXT PRIMARY KEY,celex TEXT,output_path TEXT,output_hash TEXT,raw_hash TEXT,state TEXT)')
        db.execute('INSERT INTO processed VALUES (?,?,?,?,?,?)',('url','32016R0679','source.gz',hashlib.sha256(encoded).hexdigest(),'original','extracted'))
    return root


def test_resume_without_rewriting_previous(tmp_path):
    root=source(tmp_path);out=tmp_path/'out';p=Processor(root,out)
    assert p.batch()==1
    assert p.status()['states']=={'candidate':1}
    files=list(out.glob('objects/*/*'));assert len(files)==1
    stamp=files[0].stat().st_mtime_ns;p.close()
    p=Processor(root,out);assert p.batch()==0
    assert files[0].stat().st_mtime_ns==stamp
    with sqlite3.connect(root/'processing.sqlite3') as db:
        db.execute("INSERT INTO processed VALUES ('pdf','x',NULL,NULL,NULL,'deferred')")
    assert p.batch()==1
    assert p.status()['states']=={'candidate':1,'skipped':1}
    p.close()


def test_corrupt_source_is_not_published(tmp_path):
    root=source(tmp_path)
    with sqlite3.connect(root/'processing.sqlite3') as db:db.execute("UPDATE processed SET output_hash='bad'")
    p=Processor(root,tmp_path/'out');assert p.batch()==1
    assert p.status()['states']=={'failed':1}
    assert not list((tmp_path/'out').glob('objects/*/*'));p.close()


def test_single_writer(tmp_path):
    root=source(tmp_path);out=tmp_path/'out';p=Processor(root,out)
    with pytest.raises(BlockingIOError):Processor(root,out)
    p.close()


def test_nested_output_rejected(tmp_path):
    root=source(tmp_path)
    with pytest.raises(ValueError):Processor(root,root/'derived')


def test_recovered_source_is_revisited_without_new_rowid(tmp_path):
    root=source(tmp_path)
    with sqlite3.connect(root/'processing.sqlite3') as db:db.execute("UPDATE processed SET state='failed'")
    p=Processor(root,tmp_path/'out');assert p.batch()==1
    assert p.status()['states']=={'skipped':1}
    with sqlite3.connect(root/'processing.sqlite3') as db:db.execute("UPDATE processed SET state='extracted'")
    assert p.batch()==1
    assert p.status()['states']=={'candidate':1}
    assert p.batch()==0
    p.close()


def test_memory_limit_uses_verified_pages_instead_of_failing(tmp_path):
    root=source(tmp_path);out=tmp_path/'out';p=Processor(root,out)
    p.memory_limit=8
    assert p.batch()==1
    assert p.status()['states']=={'candidate':1}
    relative=p.db.execute('SELECT path FROM results').fetchone()[0]
    manifest=json.loads(gzip.decompress((out/relative).read_bytes()))
    assert manifest['storageLayout']=='paged-paragraphs'
    assert manifest['paragraphs']==2
    p.close()


def test_changed_derived_source_replaces_old_structure_without_duplicate_url(tmp_path):
    root=source(tmp_path);p=Processor(root,tmp_path/'out');p.batch()
    old=p.db.execute('SELECT path FROM results').fetchone()[0]
    document=json.loads(gzip.decompress((root/'source.gz').read_bytes()))
    document['paragraphs'][1]['text']='Una regla corregida en la extracción.'
    encoded=json.dumps(document).encode();(root/'corrected.gz').write_bytes(gzip.compress(encoded))
    with sqlite3.connect(root/'processing.sqlite3') as db:
        db.execute('UPDATE processed SET output_path=?,output_hash=?',('corrected.gz',hashlib.sha256(encoded).hexdigest()))
    assert p.batch()==1
    assert p.db.execute('SELECT COUNT(*) FROM results').fetchone()[0]==1
    assert p.db.execute('SELECT path FROM results').fetchone()[0]!=old
    assert p.db.execute('SELECT source_output_hash FROM results').fetchone()[0]==hashlib.sha256(encoded).hexdigest()
    p.close()
