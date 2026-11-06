"""Private profiles and token-family sessions, additive to existing identity.

No device fingerprint, IP address, email or provider subject is exposed.
Legacy tokens remain valid; unpaired legacy credentials can be revoked explicitly.
"""
import hashlib
import threading
import re
import unicodedata
from datetime import datetime, timezone, timedelta

from fastapi import Depends, Header, HTTPException, Request
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import ForeignKey, String, delete, select
from sqlalchemy.orm import Mapped, mapped_column

from .db import Base, Record, Token, RecoveryCode, Audit, now, uid
from .identity import ExternalIdentity, IdentityError
from .rate_limits import account_limit

_image_slots = threading.BoundedSemaphore(2)


class UserSession(Base):
    __tablename__ = 'user_sessions'
    id: Mapped[str] = mapped_column(String(128), primary_key=True, default=uid)
    user_id: Mapped[str] = mapped_column(ForeignKey('accounts.id'), index=True)
    created_at: Mapped[str] = mapped_column(default=now)
    last_active_at: Mapped[str] = mapped_column(default=now)


class SessionToken(Base):
    __tablename__ = 'session_tokens'
    digest: Mapped[str] = mapped_column(ForeignKey('tokens.digest', ondelete='CASCADE'), primary_key=True)
    session_id: Mapped[str] = mapped_column(ForeignKey('user_sessions.id', ondelete='CASCADE'), index=True)


class AliasClaim(Base):
    __tablename__ = 'account_aliases'
    user_id: Mapped[str] = mapped_column(ForeignKey('accounts.id'), primary_key=True)
    alias: Mapped[str] = mapped_column(String(30), unique=True, index=True)


RESERVED = {'admin', 'administrator', 'administrador', 'lexmemoria', 'support', 'soporte',
            'moderador', 'moderator', 'oficial', 'official', 'google', 'apple', 'firebase', 'boe'}


def alias_normalized(value):
    value = unicodedata.normalize('NFKC', value).strip().lower()
    if not value:
        return ''
    if not re.fullmatch(r'[a-z][a-z0-9_]{2,29}', value) or re.sub(r'[_0-9]', '', value) in RESERVED or value.startswith('lexmemoria'):
        raise ValueError('Alias: 3–30 caracteres, letra inicial, letras a–z, números o _. Nombre reservado no permitido.')
    return value


class ProfileInput(BaseModel):
    model_config = ConfigDict(extra='forbid')
    displayName: str = Field(default='', max_length=80)
    alias: str = Field(default='', max_length=60)
    avatar: str = 'initials'
    language: str = 'es'
    theme: str = 'system'
    allowAliasInvitations: bool = False
    allowLinkInvitations: bool = False
    studyNotifications: bool = False
    legalNotifications: bool = False
    collaborationNotifications: bool = False
    noticeDailyLimit: int = Field(default=3, ge=1, le=20)
    quietStart: str = '22:00'
    quietEnd: str = '08:00'

    @field_validator('alias')
    @classmethod
    def valid_alias(cls, value):
        return alias_normalized(value)

    @field_validator('displayName')
    @classmethod
    def valid_name(cls, value):
        value = value.strip()
        if any(unicodedata.category(c).startswith('C') for c in value):
            raise ValueError('El nombre no admite caracteres de control')
        return value

    @field_validator('theme')
    @classmethod
    def valid_theme(cls, value):
        if value not in ('system', 'light', 'dark'):
            raise ValueError('Tema no válido')
        return value

    @field_validator('avatar')
    @classmethod
    def valid_avatar(cls, value):
        if value not in ('initials', 'book', 'balance', 'photo'):
            raise ValueError('Elige un avatar integrado; no se admiten URLs externas')
        return value

    @field_validator('language')
    @classmethod
    def valid_language(cls, value):
        if value != 'es':
            raise ValueError('Idioma disponible: español')
        return value

    @field_validator('quietStart', 'quietEnd')
    @classmethod
    def valid_time(cls, value):
        if not re.fullmatch(r'(?:[01]\d|2[0-3]):[0-5]\d', value):
            raise ValueError('Hora HH:MM no válida')
        return value


def token_digest(authorization):
    return hashlib.sha256(authorization.removeprefix('Bearer ').encode()).hexdigest()


def session_for_token(s, digest):
    link = s.get(SessionToken, digest)
    return s.get(UserSession, link.session_id) if link else None


def revoke_sessions(s, user_id, ids):
    # Remove credentials before session rows. Explicit cleanup works with older
    # databases and SQLite as well as PostgreSQL FK cascades.
    digests = select(SessionToken.digest).where(SessionToken.session_id.in_(ids))
    s.execute(delete(Token).where(Token.user_id == user_id, Token.digest.in_(digests)))
    s.execute(delete(UserSession).where(UserSession.user_id == user_id, UserSession.id.in_(ids)))


def revoke_current(s, user, authorization):
    digest = token_digest(authorization)
    session = session_for_token(s, digest)
    if session:
        revoke_sessions(s, user.id, [session.id])
        scope = 'current'
    else:
        # Old access/refresh pairs have no family ID. Never guess a device.
        # Revoke all unpaired legacy tokens, leaving new identified sessions.
        paired = select(SessionToken.digest)
        s.execute(delete(Token).where(Token.user_id == user.id, Token.digest.not_in(paired)))
        scope = 'legacy_unidentified'
    s.commit()
    return {'revoked': True, 'scope': scope}


def effective_entitlements(s, user):
    promotion_end = datetime.fromisoformat(user.created_at) + timedelta(days=30)
    grant = s.get(Record, user.id + ':entitlement')
    active = grant and (not grant.data.get('expiresAt') or grant.data['expiresAt'] > now())
    plan = grant.data['plan'] if active else ('promotion' if not grant and promotion_end.isoformat() > now() else 'free')
    return {'plan': plan, 'expiresAt': grant.data.get('expiresAt') if active else promotion_end.isoformat() if not grant else None,
        'autoRenew': False, 'storePurchasesAvailable': False, 'commercialLimitsActive': False,
        'rights': {'basicStudy': True, 'basicCollaboration': True, 'personalDataExport': True,
                  'advancedPlanning': plan in ('student_plus','opositor_pro'),
                  'advancedAnalytics': plan in ('student_plus','opositor_pro'),
                  'specializedContent': plan == 'opositor_pro'}}


def register_account_routes(app, identity, db, editorial):
    def store_avatar(s,user,image):
        row = s.get(Record, user.id + ':avatar')
        data = {'image':image,'mimeType':'image/jpeg'}
        if row:row.data=data
        else:s.add(Record(id=user.id+':avatar',kind='avatar',owner=user.id,data=data))
        s.commit()

    class EntitlementInput(BaseModel):
        plan: str = Field(pattern=r'^(free|student_plus|opositor_pro)$')
        expiresAt: datetime | None = None
        reason: str = Field(min_length=20, max_length=2000)

    @app.put('/v1/admin/accounts/{account_id}/entitlement')
    def assign_entitlement(account_id: str, body: EntitlementInput, request: Request, user=Depends(identity), s=Depends(db)):
        from .db import Account
        editorial(user, request, s)
        if user.role != 'admin':raise HTTPException(403,'Administrador requerido')
        if not s.get(Account, account_id):raise HTTPException(404,'Cuenta no encontrada')
        if body.expiresAt and (body.expiresAt.tzinfo is None or body.expiresAt.utcoffset() is None):
            raise HTTPException(422,'Fecha con zona horaria requerida')
        data={'plan':body.plan,'expiresAt':body.expiresAt.astimezone(timezone.utc).isoformat() if body.expiresAt else None,
              'source':'manual_no_billing','updatedAt':now()}
        key=account_id+':entitlement';row=s.get(Record,key)
        if row:row.data=data
        else:s.add(Record(id=key,kind='user_entitlement',owner=account_id,data=data))
        s.add(Audit(actor=user.id,entity=account_id,action='entitlement_assignment',data={'plan':body.plan,'reason':body.reason}))
        s.commit();return {'assigned':True,'billingEnabled':False,'commercialLimitsActive':False}

    class UnlinkInput(BaseModel):
        idToken: str = Field(min_length=20, max_length=16000)

    @app.post('/v1/account/identities/{identity_id}/unlink')
    def unlink_identity(identity_id: str, body: UnlinkInput, user=Depends(identity), s=Depends(db)):
        row = s.get(ExternalIdentity, identity_id)
        if not row or row.user_id != user.id:
            raise HTTPException(404, 'Identidad no disponible')
        try:
            claim = app.state.identity_verifier.verify(body.idToken, max_auth_age=300)
        except IdentityError:
            raise HTTPException(401, 'Identifícate de nuevo para desvincular')
        if claim['issuer'] != row.issuer or claim['subject'] != row.subject:
            raise HTTPException(409, 'Selecciona la identidad que quieres desvincular')
        alternative = s.scalar(select(ExternalIdentity.id).where(ExternalIdentity.user_id == user.id,
                                    ExternalIdentity.id != row.id).limit(1))
        recovery = s.scalar(select(RecoveryCode.digest).where(RecoveryCode.user_id == user.id))
        if not alternative and not recovery:
            raise HTTPException(409, 'Genera y guarda un código de recuperación antes de quitar el último acceso')
        s.delete(row); s.commit()
        return {'unlinked': True, 'localDataPreserved': True}

    class AvatarInput(BaseModel):
        image: str = Field(min_length=4, max_length=1_340_000)

    @app.post('/v1/account/avatar/google')
    def import_google_avatar(body:UnlinkInput,user=Depends(identity),s=Depends(db)):
        from .avatars import google_avatar
        account_limit(s,user.id,'avatar_upload',limit=5)
        try:
            claim=app.state.identity_verifier.verify(body.idToken,max_auth_age=300)
        except IdentityError:
            raise HTTPException(401,'Identifícate de nuevo para importar tu imagen')
        external=s.scalar(select(ExternalIdentity).where(ExternalIdentity.user_id==user.id,
            ExternalIdentity.issuer==claim['issuer'],ExternalIdentity.subject==claim['subject']))
        if not external:raise HTTPException(409,'Vincula esta identidad antes de importar su imagen')
        if not _image_slots.acquire(blocking=False):raise HTTPException(429,'Inténtalo en unos segundos',headers={'Retry-After':'5'})
        try:
            image=google_avatar(body.idToken,app.state.identity_verifier,claim,getattr(app.state,'avatar_http',None))
        except (ValueError,IdentityError):raise HTTPException(422,'La imagen de Google no está disponible o no cumple los límites')
        finally:_image_slots.release()
        store_avatar(s,user,image)
        return {'stored':True,'metadataRemoved':True}

    @app.put('/v1/account/avatar')
    def upload_avatar(body: AvatarInput, user=Depends(identity), s=Depends(db)):
        from .avatars import sanitize_avatar
        account_limit(s,user.id,'avatar_upload',limit=5)
        if not _image_slots.acquire(blocking=False):raise HTTPException(429,'Inténtalo en unos segundos',headers={'Retry-After':'5'})
        try:
            image = sanitize_avatar(body.image)
        except ValueError:
            raise HTTPException(422, 'Imagen no válida: PNG/JPEG/WebP estático, hasta 1 MB y cuatro millones de píxeles')
        finally:
            _image_slots.release()
        store_avatar(s,user,image)
        return {'stored': True, 'metadataRemoved': True}

    @app.get('/v1/account/avatar')
    def avatar(user=Depends(identity), s=Depends(db)):
        row = s.get(Record, user.id + ':avatar')
        return row.data if row else {'image': None}

    @app.delete('/v1/account/avatar')
    def delete_avatar(user=Depends(identity), s=Depends(db)):
        row = s.get(Record, user.id + ':avatar')
        if row:
            s.delete(row); s.commit()
        return {'deleted': True}

    @app.get('/v1/account/security')
    def security(authorization: str = Header(default=''), user=Depends(identity), s=Depends(db)):
        current = session_for_token(s, token_digest(authorization))
        sessions = list(s.scalars(select(UserSession).where(UserSession.user_id == user.id)))
        result = []
        for session in sessions:
            active = s.scalar(select(Token.digest).join(SessionToken, Token.digest == SessionToken.digest).where(
                SessionToken.session_id == session.id, Token.expires_at > now()).limit(1))
            if active:
                result.append({'id': session.id, 'current': bool(current and current.id == session.id),
                               'label': 'Sesión de LexMemoria', 'createdAt': session.created_at,
                               'lastActiveAt': session.last_active_at})
        legacy = s.scalar(select(Token.digest).where(Token.user_id == user.id,
                          Token.digest.not_in(select(SessionToken.digest)), Token.expires_at > now()).limit(1))
        return {'userId': user.id, 'role': user.role, 'createdAt': user.created_at, 'sessions': result,
                'legacySessionsPresent': bool(legacy), 'currentSessionIdentified': current is not None,
                'linkedIdentities': [{'id': row.id, 'provider': 'Firebase (Google/Apple)'} for row in
                    s.scalars(select(ExternalIdentity).where(ExternalIdentity.user_id == user.id))],
                'deviceIdentification': 'approximate', 'activityPrecision': 'session_issue_or_refresh'}

    @app.delete('/v1/account/sessions/{session_id}')
    def revoke(session_id: str, user=Depends(identity), s=Depends(db)):
        session = s.scalar(select(UserSession).where(UserSession.id == session_id,
                            UserSession.user_id == user.id).with_for_update())
        if not session:
            raise HTTPException(404, 'Sesión no encontrada')
        revoke_sessions(s, user.id, [session.id]); s.commit()
        return {'revoked': True}

    @app.post('/v1/account/sessions/revoke-others')
    def revoke_others(authorization: str = Header(default=''), user=Depends(identity), s=Depends(db)):
        current = session_for_token(s, token_digest(authorization))
        if current is None:
            raise HTTPException(409, 'Renueva el acceso antes de cerrar otras sesiones; la sesión antigua no identifica el dispositivo')
        ids = list(s.scalars(select(UserSession.id).where(UserSession.user_id == user.id,
                            UserSession.id != current.id).with_for_update()))
        revoke_sessions(s, user.id, ids)
        s.execute(delete(Token).where(Token.user_id == user.id, Token.digest.not_in(select(SessionToken.digest))))
        s.commit()
        return {'revoked': True, 'currentPreserved': True}

    @app.get('/v1/account/profile')
    def get_profile(user=Depends(identity), s=Depends(db)):
        row = s.get(Record, user.id + ':account-profile')
        return {'userId': user.id, 'createdAt': user.created_at, 'revision': row.revision if row else 0,
                'data': row.data if row else ProfileInput().model_dump()}

    @app.put('/v1/account/profile')
    def update_profile(body: ProfileInput, if_match: str = Header(), user=Depends(identity), s=Depends(db)):
        account_limit(s,user.id,'profile_update',limit=10)
        row = s.get(Record, user.id + ':account-profile')
        if if_match.strip('"') != str(row.revision if row else 0):
            raise HTTPException(409, 'El perfil cambió en otro dispositivo; vuelve a compararlo')
        claim = s.get(AliasClaim, user.id)
        if body.alias:
            retired = s.get(Record, 'alias-retired:' + hashlib.sha256(body.alias.encode()).hexdigest())
            if retired and retired.owner != user.id and retired.data['availableAfter'] > now():
                raise HTTPException(409, 'Este alias no está disponible')
        if claim and claim.alias != body.alias:
            key = 'alias-retired:' + hashlib.sha256(claim.alias.encode()).hexdigest()
            retired = s.get(Record, key)
            data = {'alias': claim.alias, 'availableAfter': (datetime.now(timezone.utc) + timedelta(days=30)).isoformat()}
            if retired:retired.data = data
            else:s.add(Record(id=key, kind='retired_alias', owner=user.id, data=data))
        if body.alias:
            if claim:
                claim.alias = body.alias
            else:
                s.add(AliasClaim(user_id=user.id, alias=body.alias))
        elif claim:
            s.delete(claim)
        if row:
            row.data = body.model_dump()
        else:
            row = Record(id=user.id + ':account-profile', kind='account_profile', owner=user.id,
                         data=body.model_dump()); s.add(row)
        # Shared handler translates concurrent unique-alias races to HTTP 409.
        from sqlalchemy.exc import IntegrityError
        try:
            s.commit()
        except IntegrityError:
            s.rollback()
            raise HTTPException(409, 'No se puede guardar ese alias o el perfil cambió; elige otro o vuelve a comparar')
        return JSONResponse({'data': row.data, 'revision': row.revision}, headers={'ETag': str(row.revision)})
