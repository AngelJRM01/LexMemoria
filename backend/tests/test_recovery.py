import pytest
from fastapi.testclient import TestClient
from app.main import create_app

@pytest.fixture
def c(tmp_path): return TestClient(create_app('sqlite:///' + str(tmp_path / 'db')))

def test_recovery_retains_identity_and_revokes_lost_device(c):
    session = c.post('/v1/auth/guest').json()
    h = {'Authorization': 'Bearer ' + session['accessToken']}
    c.post('/v1/decks', headers=h, json={'title': 'Conservado'})
    code = c.post('/v1/auth/recovery-code', headers=h).json()['recoveryCode']
    recovered = c.post('/v1/auth/recover', json={'recoveryCode': code})
    assert recovered.status_code == 200
    assert recovered.json()['userId'] == session['userId']
    new_h = {'Authorization': 'Bearer ' + recovered.json()['accessToken']}
    assert c.get('/v1/decks', headers=new_h).json()['items'][0]['title'] == 'Conservado'
    assert c.get('/v1/decks', headers=h).status_code == 401
    assert c.post('/v1/auth/refresh', json={'refreshToken': session['refreshToken']}).status_code == 401
    assert c.post('/v1/auth/recover', json={'recoveryCode': code}).status_code == 401
    assert recovered.json()['recoveryCode'] != code
    assert c.post('/v1/auth/recover', json={'recoveryCode': recovered.json()['recoveryCode']}).status_code == 200

def test_replacement_invalidates_old_code_and_exports_have_no_secrets(c):
    session = c.post('/v1/auth/guest').json(); h = {'Authorization': 'Bearer ' + session['accessToken']}
    old = c.post('/v1/auth/recovery-code', headers=h).json()['recoveryCode']
    new = c.post('/v1/auth/recovery-code', headers=h).json()['recoveryCode']
    assert c.post('/v1/auth/recover', json={'recoveryCode': old}).status_code == 401
    exported = c.get('/v1/account/export', headers=h).text
    assert old not in exported and new not in exported and session['accessToken'] not in exported
    assert 'recovery_codes' not in exported

def test_account_deletion_removes_recovery(c):
    session = c.post('/v1/auth/guest').json(); h = {'Authorization': 'Bearer ' + session['accessToken']}
    code = c.post('/v1/auth/recovery-code', headers=h).json()['recoveryCode']
    assert c.delete('/v1/account?confirmation=ELIMINAR', headers=h).status_code == 200
    assert c.post('/v1/auth/recover', json={'recoveryCode': code}).status_code == 401

def test_export_metadata_cannot_be_spoofed_by_private_data(c):
    session = c.post('/v1/auth/guest').json(); h = {'Authorization': 'Bearer ' + session['accessToken']}
    r = c.post('/v1/private', headers=h, json={'kind': 'note', 'data': {'id': 'spoof', 'kind': 'card', 'revision': 99}})
    assert r.status_code == 201
    assert r.json()['id'] != 'spoof' and r.json()['revision'] == 1
    exported = c.get('/v1/account/export', headers=h).json()['records'][0]
    assert exported['kind'] == 'note' and exported['revision'] == 1
