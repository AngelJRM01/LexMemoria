from datetime import datetime, timezone
import pytest
from fastapi.testclient import TestClient
from app.main import create_app
from app.exercises import grade_exercise, validate_exercise

CARD={'type':'cloze','front':'La {{c1::Constitución}} exige {{c2::tres años}}.', 'back':'Constitución; tres años'}

@pytest.mark.parametrize('response,correct', [
    ({'1':'CONSTITUCIÓN','2':' tres   años '},True),
    ({'1':'Constitucion','2':'tres años'},False),
    ({'1':'Constitución'},False),
    ({},False),
    (None,None),
])
def test_cloze_literal_grading_preserves_accents(response,correct):
    assert grade_exercise(CARD,response) is correct

@pytest.mark.parametrize('response',[0, ['Constitución'], {'3':'unexpected'}, {'1':23}, {'1':'x'*2001}])
def test_invalid_cloze_response_is_rejected(response):
    with pytest.raises(ValueError):grade_exercise(CARD,response)

def test_conflicting_repeated_placeholder_is_rejected():
    with pytest.raises(ValueError):validate_exercise({**CARD,'front':'{{c1::uno}} y {{c1::dos}}'})
    validate_exercise({**CARD,'front':'{{c1::uno}} y {{c1::uno}}'})

def test_cloze_answers_roundtrip_and_replay_without_losing_review(tmp_path):
    with TestClient(create_app('sqlite:///' + str(tmp_path/'cloze.db'))) as c:
        session=c.post('/v1/auth/guest').json()
        h={'Authorization':'Bearer '+session['accessToken']}
        d=c.post('/v1/decks',headers=h,json={'title':'Huecos'}).json()
        card=c.post('/v1/cards',headers=h,json={**CARD,'deckId':d['id']})
        assert card.status_code==201
        body={'cardId':card.json()['id'],'cardRevision':1,'rating':3,
            'occurredAt':datetime.now(timezone.utc).isoformat(),'idempotencyKey':'cloze-response-v3',
            'response':{'1':'Constitución','2':'tres años'}}
        one=c.post('/v1/reviews',headers=h,json=body)
        two=c.post('/v1/reviews',headers=h,json=body)
        assert one.status_code==two.status_code==201 and one.json()==two.json()
        exported=c.get('/v1/account/export',headers=h).json()['records']
        events=[r for r in exported if r['kind']=='review_event']
        assert len(events)==1 and events[0]['response']==body['response']
        assert events[0]['objectiveCorrect'] is True
