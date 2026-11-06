from fastapi.testclient import TestClient
from sqlalchemy import select
from app.main import create_app
from app.db import Record


def test_change_token_is_scoped_durable_and_ignores_private_preferences(tmp_path):
    url='sqlite:///'+str(tmp_path/'clock.db')
    app=create_app(url);c=TestClient(app)
    auth=lambda:{'Authorization':'Bearer '+c.post('/v1/auth/guest').json()['accessToken']}
    a,b=auth(),auth()
    status=lambda h:c.get('/v1/sync/status',headers=h).json()
    assert status(a)['progressVersion']==0
    deck=c.post('/v1/decks',headers=a,json={'title':'D'}).json()
    first=status(a)['progressVersion'];assert first>0
    card=c.post('/v1/cards',headers=a,json={'deckId':deck['id'],'front':'Q','back':'A'}).json()
    assert status(a)['progressVersion']>first
    assert status(b)['progressVersion']==0
    unchanged=status(a)['progressVersion']
    assert c.put('/v1/workspace',headers={**a,'If-Match':'0'},json={'notes':{'x':'nota'}}).status_code==200
    assert status(a)['progressVersion']==unchanged
    assert status(a)['workspaceRevision']==1
    # Source processors also use the model; they must preserve old educational content.
    with app.state.factory() as s:
        row=s.get(Record,card['id']);row.data={**row.data,'back':'B'};s.commit()
        histories=list(s.scalars(select(Record).where(Record.kind=='card_revision')))
        assert len(histories)==1 and histories[0].data['content']['back']=='A'
    changed=status(a)['progressVersion'];assert changed>unchanged
    restarted=TestClient(create_app(url))
    assert restarted.get('/v1/sync/status',headers=a).json()['progressVersion']==changed
    assert status(b)['workspaceRevision']==0
