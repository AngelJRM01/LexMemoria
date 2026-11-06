from editorial_helpers import enable_editorial
import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from fastapi.testclient import TestClient
from sqlalchemy import select
from app.accounts import SessionToken, UserSession
from app.db import Token
from app.main import create_app


def auth(session):return {'Authorization':'Bearer '+session['accessToken']}

def second_session(app, user):
    result={'userId':user['userId']}
    with app.state.factory() as s:
        family=UserSession(user_id=user['userId']);s.add(family);s.flush()
        for kind in ('access','refresh'):
            raw=secrets.token_urlsafe(48);result[kind+'Token']=raw
            digest=hashlib.sha256(raw.encode()).hexdigest()
            s.add(Token(digest=digest,kind=kind,user_id=user['userId'],expires_at=(datetime.now(timezone.utc)+timedelta(days=1)).isoformat()));s.flush()
            s.add(SessionToken(digest=digest,session_id=family.id))
        s.commit()
    return result


def test_refresh_logout_and_revocation_are_per_session(tmp_path):
    app=create_app('sqlite:///'+str(tmp_path/'sessions.db'));c=TestClient(app)
    one=c.post('/v1/auth/guest').json();two=second_session(app,one)
    listing=c.get('/v1/account/security',headers=auth(one)).json()
    assert len(listing['sessions'])==2
    current=next(x['id'] for x in listing['sessions'] if x['current'])
    refreshed=c.post('/v1/auth/refresh',json={'refreshToken':one['refreshToken']}).json()
    assert next(x['id'] for x in c.get('/v1/account/security',headers=auth(refreshed)).json()['sessions'] if x['current'])==current
    assert c.post('/v1/auth/logout',headers=auth(two)).status_code==200
    assert c.get('/v1/auth/session',headers=auth(two)).status_code==401
    assert c.post('/v1/auth/refresh',json={'refreshToken':two['refreshToken']}).status_code==401
    three=second_session(app,one)
    stranger=c.post('/v1/auth/guest').json()
    assert c.delete('/v1/account/sessions/'+current,headers=auth(stranger)).status_code==404
    assert c.post('/v1/account/sessions/revoke-others',headers=auth(refreshed)).status_code==200
    assert c.get('/v1/auth/session',headers=auth(three)).status_code==401
    assert c.get('/v1/auth/session',headers=auth(refreshed)).status_code==200


def test_legacy_tokens_preserved_until_explicit_logout(tmp_path):
    app=create_app('sqlite:///'+str(tmp_path/'legacy.db'));c=TestClient(app)
    one=c.post('/v1/auth/guest').json()
    with app.state.factory() as s:
        for row in s.scalars(select(SessionToken)):s.delete(row)
        s.commit()
    assert c.get('/v1/auth/session',headers=auth(one)).status_code==200
    info=c.get('/v1/account/security',headers=auth(one)).json()
    assert info['legacySessionsPresent'] and not info['currentSessionIdentified']
    assert c.post('/v1/account/sessions/revoke-others',headers=auth(one)).status_code==409
    assert c.post('/v1/auth/logout',headers=auth(one)).json()['scope']=='legacy_unidentified'
    assert c.post('/v1/auth/refresh',json={'refreshToken':one['refreshToken']}).status_code==401


def test_profiles_unique_private_and_revision_safe(tmp_path):
    app=create_app('sqlite:///'+str(tmp_path/'profiles.db'));c=TestClient(app)
    a,b=c.post('/v1/auth/guest').json(),c.post('/v1/auth/guest').json()
    body={'displayName':'Ángel','alias':' Angel_01 ','theme':'system'}
    put=lambda account,body,revision:c.put('/v1/account/profile',headers={**auth(account),'If-Match':str(revision)},json=body)
    assert c.get('/v1/account/profile').status_code==401
    assert put(a,body,0).status_code==200
    p=c.get('/v1/account/profile',headers=auth(a)).json()
    assert p['data']['alias']=='angel_01' and not p['data']['allowAliasInvitations']
    assert put(b,body,0).status_code==409
    assert c.get('/v1/account/profile',headers=auth(b)).json()['revision']==0
    assert put(a,{**body,'displayName':'changed'},0).status_code==409
    for fields in ({'alias':'admin'},{'alias':'a'},{'avatar':'https://tracker.test/pixel'},{'quietStart':'25:00'}):
        assert put(a,fields,1).status_code==422
    assert put(a,{**body,'alias':'another_name'},1).status_code==200
    assert put(b,body,0).status_code==409  # Retired aliases cannot be impersonated immediately.
    assert put(b,{**body,'alias':'other_person'},0).status_code==200
    assert c.delete('/v1/account?confirmation=ELIMINAR',headers=auth(a)).status_code==200
    assert c.get('/v1/account/security',headers=auth(a)).status_code==401


def test_server_entitlements_expire_without_locking_personal_data(tmp_path,monkeypatch):
    from app.db import Account
    app=create_app('sqlite:///'+str(tmp_path/'rights.db'));c=TestClient(app)
    user=c.post('/v1/auth/guest').json();admin=c.post('/v1/auth/guest').json()
    h=auth(user);ah=auth(admin)
    c.post('/v1/decks',headers=h,json={'title':'Conservar al caducar'})
    path='/v1/admin/accounts/'+user['userId']+'/entitlement'
    body={'plan':'opositor_pro','expiresAt':(datetime.now(timezone.utc)-timedelta(days=1)).isoformat(),'reason':'Derechos de prueba sin activar cobros reales'}
    assert c.put(path,headers=h,json=body).status_code==403
    with app.state.factory() as s:s.get(Account,admin['userId']).role='admin';s.commit()
    enable_editorial(monkeypatch,c,app)
    assert c.put(path,headers=ah,json=body).json()['billingEnabled'] is False
    rights=c.get('/v1/payments/entitlements',headers=h).json()
    assert rights['plan']=='free' and rights['rights']['basicStudy'] and rights['rights']['personalDataExport']
    assert not rights['commercialLimitsActive'] and not rights['storePurchasesAvailable']
    assert c.get('/v1/decks',headers=h).json()['items'][0]['title']=='Conservar al caducar'
    assert c.get('/v1/account/export',headers=h).status_code==200


def test_batch_card_identity_recovery_includes_legacy_without_leaking_other_users(tmp_path):
    from uuid import uuid5,NAMESPACE_DNS
    c=TestClient(create_app('sqlite:///'+str(tmp_path/'lookup.db')))
    a,b=c.post('/v1/auth/guest').json(),c.post('/v1/auth/guest').json();h=auth(a)
    deck=c.post('/v1/decks',headers=h,json={'title':'Legacy'}).json()
    legacy=c.post('/v1/cards',headers=h,json={'deckId':deck['id'],'front':'Q','back':'A'}).json()
    local_id=str(uuid5(NAMESPACE_DNS,legacy['id']))
    result=c.post('/v1/cards/lookup',headers=h,json={'clientIds':[local_id]}).json()['items']
    assert result[0]['id']==legacy['id'] and result[0]['lookupClientId']==local_id and result[0]['clientId'] is None
    assert c.post('/v1/cards/lookup',headers=auth(b),json={'clientIds':[local_id]}).json()['items']==[]
    assert len(c.get('/v1/account/export',headers=h).json()['records'])==2
