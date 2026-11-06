from fastapi.testclient import TestClient
from app.main import create_app
from app.db import Account
from editorial_helpers import TEST_KEY,assertion


def test_flag_alone_never_unlocks_admin_and_proof_is_bound_single_use(tmp_path,monkeypatch):
    app=create_app('sqlite:///'+str(tmp_path/'mfa.db'));c=TestClient(app)
    user=c.post('/v1/auth/guest').json();h={'Authorization':'Bearer '+user['accessToken']}
    with app.state.factory() as s:s.get(Account,user['userId']).role='admin';s.commit()
    path='/v1/admin/collaboration'
    monkeypatch.setenv('EDITORIAL_MFA_GATEWAY','configured');monkeypatch.delenv('EDITORIAL_GATEWAY_SHARED_KEY',raising=False)
    assert c.get(path,headers=h).status_code==503
    monkeypatch.setenv('EDITORIAL_GATEWAY_SHARED_KEY',TEST_KEY)
    assert c.get(path,headers=h).status_code==403
    proof=assertion(app,h,'GET',path)
    assert c.get(path,headers={**h,'X-LexMemoria-Editorial':proof}).status_code==200
    assert c.get(path,headers={**h,'X-LexMemoria-Editorial':proof}).status_code==403
    assert c.get('/v1/admin/ingestions',headers={**h,'X-LexMemoria-Editorial':assertion(app,h,'GET',path)}).status_code==403
    other=c.post('/v1/auth/guest').json();oh={'Authorization':'Bearer '+other['accessToken']}
    assert c.get(path,headers={**oh,'X-LexMemoria-Editorial':assertion(app,h,'GET',path)}).status_code==403
