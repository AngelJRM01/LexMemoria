import json
import gzip
import hashlib
import io
import zipfile
import httpx
from app.eu_bulk import EuropeanArchive, select_manifestation, valid_document


def test_manifestation_retains_all_items_and_supports_pdf_variants():
    files=[{'type':'xhtml','url':'html'}, {'type':'xhtml','url':'image'}, {'type':'pdfa1b','url':'pdf'}]
    assert select_manifestation(files)==files[:2]
    assert select_manifestation(files[2:])==files[2:]
    assert select_manifestation([{'type':'unknown','url':'file'}])==[]


def test_validation_distinguishes_text_attachments_and_error_pages():
    assert valid_document(b'%PDF-1.7\n','application/pdf','pdfa1b')
    assert not valid_document(b'<html>error</html>','text/html','pdf')
    assert valid_document(b'<html><body>articulo</body></html>','application/xhtml+xml','xhtml')
    assert valid_document(b'\xff\xd8\xffrest','image/jpeg;charset=UTF-8','xhtml')
    assert not valid_document(b'not an image','image/jpeg','xhtml')
    buffer=io.BytesIO()
    with zipfile.ZipFile(buffer,'w') as package:package.writestr('figure.tif',b'image')
    assert valid_document(buffer.getvalue(),'application/zip','xhtml')


def test_inventory_and_download_are_distinct_and_resumable(tmp_path):
    archive=EuropeanArchive(tmp_path)
    archive.set('eu_expected_works',2)
    w1='http://publications.europa.eu/resource/cellar/a'
    w2='http://publications.europa.eu/resource/cellar/b'
    answers=[
        [{'w':{'value':w1},'celex':{'value':'32026R0001'}},{'w':{'value':w2},'celex':{'value':'32026R0002'}}],
        [{'w':{'value':w1},'type':{'value':'xhtml'},'i':{'value':'https://publications.europa.eu/one'}},
         {'w':{'value':w2},'type':{'value':'pdfa1b'},'i':{'value':'https://publications.europa.eu/two'}}],
        [],
    ]
    def query(_):
        rows=answers.pop(0)
        return rows,archive.store(json.dumps(rows).encode())
    archive.query=query
    archive.discovery()
    assert archive.status()['inventory_complete'] is True
    assert archive.status()['all_texts_archived'] is False
    calls=[]
    def fetch(url):
        calls.append(url)
        return (b'<html>texto</html>','application/xhtml+xml') if url.endswith('one') else (b'%PDF-1.7\n','application/pdf')
    archive.fetch=fetch
    assert archive.download_one()
    assert archive.download_one()
    assert not archive.download_one()
    assert len(calls)==2 and archive.status()['all_texts_archived']
    assert archive.verify()['verification_passed']
    with archive.db() as db:db.execute('DELETE FROM eu_documents WHERE url=?',(calls[0],))
    assert not archive.verify()['verification_passed']


def test_images_alone_do_not_count_as_archived_legal_text(tmp_path):
    archive=EuropeanArchive(tmp_path)
    with archive.db() as db:
        db.execute('INSERT INTO eu_works(work,celex,items) VALUES (?,?,?)',('work','32026R0001',json.dumps([{'type':'xhtml','url':'https://publications.europa.eu/image'}])))
    archive.fetch=lambda _: (b'GIF89aimage','image/gif')
    archive.download_one()
    assert archive.status()['states']=={'failed':1}
    with archive.db() as db:assert db.execute('SELECT error FROM eu_works').fetchone()[0]=='manifestation_without_primary_text'


def test_streamed_documents_verify_original_bytes_without_loading_entire_file(tmp_path):
    archive=EuropeanArchive(tmp_path);raw=b'%PDF-1.7\n'+b'data'*20000
    archive.client=httpx.Client(transport=httpx.MockTransport(lambda _:httpx.Response(200,content=raw,headers={'content-type':'application/pdf'})))
    archive.rate.interval=0
    digest,type_=archive.stream_blob('https://publications.europa.eu/large','pdfa1b')
    assert digest==hashlib.sha256(raw).hexdigest() and type_=='application/pdf'
    with archive.db() as db:record=db.execute('SELECT * FROM objects WHERE hash=?',(digest,)).fetchone()
    assert gzip.decompress((tmp_path/record['path']).read_bytes())==raw
    assert archive.verify()['verification_passed']
    (tmp_path/record['path']).write_bytes(b'corrupt')
    assert not archive.verify()['verification_passed']


def test_formex_zip_contains_primary_xml_and_its_images(tmp_path):
    archive=EuropeanArchive(tmp_path);buffer=io.BytesIO()
    with zipfile.ZipFile(buffer,'w') as package:
        package.writestr('document.xml',b'<?xml version="1.0"?><ACT>Texto</ACT>')
        package.writestr('figure.tif',b'image')
    with archive.db() as db:
        db.execute('INSERT INTO eu_works(work,celex,items) VALUES (?,?,?)',('work','32026R0001',json.dumps([{'type':'fmx4','url':'https://publications.europa.eu/package'}])))
    archive.fetch=lambda _: (buffer.getvalue(),'application/zip;charset=UTF-8')
    archive.download_one()
    assert archive.status()['states']=={'complete':1}
    assert archive.has_primary_text('work')
