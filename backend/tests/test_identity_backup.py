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
