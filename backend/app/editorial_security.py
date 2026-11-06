"""Require a fresh, single-use assertion from the operator's real MFA gateway.

The gateway must authenticate staff with MFA, strip caller-supplied assertions,
and sign the exact request. A configuration flag alone never grants access.
The shared key belongs only to gateway/server environment, never to the app.
"""
import hashlib
import hmac
import os
import re
import time
from fastapi import HTTPException
from sqlalchemy.exc import IntegrityError
from .db import Audit


def require_editorial(user,request,session):
    if user.role not in ('reviewer','publisher','admin'):
        raise HTTPException(403,'Rol editorial requerido')
    secret=os.getenv('EDITORIAL_GATEWAY_SHARED_KEY','')
    if os.getenv('EDITORIAL_MFA_GATEWAY')!='configured' or len(secret)<32:
        raise HTTPException(503,'Configura y verifica la pasarela MFA editorial antes de habilitar publicaciones')
    assertion=request.headers.get('x-lexmemoria-editorial','')
    if len(assertion)>256:raise HTTPException(403,'Acreditación MFA no válida')
    try:
        stamp,nonce,signature=assertion.split('.')
        if not stamp.isdigit() or abs(time.time()-int(stamp))>60 or not re.fullmatch(r'[A-Za-z0-9_-]{24,64}',nonce):raise ValueError()
        token=request.headers.get('authorization','').removeprefix('Bearer ')
        token_hash=hashlib.sha256(token.encode()).hexdigest()
        payload='\n'.join([user.id,stamp,nonce,request.method,request.url.path,
                          request.state.body_hash,token_hash]).encode()
        expected=hmac.new(secret.encode(),payload,hashlib.sha256).hexdigest()
        if not hmac.compare_digest(expected,signature):raise ValueError()
    except ValueError:
        raise HTTPException(403,'Se requiere acreditación MFA reciente de la pasarela')
    session.add(Audit(id='mfa:'+nonce,actor=user.id,entity=request.url.path,action='mfa_assertion',
                      data={'method':request.method,'at':int(stamp)}))
    try:session.commit()
    except IntegrityError:
        session.rollback();raise HTTPException(403,'Acreditación MFA ya utilizada')
