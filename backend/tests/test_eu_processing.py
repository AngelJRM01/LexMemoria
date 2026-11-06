import gzip
import hashlib
import json
from pathlib import Path
import sqlite3
import pytest
from app.eu_processing import Processor, ExtractionError, extract_html

HTML=b'''<!DOCTYPE html><html><head><title>not a canonical legal title</title></head><body>
<script>never execute private code</script><p id="p1">Texto oficial de prueba con <b>contenido</b> y referencias &amp; citas.</p>
<p>Segundo apartado con una cantidad de texto suficiente para la extraccion.</p></body></html>'''

def fixture_archive(root, raw=HTML, type_='text/html;charset=UTF-8'):
    root.mkdir();digest=hashlib.sha256(raw).hexdigest();relative=f'objects/{digest}.gz'
    (root/'objects').mkdir();(root/relative).write_bytes(gzip.compress(raw))
    with sqlite3.connect(root/'archive.sqlite3') as db:
        db.executescript('''CREATE TABLE eu_works(work TEXT PRIMARY KEY,celex TEXT,status TEXT);
            CREATE TABLE eu_documents(url TEXT PRIMARY KEY,work TEXT,hash TEXT,content_type TEXT);
            CREATE TABLE objects(hash TEXT PRIMARY KEY,path TEXT);''')
        db.execute('INSERT INTO eu_works VALUES (?,?,?)',('work','CELEX-test','running'))
        db.execute('INSERT INTO eu_documents VALUES (?,?,?,?)',('https://source.test/document','work',digest,type_))
        db.execute('INSERT INTO objects VALUES (?,?)',(digest,relative))
    return root/relative

def test_extract_plain_paragraphs_never_claims_articles_or_review():
    result=extract_html(HTML,'text/html;charset=UTF-8')
    assert result['paragraphs'][0]['sourceAnchor']=='p1'
    assert 'contenido y referencias & citas' in result['paragraphs'][0]['text']
    assert 'never execute' not in json.dumps(result)
    assert result['unitsAreLegalArticles'] is False and result['legalReview']=='not_performed'
    assert result['reviewState']=='pending'

@pytest.mark.parametrize('raw,type_',[(b'%PDF-1.5','application/pdf'),(b'login','text/html'),
    (b'<html><body><p>\xff</p></body></html>','text/html;charset=UTF-8')])
def test_invalid_or_unsupported_sources_are_not_silently_converted(raw,type_):
    with pytest.raises(ExtractionError):extract_html(raw,type_)

def test_incremental_processing_keeps_original_archive_unchanged_and_resumes(tmp_path):
    source=tmp_path/'source';out=tmp_path/'derived'
    object_=fixture_archive(source);before=object_.read_bytes()
    db_before=(source/'archive.sqlite3').read_bytes()
    worker=Processor(source,out)
    assert worker.batch()==1
    row=worker.db.execute('SELECT * FROM processed').fetchone()
    assert row['state']=='extracted'
    derived=gzip.decompress((out/row['output_path']).read_bytes())
    assert hashlib.sha256(derived).hexdigest()==row['output_hash']
    assert object_.read_bytes()==before and (source/'archive.sqlite3').read_bytes()==db_before
    worker.close();worker=Processor(source,out)
    assert worker.batch()==0 and worker.status()['states']=={'extracted':1}
    assert worker.status()['clientIntegrated'] is False
    worker.close()

def test_bad_hash_is_quarantined_without_output_or_source_repair(tmp_path):
    source=tmp_path/'source';object_=fixture_archive(source)
    object_.write_bytes(gzip.compress(HTML+b' changed'))
    worker=Processor(source,tmp_path/'derived');worker.batch()
    row=worker.db.execute('SELECT * FROM processed').fetchone()
    assert row['state']=='failed' and row['error']=='source_hash_mismatch'
    assert row['output_path'] is None
    worker.close()

def test_pdf_is_deferred_and_can_never_count_as_extracted(tmp_path):
    source=tmp_path/'source';fixture_archive(source,b'%PDF-1.5','application/pdf')
    worker=Processor(source,tmp_path/'derived');worker.batch()
    assert worker.status()['states']=={'deferred':1}
    worker.close()
