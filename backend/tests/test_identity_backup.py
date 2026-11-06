import base64
from datetime import datetime, timedelta, timezone
import json
import os
import sqlite3
import httpx
import pytest
from cryptography import x509
from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.x509.oid import NameOID
from fastapi.testclient import TestClient
from app.identity import FirebaseVerifier, IdentityError
from app.main import create_app
from app.backup import backup, restore

@pytest.fixture
def signed():
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
    name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'Test-only certificate')])
    date = datetime.now(timezone.utc)
    certificate = x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key()).serial_number(1).not_valid_before(date-timedelta(days=1)).not_valid_after(date+timedelta(days=1)).sign(key, hashes.SHA256()).public_bytes(serialization.Encoding.PEM).decode()
    clock = int(date.timestamp())
    client = httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(200, json={'key-1': certificate}, headers={'Cache-Control': 'public,max-age=3600'})))
    verifier = FirebaseVerifier('test-project', client=client, clock=lambda: clock)
    def token(**overrides):
        claims = {'iss': 'https://securetoken.google.com/test-project', 'aud': 'test-project', 'sub': 'provider-user',
                  'exp': clock+3600, 'iat': clock, 'auth_time': clock, 'firebase': {'sign_in_provider': 'google.com'}, **overrides}
        encode = lambda b: base64.urlsafe_b64encode(b).rstrip(b'=').decode()
        message = encode(json.dumps({'alg': 'RS256', 'kid': 'key-1'}).encode())+'.'+encode(json.dumps(claims).encode())
        return message+'.'+encode(key.sign(message.encode(), padding.PKCS1v15(), hashes.SHA256()))
    return verifier, token, clock

def test_identity_verifies_signature_issuer_audience_expiry_provider(signed):
    verifier, token, clock = signed
    assert verifier.verify(token())['subject'] == 'provider-user'
    for bad in [token(aud='other'), token(iss='https://evil.test'), token(exp=clock), token(iat=clock+300), token(sub=''), token(firebase={'sign_in_provider': 'anonymous'}), token()+'tamper']:
        with pytest.raises(IdentityError): verifier.verify(bad)

def test_link_retains_guest_data_and_blocks_other_account(tmp_path, signed):
    app = create_app('sqlite:///'+str(tmp_path/'db')); app.state.identity_verifier = signed[0]
    c = TestClient(app)
    guest = c.post('/v1/auth/guest').json(); h = {'Authorization': 'Bearer '+guest['accessToken']}
    c.post('/v1/decks', headers=h, json={'title': 'Conservado'})
    body = {'idToken': signed[1]()}
    assert c.post('/v1/auth/link', headers=h, json=body).json() == {'linked': True}
    login = c.post('/v1/auth/oidc', json=body).json(); assert login['userId'] == guest['userId']
    other = {'Authorization': 'Bearer '+c.post('/v1/auth/guest').json()['accessToken']}
    assert c.post('/v1/auth/link', headers=other, json=body).status_code == 409
    assert c.get('/v1/decks', headers={'Authorization': 'Bearer '+login['accessToken']}).json()['items'][0]['title'] == 'Conservado'
    assert c.delete('/v1/account?confirmation=ELIMINAR', headers=h).status_code == 200

def test_backup_authenticated_consistent_and_non_destructive(tmp_path):
    source, key, archive, restored = [tmp_path/n for n in ('source.db','key','backup.lexbackup','restored.db')]
    key.write_bytes(os.urandom(32))
    with sqlite3.connect(source) as db:
        db.execute('CREATE TABLE records (id TEXT, body TEXT)'); db.execute('INSERT INTO records VALUES (?,?)', ('version-1','private content'))
    backup(source, archive, key)
    assert b'private content' not in archive.read_bytes()
    restore(archive, restored, key)
    with sqlite3.connect(restored) as db: assert db.execute('SELECT * FROM records').fetchall() == [('version-1','private content')]
    with pytest.raises(FileExistsError): restore(archive, restored, key)
    altered = bytearray(archive.read_bytes()); altered[-1] ^= 1; archive.write_bytes(altered)
    with pytest.raises(InvalidTag): restore(archive, tmp_path/'corrupt.db', key)
    assert not (tmp_path/'corrupt.db').exists()


def test_recent_identity_deletion_and_public_web_configuration(tmp_path,signed,monkeypatch):
    app=create_app('sqlite:///'+str(tmp_path/'identity-delete.db'));app.state.identity_verifier=signed[0]
    c=TestClient(app);session=c.post('/v1/auth/oidc',json={'idToken':signed[1]()} ).json()
    other=c.post('/v1/auth/guest').json();h={'Authorization':'Bearer '+session['accessToken']}
    c.post('/v1/decks',headers=h,json={'title':'Private study'})
    body={'idToken':signed[1](),'confirmation':'ELIMINAR','expectedUserId':session['userId']}
    assert c.post('/v1/account/check-deletion-identity',json=body).json()['verified']
    assert c.post('/v1/account/delete-with-identity',json={**body,'expectedUserId':other['userId']}).status_code==409
    assert c.post('/v1/account/delete-with-identity',json={**body,'idToken':signed[1](auth_time=signed[2]-600)}).status_code==401
    assert c.post('/v1/account/delete-with-identity',json={**body,'confirmation':'no'}).status_code==422
    assert c.post('/v1/account/delete-with-identity',json=body).json()['firebaseDeletion']=='client_must_complete'
    assert c.get('/v1/account/export',headers=h).status_code==401
    assert c.post('/v1/account/delete-with-identity',json=body).json()['alreadyAbsent']
    assert c.get('/v1/account/export',headers={'Authorization':'Bearer '+other['accessToken']}).status_code==200
    monkeypatch.delenv('FIREBASE_WEB_API_KEY',raising=False)
    assert c.get('/v1/public/identity-config').status_code==503
    page=c.get('/account/delete');assert page.status_code==200 and 'nonce-' in page.headers['content-security-policy']
    assert c.get('/account/privacy').status_code==503


def test_google_avatar_is_verified_downloaded_once_and_never_accepts_arbitrary_urls(tmp_path,signed):
    import io
    from PIL import Image
    app=create_app('sqlite:///'+str(tmp_path/'google-avatar.db'));app.state.identity_verifier=signed[0]
    c=TestClient(app);user=c.post('/v1/auth/oidc',json={'idToken':signed[1]()} ).json()
    h={'Authorization':'Bearer '+user['accessToken']}
    output=io.BytesIO();Image.new('RGB',(16,16),'blue').save(output,format='PNG')
    calls=[]
    app.state.avatar_http=httpx.Client(transport=httpx.MockTransport(lambda request:(calls.append(str(request.url)) or httpx.Response(200,content=output.getvalue(),headers={'Content-Type':'image/png'}))))
    url='https://lh3.googleusercontent.com/test-avatar'
    assert c.post('/v1/account/avatar/google',headers=h,json={'idToken':signed[1](picture=url)}).status_code==200
    assert calls==[url]
    before=c.get('/v1/account/avatar',headers=h).json()
    for bad in ['https://127.0.0.1/internal','http://lh3.googleusercontent.com/picture','https://tracker.example/image']:
        assert c.post('/v1/account/avatar/google',headers=h,json={'idToken':signed[1](picture=bad)}).status_code==422
    assert calls==[url] and c.get('/v1/account/avatar',headers=h).json()==before
    other=c.post('/v1/auth/guest').json()
    assert c.post('/v1/account/avatar/google',headers={'Authorization':'Bearer '+other['accessToken']},json={'idToken':signed[1](picture=url)}).status_code==409
    assert calls==[url]


def test_unlink_requires_recent_identity_and_recovery_before_last_credential(tmp_path,signed):
    app=create_app('sqlite:///'+str(tmp_path/'unlink.db'));app.state.identity_verifier=signed[0]
    c=TestClient(app);user=c.post('/v1/auth/oidc',json={'idToken':signed[1]()} ).json()
    h={'Authorization':'Bearer '+user['accessToken']}
    identity=c.get('/v1/account/security',headers=h).json()['linkedIdentities'][0]['id']
    path='/v1/account/identities/'+identity+'/unlink'
    assert c.post(path,headers=h,json={'idToken':signed[1]()} ).status_code==409
    code=c.post('/v1/auth/recovery-code',headers=h).json()['recoveryCode']
    assert c.post(path,headers=h,json={'idToken':signed[1](auth_time=signed[2]-600)}).status_code==401
    assert c.post(path,headers=h,json={'idToken':signed[1]()} ).status_code==200
    assert c.get('/v1/account/security',headers=h).json()['linkedIdentities']==[]
    assert c.post('/v1/auth/recover',json={'recoveryCode':code}).json()['userId']==user['userId']
