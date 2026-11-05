import gzip
import hashlib
import json
import pytest
from app.db import Record, connect
from app.distribution import import_distribution_pack


def fixture(version='v1', text='Texto original'):
    xml='<version><p>'+text+'</p></version>'
    norm={'id':'BOE-A-2026-1','title':'Ley de prueba','latestVersion':version}
    blocks=[{'id':'a1','title':'Artículo 1','versions':[{'xml':xml,'text':text,'hash':hashlib.sha256(xml.encode()).hexdigest(),'effectiveFrom':'20260101'}]}]
    raw=gzip.compress(json.dumps({'schemaVersion':1,'norm':norm,'items':blocks,'sourceHash':hashlib.sha256(text.encode()).hexdigest()}).encode())
    return {**norm,'packHash':hashlib.sha256(raw).hexdigest(),'packBytes':len(raw),'sourceUrl':'https://www.boe.es','sourceUpdatedAt':'20261105T000000Z'},raw


def test_import_is_idempotent_and_preserves_user_history(tmp_path):
    _,factory=connect('sqlite:///'+str(tmp_path/'test.db'))
    entry,raw=fixture()
    with factory() as s:
        s.add(Record(id='review',kind='review_event',data={'rating':3}));s.commit()
        assert import_distribution_pack(s,entry,raw)=='imported'
        assert import_distribution_pack(s,entry,raw)=='duplicate'
        assert s.get(Record,'review').data=={'rating':3}
        assert s.get(Record,'v1').data['blocks'][0]['versions'][0]['text']=='Texto original'
        assert s.get(Record,entry['id']).data['reviewState']=='pending'
        with pytest.raises(ValueError):import_distribution_pack(s,{**entry,'packHash':'invalid'},raw)


def test_new_version_blocks_stale_cards_without_deleting_previous_source(tmp_path):
    _,factory=connect('sqlite:///'+str(tmp_path/'test.db'))
    with factory() as s:
        entry,raw=fixture();import_distribution_pack(s,entry,raw)
        s.add(Record(id='card',kind='card',data={'citations':[{'normId':entry['id'],'versionId':'v1'}],'front':'Privada'}));s.commit()
        newer,payload=fixture('v2','Texto corregido');import_distribution_pack(s,newer,payload)
        assert s.get(Record,'card').data['blocked'] is True
        assert s.get(Record,'card').data['front']=='Privada'
        assert s.get(Record,'v1') and s.get(Record,'v2')
        s.get(Record,entry['id']).data={**s.get(Record,entry['id']).data,'sourceUpdatedAt':'20270101T000000Z'};s.commit()
        assert import_distribution_pack(s,entry,raw)=='archived_older'
        assert s.get(Record,entry['id']).data['latestVersion']=='v2'
