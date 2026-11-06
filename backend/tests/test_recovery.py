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


def test_lost_response_can_retry_only_same_secret_attempt(c):
    import secrets
    from app.recovery_receipts import RecoveryReceipt
    from sqlalchemy import select
    session=c.post('/v1/auth/guest').json();h={'Authorization':'Bearer '+session['accessToken']}
    code=c.post('/v1/auth/recovery-code',headers=h).json()['recoveryCode']
    body={'recoveryCode':code,'attemptId':secrets.token_urlsafe(32),'attemptSecret':secrets.token_urlsafe(32)}
    first=c.post('/v1/auth/recover-idempotent',json=body)
    assert first.status_code==200
    # Simulate total response loss: repeat original request rather than using
    # anything returned by the first response.
    second=c.post('/v1/auth/recover-idempotent',json=body)
    assert second.status_code==200 and second.json()==first.json()
    assert c.post('/v1/auth/recover-idempotent',json={**body,'attemptSecret':secrets.token_urlsafe(32)}).status_code==401
    assert c.post('/v1/auth/recover-idempotent',json={**body,'attemptId':secrets.token_urlsafe(32)}).status_code==401
    assert c.post('/v1/auth/recover-idempotent',json={'recoveryCode':first.json()['recoveryCode']}).status_code==422
    recovered_h={'Authorization':'Bearer '+first.json()['accessToken']}
    exported=c.get('/v1/account/export',headers=recovered_h).text
    assert body['attemptSecret'] not in exported and first.json()['refreshToken'] not in exported
    with c.app.state.factory() as s:
        receipt=s.scalar(select(RecoveryReceipt))
        assert first.json()['accessToken'] not in receipt.ciphertext
    assert c.delete('/v1/account?confirmation=ELIMINAR',headers=recovered_h).status_code==200
    assert c.post('/v1/auth/recover-idempotent',json=body).status_code==401
