import base64
import io
import pytest
from sqlalchemy import select
from PIL import Image
from fastapi.testclient import TestClient
from app.main import create_app


def test_avatar_reencoded_private_and_malicious_formats_rejected(tmp_path):
    c=TestClient(create_app('sqlite:///'+str(tmp_path/'avatar.db')))
    auth=lambda:{'Authorization':'Bearer '+c.post('/v1/auth/guest').json()['accessToken']}
    a,b=auth(),auth()
    source=Image.new('RGB',(400,300),'red');exif=Image.Exif();exif[0x010e]='PRIVATE GPS-LIKE METADATA'
    output=io.BytesIO();source.save(output,format='JPEG',exif=exif)
    assert c.put('/v1/account/avatar',headers=a,json={'image':base64.b64encode(output.getvalue()).decode()}).status_code==200
    result=c.get('/v1/account/avatar',headers=a).json()
    raw=base64.b64decode(result['image']);image=Image.open(io.BytesIO(raw))
    assert max(image.size)<=256 and len(image.getexif())==0 and b'PRIVATE' not in raw
    assert c.get('/v1/account/avatar',headers=b).json()['image'] is None
    for bad in ['not-base64',base64.b64encode(b'<svg onload="evil()"/>').decode(),base64.b64encode(b'x'*1000001).decode()]:
        assert c.put('/v1/account/avatar',headers=a,json={'image':bad}).status_code==422
    assert c.delete('/v1/account/avatar',headers=a).status_code==200
    assert c.get('/v1/account/avatar',headers=a).json()['image'] is None


def test_legacy_workspace_save_preserves_newer_sections(tmp_path):
    c=TestClient(create_app('sqlite:///'+str(tmp_path/'workspace.db')))
    h={'Authorization':'Bearer '+c.post('/v1/auth/guest').json()['accessToken']}
    body={'profile':{'dailyGoal':20},'notes':{'a1':'Nota'},'courses':[],'follows':[],
          'readerPositions':{'norm:a1':{'versionId':'v1','hash':'abc','offset':2}},
          'bookmarks':['norm'],'favoriteCards':['c1'],'examHistory':[{'id':'exam-1'}],'activeExam':{'id':'exam-2'}}
    r=c.put('/v1/workspace',headers={**h,'If-Match':'0'},json=body)
    assert r.status_code==200
    assert r.json()['data']==body
    result=c.put('/v1/workspace',headers={**h,'If-Match':str(r.json()['revision'])},json={'profile':{'dailyGoal':30},'notes':{},'courses':[],'follows':[]})
    assert result.status_code==200
    assert result.json()['data']['bookmarks']==['norm']
    assert result.json()['data']['activeExam']=={'id':'exam-2'}
    assert result.json()['data']['readerPositions']==body['readerPositions']


def test_legal_notices_obey_canonical_silence_and_daily_cap(tmp_path,monkeypatch):
    from datetime import datetime,timezone
    from app import notifications
    from app.db import Record
    class Frozen(datetime):
        @classmethod
        def now(cls,tz=None):
            value=datetime(2026,11,6,12,tzinfo=timezone.utc)
            return value.astimezone(tz) if tz else value.replace(tzinfo=None)
    monkeypatch.setattr(notifications,'datetime',Frozen)
    app=create_app('sqlite:///'+str(tmp_path/'legal-silence.db'));c=TestClient(app)
    h={'Authorization':'Bearer '+c.post('/v1/auth/guest').json()['accessToken']}
    with app.state.factory() as s:
        s.add(Record(id='norm',kind='norm',data={'title':'Norma'}));s.commit()
    assert c.post('/v1/legal-updates/subscriptions',headers=h,json={'normIds':['norm']}).status_code==200
    p=c.get('/v1/account/profile',headers=h).json()
    settings={**p['data'],'legalNotifications':True,'noticeDailyLimit':1,'quietStart':'12:00','quietEnd':'14:00'}
    assert c.put('/v1/account/profile',headers={**h,'If-Match':'0'},json=settings).status_code==200
    with app.state.factory() as s:
        for i in range(2):s.add(Record(id=f'event-{i}',kind='legal_event',data={'normId':'norm'}))
        s.commit()
    assert c.get('/v1/notifications',headers=h).json()['items']==[]
    p=c.get('/v1/account/profile',headers=h).json()
    assert c.put('/v1/account/profile',headers={**h,'If-Match':str(p['revision'])},json={**settings,'quietStart':'00:00','quietEnd':'00:00'}).status_code==200
    notices=c.get('/v1/notifications',headers=h).json()['items']
    assert len(notices)==1 and notices[0]['category']=='legal'


def test_study_reminder_respects_completed_goal(tmp_path):
    from datetime import datetime,timezone
    from app.db import Record
    from app.notifications import study_notices
    app=create_app('sqlite:///'+str(tmp_path/'goal.db'));c=TestClient(app)
    account=c.post('/v1/auth/guest').json();h={'Authorization':'Bearer '+account['accessToken']}
    assert c.put('/v1/account/profile',headers={**h,'If-Match':'0'},json={'studyNotifications':True}).status_code==200
    assert c.put('/v1/workspace',headers={**h,'If-Match':'0'},json={'profile':{'dailyGoal':1}}).status_code==200
    deck=c.post('/v1/decks',headers=h,json={'title':'D'}).json()
    c.post('/v1/cards',headers=h,json={'deckId':deck['id'],'front':'Q','back':'A'})
    with app.state.factory() as s:
        event=Record(kind='review_event',owner=account['userId'],data={'occurredAt':datetime.now(timezone.utc).isoformat()})
        s.add(event);s.commit();study_notices(s,account['userId']);s.commit()
        assert not list(s.scalars(select(Record).where(Record.kind=='notification_delivery')))
        s.delete(event);s.commit();study_notices(s,account['userId']);s.commit()
        assert len(list(s.scalars(select(Record).where(Record.kind=='notification_delivery'))))==1
