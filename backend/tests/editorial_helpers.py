"""A test-only stand-in for a real staff MFA gateway; never deployed."""
import hashlib,hmac,json,secrets,time
from urllib.parse import urlsplit
from app.db import Token

TEST_KEY='unit-test-gateway-key-not-a-production-secret'

def assertion(app,headers,method,path,body=None):
    token=headers['Authorization'].removeprefix('Bearer ')
    with app.state.factory() as s:user_id=s.get(Token,hashlib.sha256(token.encode()).hexdigest()).user_id
    stamp=str(int(time.time()));nonce=secrets.token_urlsafe(24)
    raw=json.dumps(body,ensure_ascii=False,separators=(',',':'),allow_nan=False).encode() if body is not None else b''
    message='\n'.join([user_id,stamp,nonce,method.upper(),path,hashlib.sha256(raw).hexdigest(),hashlib.sha256(token.encode()).hexdigest()]).encode()
    return stamp+'.'+nonce+'.'+hmac.new(TEST_KEY.encode(),message,hashlib.sha256).hexdigest()


def enable_editorial(monkeypatch,client,app):
    monkeypatch.setenv('EDITORIAL_MFA_GATEWAY','configured')
    monkeypatch.setenv('EDITORIAL_GATEWAY_SHARED_KEY',TEST_KEY)
    original=client.request
    def request(method,url,*args,**kwargs):
        path=urlsplit(str(url)).path
        headers=dict(kwargs.get('headers') or {})
        if path.startswith('/v1/admin/') and 'Authorization' in headers and 'X-LexMemoria-Editorial' not in headers:
            headers['X-LexMemoria-Editorial']=assertion(app,headers,method,path,kwargs.get('json'))
            kwargs['headers']=headers
        return original(method,url,*args,**kwargs)
    monkeypatch.setattr(client,'request',request)
