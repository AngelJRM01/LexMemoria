import gzip
import importlib.util
import json
from pathlib import Path

spec=importlib.util.spec_from_file_location('eu_export',Path(__file__).resolve().parents[2]/'scripts/build_eu_full_library.py')
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)


def test_consolidation_and_correction_are_grouped_without_conflating_editions():
    assert module.group_celex('02016R0679-20160504')==('32016R0679','consolidated','2016-05-04')
    assert module.group_celex('32016R0679R(01)')==('32016R0679','correction',None)
    assert module.group_celex('31960R0009(01)')==('31960R0009(01)','original',None)


def test_exported_pages_preserve_paragraphs_and_bounded_metadata(tmp_path):
    root=tmp_path/'structures';root.mkdir()
    value={'sourceUrl':'official','rawSha256':'raw','warnings':[], 'units':[{'id':'a','title':'Artículo 1','kind':'article_candidate','paragraphs':[{'id':'p','text':'Una regla.'}],'automaticStudyEligible':False}]}
    import hashlib
    raw=module.encoded(value);digest=hashlib.sha256(raw).hexdigest();source=root/(digest+'.json.gz');source.write_bytes(gzip.compress(raw))
    export=module.Exporter(tmp_path/'out');ref=export.reading(root,{'path':source.name,'celex':'32000R0001'})
    manifest=json.loads(gzip.decompress((export.output/ref['path']).read_bytes()))
    page=manifest['pages'][0]
    records=[json.loads(r) for r in gzip.decompress((export.output/page['path']).read_bytes()).splitlines()]
    assert records==[{'unitId':'a','paragraph':{'id':'p','text':'Una regla.'}}]
    assert manifest['paragraphs']==1 and manifest['automaticStudyEligible'] is False
    export.db.close()


def test_amending_acts_not_offered_as_complete_study_text():
    assert not module.study_title_allowed('Reglamento','Reglamento por el que se modifica el Reglamento anterior')
    assert module.study_title_allowed('Reglamento','Reglamento relativo a los datos y por el que se deroga la Directiva anterior')
    assert not module.study_title_allowed('Dictamen','Dictamen sobre los datos')


def test_full_snapshot_verifier_checks_coverage_and_page_unit_assignment(tmp_path):
    spec=importlib.util.spec_from_file_location('eu_verify',Path(__file__).resolve().parents[2]/'scripts/verify_eu_full_library.py')
    verifier=importlib.util.module_from_spec(spec);spec.loader.exec_module(verifier)
    export=module.Exporter(tmp_path)
    page=export.put(module.encoded({'unitId':'a','paragraph':{'id':'p','text':'Una regla.'}})+b'\n',lines=True)
    reading=export.put({'celex':'32000R0001','paragraphs':1,'units':[{'id':'a','firstParagraph':0,'paragraphCount':1}],'pages':[{**page,'firstParagraph':0,'paragraphs':1}]})
    norm=export.put({'id':'EU-32000R0001','celex':'32000R0001','versions':[{'celex':'32000R0001','resources':[{'url':'https://official.test/source','sha256':'a'*64}],'readingDocuments':[reading]}]})
    index=export.put({'items':[{'id':'EU-32000R0001','editions':1,'manifest':norm}]})
    (tmp_path/'catalogue-manifest.json').write_text(json.dumps({'index':index,'norms':1,'records':1,'sourceFiles':1}))
    assert verifier.verify(tmp_path)['paragraphs']==1
    (tmp_path/page['path']).write_bytes(b'corrupted')
    import pytest
    with pytest.raises(ValueError,match='integrity mismatch'):verifier.verify(tmp_path)
    export.db.close()


def test_resume_archives_stale_derived_index_when_input_changes(tmp_path):
    export=module.Exporter(tmp_path,build_id='before')
    with export.db:export.db.execute("INSERT INTO completed VALUES ('old','{}','{}')")
    export.db.close()
    export=module.Exporter(tmp_path,build_id='after')
    assert export.db.execute('SELECT COUNT(*) FROM completed').fetchone()[0]==0
    table=export.db.execute("SELECT name FROM sqlite_master WHERE name LIKE 'completed_superseded_%'").fetchone()[0]
    assert export.db.execute('SELECT COUNT(*) FROM '+table).fetchone()[0]==1
    export.db.close()


def test_verified_gzip_page_is_copied_without_recompressing(tmp_path):
    import hashlib
    raw=b'{"unitId":"a","paragraph":{"id":"p","text":"Una regla."}}\n'
    compressed=gzip.compress(raw,mtime=123);source=tmp_path/'source.gz';source.write_bytes(compressed)
    export=module.Exporter(tmp_path/'out')
    ref=export.copy_page(source,hashlib.sha256(raw).hexdigest())
    assert (export.output/ref['path']).read_bytes()==compressed
    assert ref['sha256']==hashlib.sha256(compressed).hexdigest()
    assert ref['expandedBytes']==len(raw) and ref['encoding']=='jsonl'
    export.db.close()
