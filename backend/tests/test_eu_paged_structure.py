import gzip
import hashlib
import json
import pytest
from app.eu_paged_structure import prepare
from app.eu_structure import structure_document


def fixture(tmp_path):
    texts=['Considerando lo siguiente:','(1)','Una razón.','HA ADOPTADO EL PRESENTE REGLAMENTO:','Artículo 1','Una regla.','Artículo 2','Otra regla.','ANEXO I','Artículo 1','Una regla del anexo.']
    doc={'parser':'fixture','rawSha256':'original','language':'es','paragraphs':[{'id':str(i),'text':t,'sourceAnchor':None} for i,t in enumerate(texts)]}
    encoded=json.dumps(doc,ensure_ascii=False).encode();path=tmp_path/'source.gz';path.write_bytes(gzip.compress(encoded))
    return path,doc,{'raw_hash':'original','output_hash':hashlib.sha256(encoded).hexdigest(),'celex':'32000R0001','url':'source'}


def test_pages_preserve_exact_order_and_classification(tmp_path):
    path,doc,row=fixture(tmp_path);relative,result=prepare(path,tmp_path/'out',row,page_bytes=120)
    expected=structure_document(doc,row['celex'],row['url'])
    assert len(result['pages'])>1
    records=[]
    for page in result['pages']:
        raw=gzip.decompress((tmp_path/'out'/page['path']).read_bytes())
        assert hashlib.sha256(raw).hexdigest()==page['sha256']
        records.extend(json.loads(line) for line in raw.splitlines())
    assert [r['paragraph'] for r in records]==doc['paragraphs']
    assert [(u['id'],u['kind'],u['title']) for u in result['units']]==[(u['id'],u['kind'],u['title']) for u in expected['units']]
    assert result['warnings']==expected['warnings']
    assert not result['clientReady'] and all(not u['automaticStudyEligible'] for u in result['units'])


def test_corrupt_source_cannot_produce_manifest(tmp_path):
    path,doc,row=fixture(tmp_path);row['output_hash']='wrong'
    with pytest.raises(ValueError,match='source_hash_mismatch'):prepare(path,tmp_path/'out',row)


def test_streaming_keeps_numeric_boolean_and_nested_source_provenance(tmp_path):
    path,doc,row=fixture(tmp_path)
    doc['paragraphs'][0].update(sourcePage=7,confidence=0.98,ocr=True,sourceBox={'x':12,'range':[1,2]})
    encoded=json.dumps(doc,ensure_ascii=False).encode()
    path.write_bytes(gzip.compress(encoded));row['output_hash']=hashlib.sha256(encoded).hexdigest()
    _,result=prepare(path,tmp_path/'out',row,bounded_json_bytes=0)
    records=[]
    for page in result['pages']:
        records.extend(json.loads(line) for line in gzip.decompress((tmp_path/'out'/page['path']).read_bytes()).splitlines())
    assert [r['paragraph'] for r in records]==doc['paragraphs']
