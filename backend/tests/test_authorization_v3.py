"""Cross-account acceptance tests: private API must never trust caller IDs."""
from datetime import datetime, timezone
import pytest
from fastapi.testclient import TestClient
from app.main import create_app

@pytest.fixture
def identities(tmp_path):
    with TestClient(create_app('sqlite:///' + str(tmp_path / 'v3.db'))) as client:
        a = client.post('/v1/auth/guest').json()
        b = client.post('/v1/auth/guest').json()
        ha = {'Authorization': 'Bearer ' + a['accessToken']}
        hb = {'Authorization': 'Bearer ' + b['accessToken']}
        deck = client.post('/v1/decks', headers=ha, json={'title':'PRIVATE ALICE'}).json()
        card = client.post('/v1/cards', headers=ha, json={'deckId':deck['id'], 'front':'PRIVATE Q', 'back':'PRIVATE A'}).json()
        note = client.post('/v1/private', headers=ha, json={'kind':'note', 'data':{'text':'PRIVATE NOTE'}}).json()
        yield client, a, b, ha, hb, deck, card, note

def test_authenticated_identity_proof_has_no_private_data(identities):
    c,a,b,ha,hb,*_ = identities
    assert c.get('/v1/auth/session').status_code == 401
    assert c.get('/v1/auth/session',headers=ha).json() == {'userId':a['userId']}
    assert c.get('/v1/auth/session',headers=hb).json() == {'userId':b['userId']}
    c.post('/v1/auth/logout',headers=ha)
    assert c.get('/v1/auth/session',headers=ha).status_code == 401

@pytest.mark.parametrize('operation', ['history','edit_card','review','exam','edit_note'])
def test_other_account_cannot_access_or_change_private_entities(identities, operation):
    c,a,b,ha,hb,deck,card,note=identities
    if operation=='history': r=c.get(f"/v1/cards/{card['id']}/history",headers=hb)
    elif operation=='edit_card':
        r=c.put(f"/v1/cards/{card['id']}",headers={**hb,'If-Match':'1'},json={
            'deckId':deck['id'],'front':'stolen','back':'overwritten'})
    elif operation=='review':
        r=c.post('/v1/reviews',headers=hb,json={'cardId':card['id'],'cardRevision':1,'rating':4,
            'occurredAt':datetime.now(timezone.utc).isoformat(),'idempotencyKey':'cross-account-event'})
    elif operation=='exam': r=c.post('/v1/exams/attempts',headers=hb,json={'cardIds':[card['id']]})
    else:r=c.put(f"/v1/private/{note['id']}",headers={**hb,'If-Match':'1'},json={'data':{'text':'overwritten'}})
    assert r.status_code == 404
    own=c.get('/v1/account/export',headers=ha)
    assert 'PRIVATE A' in own.text and 'PRIVATE NOTE' in own.text
    assert 'overwritten' not in own.text
    assert 'PRIVATE' not in c.get('/v1/account/export',headers=hb).text

def test_workspace_and_account_deletion_are_isolated(identities):
    c,a,b,ha,hb,*_=identities
    original={'profile':{'goal':'PRIVATE GOAL'},'notes':{'x':'PRIVATE NOTE'},'courses':[],'follows':[]}
    assert c.put('/v1/workspace',headers={**ha,'If-Match':'0'},json=original).status_code == 200
    assert 'PRIVATE' not in c.get('/v1/workspace',headers=hb).text
    assert c.delete('/v1/account?confirmation=ELIMINAR',headers=hb).status_code == 200
    assert 'PRIVATE GOAL' in c.get('/v1/workspace',headers=ha).text
    assert c.get('/v1/auth/session',headers=ha).status_code == 200
