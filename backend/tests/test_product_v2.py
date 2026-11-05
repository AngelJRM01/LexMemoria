from datetime import datetime, timezone
import httpx
import pytest
from fastapi.testclient import TestClient
from app.main import create_app
from app.db import Record
from app.catalogue import index_norm
from app.boe import BoeClient, SourceError

@pytest.fixture
def app(tmp_path): return create_app('sqlite:///' + str(tmp_path / 'db'))
@pytest.fixture
def client(app): return TestClient(app)
def auth(client): return {'Authorization': 'Bearer ' + client.post('/v1/auth/guest').json()['accessToken']}
def make_card(client, h, **fields):
    deck = client.post('/v1/decks', headers=h, json={'title': 'Privado'}).json()
    body = {'deckId': deck['id'], 'clientId': 'stable-card', 'front': 'Pregunta', 'back': 'Respuesta', **fields}
    return body, client.post('/v1/cards', headers=h, json=body)

def test_edit_history_progress_concurrency_and_old_offline_review(client):
    h = auth(client); body, r = make_card(client, h); card = r.json()
    review = {'cardId': card['id'], 'cardRevision': 1, 'rating': 3, 'occurredAt': datetime.now(timezone.utc).isoformat(), 'idempotencyKey': 'review-key-1'}
    assert client.post('/v1/reviews', headers=h, json=review).status_code == 201
    r = client.put('/v1/cards/' + card['id'], headers={**h, 'If-Match': '1'}, json={**body, 'back': 'Corregida'})
    assert r.status_code == 200 and r.json()['revision'] == 2 and r.headers['etag'] == '2'
    assert client.put('/v1/cards/' + card['id'], headers={**h, 'If-Match': '1'}, json=body).status_code == 409
    history = client.get('/v1/cards/' + card['id'] + '/history', headers=h).json()['items']
    assert len(history) == 1 and history[0]['content']['back'] == 'Respuesta'
    assert client.get('/v1/study/today', headers=h).json()['states'][0]['repetitions'] == 1
    assert client.get('/v1/cards/' + card['id'] + '/history', headers=auth(client)).status_code == 404
    assert client.post('/v1/reviews', headers=h, json={**review, 'idempotencyKey': 'review-key-2'}).status_code == 201
    assert client.post('/v1/reviews', headers=h, json={**review, 'cardRevision': 99, 'idempotencyKey': 'review-key-3'}).status_code == 409

@pytest.mark.parametrize('fields', [
    {'type': 'cloze', 'front': 'Sin hueco'},
    {'type': 'truefalse', 'options': ['Sí', 'No'], 'correct': 0},
    {'type': 'order', 'options': ['uno', 'uno']},
    {'type': 'order', 'options': ['uno']},
    {'type': 'test', 'options': ['uno', 'dos'], 'correct': 5},
])
def test_invalid_exercises(client, fields):
    _, r = make_card(client, auth(client), **fields); assert r.status_code == 422

def test_structured_exercises_and_duplicate_questions(client):
    h = auth(client); _, r = make_card(client, h, type='truefalse', options=['Verdadero', 'Falso'], correct=0)
    assert r.status_code == 201
    assert client.post('/v1/exams/attempts', headers=h, json={'cardIds': [r.json()['id']] * 2}).status_code == 422
    assert client.post('/v1/cards', headers=h, json={'deckId': r.json()['deckId'], 'front': 'Ordena', 'back': 'Orden correcto', 'type': 'order', 'options': ['primero', 'segundo']}).status_code == 201

def test_wrong_norm_in_citation(app, client):
    with app.state.factory() as s:
        s.add(Record(id='v', kind='norm_version', data={'normId': 'norm-a', 'blocks': [{'id': 'a1'}]})); s.commit()
    _, r = make_card(client, auth(client), citations=[{'versionId': 'v', 'normId': 'norm-b', 'unitId': 'a1'}]); assert r.status_code == 422

def test_search_accents_wildcards_filters_coverage_and_cursor(app, client):
    with app.state.factory() as s:
        for id_, title in [('a', 'Constitución Española'), ('b', 'Código Civil')]:
            data = {'title': title, 'officialId': id_, 'source': 'BOE', 'jurisdiction': 'Estado', 'reviewState': 'pending'}
            s.add(Record(id=id_, kind='norm', data=data)); index_norm(s, id_, data)
        s.commit()
    assert client.get('/v1/library/norms', params={'q': 'CONSTITUCION española'}).json()['items'][0]['id'] == 'a'
    assert client.get('/v1/library/norms', params={'q': '%'}).json()['items'] == []
    assert client.get('/v1/library/norms', params={'jurisdiction': 'UE'}).json()['items'] == []
    assert client.get('/v1/library/coverage').json()['bySource'] == {'BOE': 2}
    assert client.get('/v1/library/norms?limit=1').json()['nextCursor'] == 'a'
    assert client.get('/v1/library/norms?limit=1&cursor=a').json()['items'][0]['id'] == 'b'

def test_boe_xml_error_status():
    transport = httpx.MockTransport(lambda r: httpx.Response(200, content=b'<response><status><code>404</code></status><data/></response>'))
    with pytest.raises(SourceError, match='404'):
        BoeClient(httpx.Client(transport=transport), sleep=lambda _: None).get('/missing')

def test_inbox_opt_in_dedup_read_and_isolation(app, client):
    h = auth(client)
    with app.state.factory() as s:
        s.add(Record(id='norm-a', kind='norm', data={'title': 'Norma'})); s.commit()
    assert client.post('/v1/legal-updates/subscriptions', headers=h, json={'normIds': ['norm-a']}).status_code == 200
    with app.state.factory() as s:
        s.add(Record(id='e1', kind='legal_event', data={'normId': 'norm-a'})); s.commit()
    items = client.get('/v1/notifications', headers=h).json()['items']
    assert len(items) == 1 and items[0]['channel'] == 'in_app'
    assert len(client.get('/v1/notifications', headers=h).json()['items']) == 1
    other = auth(client); assert client.get('/v1/notifications', headers=other).json()['items'] == []
    path = '/v1/notifications/' + items[0]['id'] + '/read'
    assert client.post(path, headers=other).status_code == 404
    assert client.post(path, headers=h).json()['read'] is True
    client.post('/v1/legal-updates/subscriptions', headers=h, json={'normIds': ['norm-a'], 'enabled': False})
    with app.state.factory() as s:
        s.add(Record(id='e2', kind='legal_event', data={'normId': 'norm-a'})); s.commit()
    assert len(client.get('/v1/notifications', headers=h).json()['items']) == 1

def test_reports_idempotent_and_private(client):
    h = auth(client); _, r = make_card(client, h)
    body = {'clientId': 'report-1234', 'cardId': r.json()['id'], 'reason': 'Revisar esta respuesta'}
    first = client.post('/v1/reports', headers=h, json=body)
    assert first.status_code == 201 and first.json()['status'] == 'received'
    assert client.post('/v1/reports', headers=h, json=body).json()['id'] == first.json()['id']
    assert client.post('/v1/reports', headers=h, json={**body, 'reason': 'Motivo cambiado'}).status_code == 409
    assert client.get('/v1/reports', headers=auth(client)).json()['items'] == []

def test_historical_citation_hash_and_objective_response(app, client):
    h = auth(client)
    with app.state.factory() as s:
        s.add(Record(id='version-1', kind='norm_version', data={'normId': 'norm-1', 'blocks': [{'id': 'a1', 'versions': [{'hash': 'actual-hash'}]}]})); s.commit()
    body, result = make_card(client, h, type='order', options=['Primero', 'Segundo'], citations=[{'normId': 'norm-1', 'versionId': 'version-1', 'unitId': 'a1', 'unitVersionHash': 'made-up'}])
    assert result.status_code == 422
    body['citations'][0]['unitVersionHash'] = 'actual-hash'
    result = client.post('/v1/cards', headers=h, json=body); assert result.status_code == 201
    review = {'cardId': result.json()['id'], 'cardRevision': 1, 'rating': 2, 'occurredAt': datetime.now(timezone.utc).isoformat(), 'idempotencyKey': 'order-review-1', 'response': [1, 0]}
    assert client.post('/v1/reviews', headers=h, json=review).status_code == 201
    exported = client.get('/v1/account/export', headers=h).json()['records']
    assert next(r for r in exported if r['kind'] == 'review_event')['objectiveCorrect'] is False
    assert client.post('/v1/reviews', headers=h, json={**review, 'response': [1, 1], 'idempotencyKey': 'order-review-2'}).status_code == 422

def test_body_limit_does_not_trust_missing_content_length(client):
    request = client.build_request('POST', '/v1/auth/guest', content=b'x' * 2_000_001)
    request.headers.pop('content-length', None)
    assert client.send(request).status_code == 413

def test_workspace_compare_and_swap_and_deletion(client):
    h = auth(client); other = auth(client)
    assert client.get('/v1/workspace', headers=h).json() == {'data': None, 'revision': 0}
    body = {'profile': {'dailyGoal': 20}, 'notes': {'article-1': 'Mi nota'}, 'courses': [], 'follows': []}
    r = client.put('/v1/workspace', headers={**h, 'If-Match': '0'}, json=body)
    assert r.status_code == 200 and r.json()['revision'] == 1
    assert client.get('/v1/workspace', headers=other).json()['data'] is None
    assert client.put('/v1/workspace', headers={**h, 'If-Match': '0'}, json={**body, 'notes': {}}).status_code == 409
    assert client.get('/v1/workspace', headers=h).json()['data']['notes'] == body['notes']
    assert client.delete('/v1/account?confirmation=ELIMINAR', headers=h).status_code == 200
