from datetime import datetime, timezone
import httpx
import pytest
from fastapi.testclient import TestClient
from app.main import create_app
from app.db import Record
from app.boe import BoeClient, SourceError, import_norm, parse_text
from app.learning import schedule, score

@pytest.fixture
def app(tmp_path):
    return create_app('sqlite:///' + str(tmp_path / 'test.db'))

@pytest.fixture
def client(app):
    return TestClient(app)

def auth(client):
    r = client.post('/v1/auth/guest')
    assert r.status_code == 201
    return {'Authorization': 'Bearer ' + r.json()['accessToken']}

def card(client, h):
    d = client.post('/v1/decks', headers=h, json={'title': 'Privado'}).json()
    c = client.post('/v1/cards', headers=h, json={'deckId': d['id'], 'front': 'Pregunta', 'back': 'Respuesta'})
    assert c.status_code == 201
    return c.json()

def test_auth_rotation(client):
    a = client.post('/v1/auth/guest').json()
    r = client.post('/v1/auth/refresh', json={'refreshToken': a['refreshToken']})
    assert r.status_code == 200
    assert client.post('/v1/auth/refresh', json={'refreshToken': a['refreshToken']}).status_code == 401
    h = {'Authorization': 'Bearer ' + r.json()['accessToken']}
    assert client.post('/v1/auth/logout', headers=h).status_code == 200
    assert client.get('/v1/decks', headers=h).status_code == 401

def test_private_access(client):
    a, b = auth(client), auth(client)
    c = card(client, a)
    assert client.get('/v1/decks', headers=b).json()['items'] == []
    assert client.post('/v1/cards', headers=b, json={'deckId': c['deckId'], 'front': 'X', 'back': 'Y'}).status_code == 404
    assert client.post('/v1/cards', headers=a, json={'deckId': c['deckId'], 'front': 'X', 'back': 'Y', 'citations': [{'versionId': 'invented', 'unitId': 'a1'}]}).status_code == 422

def test_reviews(client, app):
    h = auth(client); c = card(client, h)
    body = {'cardId': c['id'], 'cardRevision': 1, 'rating': 3, 'occurredAt': datetime.now(timezone.utc).isoformat(), 'idempotencyKey': 'stable-key-1'}
    one = client.post('/v1/reviews', headers=h, json=body)
    two = client.post('/v1/reviews', headers=h, json=body)
    assert one.status_code == two.status_code == 201
    assert one.json() == two.json()
    assert client.post('/v1/reviews', headers=h, json={**body, 'rating': 4}).status_code == 409
    records = client.get('/v1/account/export', headers=h).json()['records']
    assert len([r for r in records if r['kind'] == 'review_event']) == 1
    with app.state.factory() as s:
        c = s.get(Record, c['id']); c.data = {**c.data, 'blocked': True}; s.commit()
    assert client.post('/v1/reviews', headers=h, json={**body, 'idempotencyKey': 'another-key'}).status_code == 409

def test_erase_and_promo(client):
    h = auth(client); card(client, h)
    rights = client.get('/v1/payments/entitlements', headers=h).json()
    assert rights['autoRenew'] is False and rights['storePurchasesAvailable'] is False
    assert client.post('/v1/payments/validate', headers=h).status_code == 503
    assert client.delete('/v1/account?confirmation=no', headers=h).status_code == 422
    assert client.delete('/v1/account?confirmation=ELIMINAR', headers=h).status_code == 200
    assert client.get('/v1/account/export', headers=h).status_code == 401

def test_etag(client):
    h = auth(client)
    r = client.post('/v1/private', headers=h, json={'kind': 'note', 'data': {'text': 'a'}}).json()
    url = '/v1/private/' + r['id']
    assert client.put(url, headers={**h, 'If-Match': '1'}, json={'data': {'text': 'b'}}).status_code == 200
    assert client.put(url, headers={**h, 'If-Match': '1'}, json={'data': {'text': 'c'}}).status_code == 409

def test_scheduler():
    at = datetime(2026, 1, 1, tzinfo=timezone.utc)
    a = schedule({}, 3, at); assert a['interval'] == 1
    b = schedule(a, 3, at); assert b['interval'] == 6
    assert schedule(b, 1, at)['repetitions'] == 0
    assert schedule(b, 1, at)['lapses'] == 1
    for _ in range(30): b = schedule(b, 2, at)
    assert b['ease'] >= 1.3
    with pytest.raises(ValueError): schedule({}, 0)

def test_score():
    assert score([{'id': '1', 'correct': 0}, {'id': '2', 'correct': 1}, {'id': '3', 'correct': 2}], {'1': 0, '2': 0}, .25) == {'correct': 1, 'wrong': 1, 'blank': 1, 'score': .75, 'total': 3}

XML = b'<response><bloque id="a1" titulo="Articulo 1"><version fecha_vigencia="20260101" fecha_publicacion="20251201"><p>Texto original</p><table><tr><td>Dato</td></tr></table></version></bloque></response>'
META = b'<response><metadatos><titulo>Norma de prueba</titulo></metadatos></response>'
class FakeBoe:
    payload = XML
    def get(self, path): return META if path.endswith('metadatos') else self.payload

def test_import_integrity(app):
    with app.state.factory() as s:
        client = FakeBoe(); a = import_norm(s, client, 'BOE-A-2026-1')
        assert import_norm(s, client, 'BOE-A-2026-1') == a
        s.add(Record(id='card1', kind='card', data={'citations': [{'normId': 'BOE-A-2026-1'}], 'editorialState': 'approved'})); s.commit()
        client.payload = XML.replace(b'original', b'nuevo')
        b = import_norm(s, client, 'BOE-A-2026-1'); assert a != b
        assert s.get(Record, a).data['blocks'][0]['versions'][0]['text'].startswith('Texto original')
        assert '<table>' in s.get(Record, a).data['blocks'][0]['versions'][0]['xml']
        assert s.get(Record, 'card1').data['blocked'] is True
        client.payload = b'<response><bloque id="a1"/></response>'
        with pytest.raises(SourceError): import_norm(s, client, 'BOE-A-2026-1')
        assert s.get(Record, 'BOE-A-2026-1').data['latestVersion'] == b

def test_boe_retries():
    calls = []
    def handler(request):
        calls.append(request)
        return httpx.Response(429 if len(calls) < 3 else 200, content=b'<response/>')
    boe = BoeClient(httpx.Client(transport=httpx.MockTransport(handler)), sleep=lambda _: None)
    assert boe.daily('20261104') == b'<response/>' and len(calls) == 3
    with pytest.raises(SourceError): parse_text(b'<response/>')
    with pytest.raises(Exception): parse_text(b'<!DOCTYPE x [<!ENTITY x SYSTEM "file:///etc/passwd">]><r>&x;</r>')

def test_permissions_and_health(client):
    assert client.get('/v1/library/norms').json()['items'] == []
    assert client.get('/v1/admin/ingestions', headers=auth(client)).status_code == 403
    assert client.get('/health').json()['status'] == 'ok'

def test_exam_frozen_bank_and_submission(client):
    h = auth(client)
    d = client.post('/v1/decks', headers=h, json={'title': 'Test'}).json()
    c = client.post('/v1/cards', headers=h, json={'deckId': d['id'], 'front': 'A o B', 'back': 'A', 'type': 'test', 'options': ['A', 'B'], 'correct': 0}).json()
    a = client.post('/v1/exams/attempts', headers=h, json={'cardIds': [c['id']], 'penalty': .25})
    assert a.status_code == 201
    assert 'correct' not in a.json()['questions'][0]
    url = '/v1/exams/attempts/' + a.json()['id'] + '/submit'
    assert client.post(url, headers=h, json={'responses': {c['id']: 9}}).status_code == 422
    result = client.post(url, headers=h, json={'responses': {c['id']: 0}}).json()
    assert result['result']['score'] == 1
    assert client.post(url, headers=h, json={'responses': {c['id']: 1}}).json() == result

def test_missing_version_and_invalid_date(client):
    assert client.get('/v1/library/norms/BOE-A-2026-1/units?version=invented').status_code == 404
    h = auth(client); c = card(client, h)
    r = client.post('/v1/reviews', headers=h, json={'cardId': c['id'], 'cardRevision': 1, 'rating': 3, 'occurredAt': '2026-01-01T12:00:00', 'idempotencyKey': 'no-timezone-key'})
    assert r.status_code == 422

def test_stable_upload_ids(client):
    h = auth(client)
    body = {'title': 'Offline', 'clientId': 'device-deck-1'}
    d = client.post('/v1/decks', headers=h, json=body).json()
    assert client.post('/v1/decks', headers=h, json=body).json()['id'] == d['id']
    assert client.post('/v1/decks', headers=h, json={**body, 'title': 'Different'}).status_code == 409
    c = {'deckId': d['id'], 'clientId': 'device-card-1', 'front': 'F', 'back': 'B'}
    first = client.post('/v1/cards', headers=h, json=c).json()
    assert client.post('/v1/cards', headers=h, json=c).json()['id'] == first['id']
    assert client.post('/v1/cards', headers=h, json={**c, 'back': 'changed'}).status_code == 409

def test_concurrent_record_write_keeps_first_version(app):
    from sqlalchemy.orm.exc import StaleDataError
    with app.state.factory() as s:
        s.add(Record(id='same-note', kind='note', data={'text': 'original'})); s.commit()
    with app.state.factory() as a, app.state.factory() as b:
        first, second = a.get(Record, 'same-note'), b.get(Record, 'same-note')
        first.data = {'text': 'first'}; a.commit()
        second.data = {'text': 'second'}
        with pytest.raises(StaleDataError): b.commit()
    with app.state.factory() as s:
        assert s.get(Record, 'same-note').data['text'] == 'first'
