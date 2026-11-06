"""Retry a lost recovery response without consuming another recovery code.

Only encrypted response receipts are stored. The client keeps the random request
secret in its credential vault before sending the first request. No receipt is
included in exports; receipts expire after 24 hours and cannot revive revoked tokens.
"""
import base64
import hashlib
import json
import os
from datetime import datetime, timedelta, timezone
from cryptography.exceptions import InvalidTag
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
from fastapi import HTTPException
from sqlalchemy import ForeignKey, Text
from sqlalchemy.orm import Mapped, mapped_column
from .db import Base, now

class RecoveryReceipt(Base):
    __tablename__='recovery_receipts'
    id: Mapped[str] = mapped_column(primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('accounts.id',ondelete='CASCADE'),index=True)
    code_hash: Mapped[str]
    ciphertext: Mapped[str] = mapped_column(Text)
    expires_at: Mapped[str]


def read_receipt(s, body):
    if not body.attemptId:return None
    row=s.get(RecoveryReceipt,body.attemptId)
    if not row:return None
    if row.expires_at<now() or row.code_hash!=hashlib.sha256(body.recoveryCode.encode()).hexdigest():
        raise HTTPException(401,'Reintento de recuperación no disponible')
    try:
        raw=base64.b64decode(row.ciphertext)
        key=hashlib.sha256(body.attemptSecret.encode()).digest()
        plaintext=AESGCM(key).decrypt(raw[:12],raw[12:],body.attemptId.encode())
        return json.loads(plaintext)
    except (InvalidTag,ValueError):
        raise HTTPException(401,'Reintento de recuperación no disponible')


def add_receipt(s,body,user_id,result):
    if not body.attemptId:return
    nonce=os.urandom(12);key=hashlib.sha256(body.attemptSecret.encode()).digest()
    encrypted=AESGCM(key).encrypt(nonce,json.dumps(result).encode(),body.attemptId.encode())
    s.add(RecoveryReceipt(id=body.attemptId,user_id=user_id,
        code_hash=hashlib.sha256(body.recoveryCode.encode()).hexdigest(),
        ciphertext=base64.b64encode(nonce+encrypted).decode(),
        expires_at=(datetime.now(timezone.utc)+timedelta(hours=24)).isoformat()))
