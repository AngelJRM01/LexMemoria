from editorial_helpers import enable_editorial
"""Private progress must survive a server without the mobile source catalogue."""
from datetime import datetime, timezone

from fastapi.testclient import TestClient

from app.db import Account, Record
from app.main import create_app


def test_private_cited_card_roundtrip_history_and_progress_on_empty_server(tmp_path, monkeypatch):
    app = create_app('sqlite:///' + str(tmp_path / 'sync.db'))
    client = TestClient(app)
    credentials = client.post('/v1/auth/guest').json()
    headers = {'Authorization': 'Bearer ' + credentials['accessToken']}
    deck = client.post('/v1/decks', headers=headers, json={'title': 'Constitución'}).json()
    citation = {'normId': 'BOE-A-1978-31229', 'unitId': 'a1',
                'versionId': 'mobile-immutable-version', 'unitVersionHash': 'a' * 64}
    body = {'deckId': deck['id'], 'clientId': 'prepared-card-1',
            'front': 'Pregunta', 'back': 'Respuesta', 'citations': [citation]}
    response = client.post('/v1/cards', headers=headers, json=body)
    assert response.status_code == 201, response.text
    card = response.json()
    assert card['citationState'] == 'pending_source'
    assert card['editorialState'] == 'user'
    assert card['citations'] == [citation]
    assert client.post('/v1/cards', headers=headers, json=body).json() == card
    edited = client.put('/v1/cards/' + card['id'], headers={**headers, 'If-Match': '1'},
                        json={**body, 'back': 'Edición personal'})
    assert edited.status_code == 200, edited.text
    assert edited.json()['citationState'] == 'pending_source'
    history = client.get('/v1/cards/' + card['id'] + '/history', headers=headers).json()['items']
    assert history[0]['content']['citations'] == [citation]
    review = {'cardId': card['id'], 'cardRevision': 1, 'rating': 3,
              'occurredAt': datetime.now(timezone.utc).isoformat(), 'idempotencyKey': 'offline-review-1'}
    assert client.post('/v1/reviews', headers=headers, json=review).status_code == 201
    records = client.get('/v1/account/export', headers=headers).json()['records']
    assert any(r['kind'] == 'review_event' for r in records)
    assert next(r for r in records if r['kind'] == 'card')['citations'] == [citation]
    stranger = {'Authorization': 'Bearer ' + client.post('/v1/auth/guest').json()['accessToken']}
    assert client.get('/v1/cards/' + card['id'] + '/history', headers=stranger).status_code == 404
    with app.state.factory() as session:
        assert session.get(Record, citation['versionId']) is None
        assert session.get(Record, citation['normId']) is None
    reviewer = client.post('/v1/auth/guest').json()
    with app.state.factory() as session:
        session.get(Account, reviewer['userId']).role = 'reviewer'
        session.commit()
    enable_editorial(monkeypatch,client,app)
    approval = client.post('/v1/admin/editorial/' + card['id'] + '/approve',
                           headers={'Authorization': 'Bearer ' + reviewer['accessToken']},
                           json={'revision': 2, 'reason': 'Revisión editorial de prueba sin fuente importada'})
    assert approval.status_code == 422, approval.text
    assert approval.json()['title'] == 'Referencia obsoleta o no disponible'


def test_missing_catalogue_does_not_disable_citation_or_exercise_validation(tmp_path):
    client = TestClient(create_app('sqlite:///' + str(tmp_path / 'validation.db')))
    headers = {'Authorization': 'Bearer ' + client.post('/v1/auth/guest').json()['accessToken']}
    deck = client.post('/v1/decks', headers=headers, json={'title': 'Privado'}).json()
    body = {'deckId': deck['id'], 'front': 'Pregunta', 'back': 'Respuesta'}
    for citation in ({'versionId': 'unknown', 'unitId': 'a1'},
                     {'normId': [], 'versionId': 'unknown', 'unitId': 'a1'},
                     {'normId': 'norm', 'versionId': 'unknown', 'unitId': 'a1', 'unitVersionHash': 12}):
        assert client.post('/v1/cards', headers=headers, json={**body, 'citations': [citation]}).status_code == 422
    citation = {'normId': 'norm', 'versionId': 'unknown', 'unitId': 'a1'}
    assert client.post('/v1/cards', headers=headers,
                       json={**body, 'citations': [citation], 'type': 'cloze'}).status_code == 422
