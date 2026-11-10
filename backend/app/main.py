import hashlib
import json
import os
import secrets
import time
from collections import defaultdict, deque
from datetime import datetime, timedelta, timezone
from uuid import uuid4, uuid5, NAMESPACE_DNS
from fastapi import FastAPI, Depends, Header, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse, Response, HTMLResponse
from pydantic import BaseModel, Field
from sqlalchemy import select, delete
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm.exc import StaleDataError
from .identity import ExternalIdentity, FirebaseVerifier, IdentityError
from .accounts import (UserSession, SessionToken, AliasClaim, session_for_token,
                       revoke_current, register_account_routes, effective_entitlements)
from .collaboration import register_collaboration, Membership, Relationship, Invitation
from .editorial_security import require_editorial
from .sync_clock import AccountSyncClock
from .recovery_receipts import RecoveryReceipt, read_receipt, add_receipt
from .notifications import inbox, release_optional_notices, study_notices
from .catalogue import NormIndex, normalize, rebuild_index
from .exercises import validate_exercise, grade_exercise
from .db import connect, Record, Account, Token, RecoveryCode, Mutation, Audit, now, uid
from .learning import schedule, score
from .temporal import civil_date, resolve_block


def create_app(database_url=None):
    engine, factory = connect(database_url)
    with factory() as session:
        rebuild_index(session)
    app = FastAPI(title='LexMemoria', version='0.8.2')
    origins = [v.strip() for v in os.getenv('CORS_ORIGINS', '').split(',') if v.strip()]
    if origins:
        app.add_middleware(CORSMiddleware, allow_origins=origins, allow_credentials=False,
                           allow_methods=['GET', 'POST', 'PUT', 'DELETE'], allow_headers=['Authorization', 'Content-Type', 'If-Match'],
                           expose_headers=['ETag', 'X-Request-ID'])
    app.state.factory = factory
    app.state.identity_verifier = FirebaseVerifier(os.getenv('FIREBASE_PROJECT_ID', ''))
    buckets = defaultdict(deque)

    @app.middleware('http')
    async def guard(request, call_next):
        request_id = str(uuid4())
        request.state.request_id = request_id
        key = request.client.host if request.client else 'unknown'
        bucket = buckets[key]
        current = time.monotonic()
        while bucket and bucket[0] < current - 60:
            bucket.popleft()
        if len(bucket) >= 120:
            return JSONResponse({'type': 'about:blank', 'title': 'Demasiadas peticiones',
                                 'status': 429, 'requestId': request_id}, status_code=429,
                                headers={'Retry-After': '60'}, media_type='application/problem+json')
        bucket.append(current)
        try:
            declared_size = int(request.headers.get('content-length', '0'))
            if declared_size < 0:
                raise ValueError()
        except ValueError:
            return JSONResponse({'title': 'Content-Length no válido', 'status': 400, 'requestId': request_id}, status_code=400, media_type='application/problem+json')
        size, chunks = 0, []
        async for chunk in request.stream():
            size += len(chunk)
            if size > 2_000_000 or declared_size > 2_000_000:
                return JSONResponse({'title': 'Solicitud demasiado grande', 'status': 413, 'requestId': request_id}, status_code=413, media_type='application/problem+json')
            chunks.append(chunk)
        request._body = b''.join(chunks)
        request.state.body_hash = hashlib.sha256(request._body).hexdigest()
        response = await call_next(request)
        response.headers['X-Request-ID'] = request_id
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['Cache-Control'] = 'no-store'
        return response

    @app.exception_handler(HTTPException)
    async def error(request, exc):
        return JSONResponse({'type': 'about:blank', 'title': str(exc.detail), 'status': exc.status_code,
                             'requestId': request.state.request_id, 'retryable': exc.status_code in (429, 503)},
                            status_code=exc.status_code, headers=exc.headers, media_type='application/problem+json')

    @app.exception_handler(StaleDataError)
    async def concurrent_error(request, exc):
        return JSONResponse({'type': 'about:blank', 'title': 'Conflicto de edición concurrente; reintenta conservando los datos locales', 'status': 409, 'requestId': request.state.request_id}, status_code=409, media_type='application/problem+json')

    def db():
        with factory() as s:
            yield s

    def identity(authorization: str = Header(default=''), s=Depends(db)):
        if not authorization.startswith('Bearer '):
            raise HTTPException(401, 'Identificación necesaria')
        digest = hashlib.sha256(authorization[7:].encode()).hexdigest()
        token = s.get(Token, digest)
        if not token or token.kind != 'access' or token.expires_at < now():
            raise HTTPException(401, 'Sesión caducada')
        user = s.get(Account, token.user_id)
        if not user:
            raise HTTPException(401, 'Cuenta no disponible')
        return user

    def pack(r):
        defaults = {'clientId':None,'explanation':'','type':'qa','citations':[],'options':[],'correct':None} if r.kind == 'card' else {}
        return {**defaults, **r.data, 'id': r.id, 'revision': r.revision}

    def own(s, id, user, kind=None):
        r = s.get(Record, id)
        if not r or r.owner != user.id or (kind and r.kind != kind):
            raise HTTPException(404, 'Recurso no encontrado')
        return r

    def issue(s, user, session=None, commit=True):
        if session is None:
            session = UserSession(user_id=user.id)
            s.add(session)
            s.flush()
        session.last_active_at = now()
        result = {'userId': user.id, 'role': user.role}
        for kind, duration in [('access', timedelta(minutes=15)), ('refresh', timedelta(days=30))]:
            raw = secrets.token_urlsafe(48)
            digest = hashlib.sha256(raw.encode()).hexdigest()
            s.add(Token(digest=digest, user_id=user.id,
                        kind=kind, expires_at=(datetime.now(timezone.utc) + duration).isoformat()))
            s.flush()
            s.add(SessionToken(digest=digest, session_id=session.id))
            result[kind + 'Token'] = raw
        s.flush()
        s.execute(delete(Token).where(Token.expires_at < now()))
        s.execute(delete(UserSession).where(UserSession.id.not_in(select(SessionToken.session_id))))
        s.execute(delete(RecoveryReceipt).where(RecoveryReceipt.expires_at < now()))
        if commit:
            s.commit()
        return result

    class IdentityInput(BaseModel):
        idToken: str = Field(min_length=20, max_length=16000)

    def verified_identity(body):
        if not app.state.identity_verifier.project:
            raise HTTPException(503, 'Configura FIREBASE_PROJECT_ID para el acceso con Google/Apple')
        try:
            return app.state.identity_verifier.verify(body.idToken)
        except IdentityError:
            raise HTTPException(401, 'No se ha podido verificar la identidad')

    @app.post('/v1/auth/oidc')
    def oidc_login(body: IdentityInput, s=Depends(db)):
        claim = verified_identity(body)
        external = s.scalar(select(ExternalIdentity).where(ExternalIdentity.issuer == claim['issuer'], ExternalIdentity.subject == claim['subject']))
        if external:
            user = s.get(Account, external.user_id)
        else:
            user = Account(); s.add(user); s.flush()
            s.add(ExternalIdentity(user_id=user.id, **claim))
        try:
            return issue(s, user)
        except IntegrityError:
            s.rollback()
            raise HTTPException(409, 'Acceso concurrente; reintenta')

    @app.post('/v1/auth/link')
    def oidc_link(body: IdentityInput, user=Depends(identity), s=Depends(db)):
        claim = verified_identity(body)
        external = s.scalar(select(ExternalIdentity).where(ExternalIdentity.issuer == claim['issuer'], ExternalIdentity.subject == claim['subject']))
        if external:
            if external.user_id != user.id:
                raise HTTPException(409, 'Esta identidad pertenece a otra cuenta; recupera esa cuenta antes de fusionar datos')
            return {'linked': True}
        s.add(ExternalIdentity(user_id=user.id, **claim))
        try:
            s.commit()
        except IntegrityError:
            s.rollback()
            raise HTTPException(409, 'Vinculación concurrente; reintenta')
        return {'linked': True}

    @app.get('/health')
    def health(s=Depends(db)):
        s.execute(select(1))
        return {'status': 'ok', 'version': app.version, 'database': engine.dialect.name,
                'firebaseProject': app.state.identity_verifier.project or None, 'coverage': 'not-certified'}

    @app.post('/v1/auth/guest', status_code=201)
    def guest(s=Depends(db)):
        user = Account()
        s.add(user)
        s.flush()
        return issue(s, user)

    class Refresh(BaseModel):
        refreshToken: str = Field(min_length=20, max_length=256)

    @app.get('/v1/auth/session')
    def current_session(user=Depends(identity)):
        # Minimal authenticated identity proof for safe client-session upgrades.
        return {'userId': user.id}

    @app.get('/v1/sync/status')
    def synchronization_status(user=Depends(identity), s=Depends(db)):
        clock=s.get(AccountSyncClock,user.id)
        workspace=s.scalar(select(Record.revision).where(Record.id==user.id+':workspace'))
        profile=s.scalar(select(Record.revision).where(Record.id==user.id+':account-profile'))
        return {'userId':user.id,'progressVersion':clock.version if clock else 0,
                'workspaceRevision':workspace or 0,
                'profileRevision':profile or 0}

    @app.post('/v1/auth/refresh')
    def refresh(body: Refresh, s=Depends(db)):
        t = s.get(Token, hashlib.sha256(body.refreshToken.encode()).hexdigest())
        if not t or t.kind != 'refresh' or t.expires_at < now():
            raise HTTPException(401, 'Renovación no disponible')
        user = s.get(Account, t.user_id)
        session = session_for_token(s, t.digest)
        if session:
            # Serialize refresh/revocation for this token family on PostgreSQL.
            session = s.scalar(select(UserSession).where(UserSession.id == session.id).with_for_update())
        consumed = s.execute(delete(Token).where(Token.digest == t.digest, Token.kind == 'refresh'))
        if consumed.rowcount != 1:
            s.rollback()
            raise HTTPException(401, 'Renovación no disponible')
        return issue(s, user, session)

    def new_recovery(s, user):
        s.execute(delete(RecoveryReceipt).where(RecoveryReceipt.user_id == user.id))
        s.execute(delete(RecoveryCode).where(RecoveryCode.user_id == user.id))
        raw = secrets.token_urlsafe(32)
        s.add(RecoveryCode(digest=hashlib.sha256(raw.encode()).hexdigest(), user_id=user.id))
        s.commit()
        return raw

    @app.post('/v1/auth/recovery-code')
    def recovery_code(user=Depends(identity), s=Depends(db)):
        return {'recoveryCode': new_recovery(s, user), 'oneTime': True,
                'warning': 'Guárdalo fuera del dispositivo. Sustituye al código anterior y solo se muestra ahora.'}

    class RecoveryInput(BaseModel):
        recoveryCode: str = Field(min_length=20, max_length=128)
        attemptId: str | None = Field(default=None, min_length=32, max_length=80, pattern=r'^[A-Za-z0-9_-]+$')
        attemptSecret: str | None = Field(default=None, min_length=32, max_length=128)

    @app.post('/v1/auth/recover')
    @app.post('/v1/auth/recover-idempotent')
    def recover(body: RecoveryInput, request: Request, s=Depends(db)):
        if request.url.path.endswith('recover-idempotent') and not body.attemptId:
            raise HTTPException(422, 'Se requiere identificador y secreto del intento')
        if bool(body.attemptId) != bool(body.attemptSecret):
            raise HTTPException(422, 'Reintento incompleto')
        s.execute(delete(RecoveryReceipt).where(RecoveryReceipt.expires_at < now()))
        previous = read_receipt(s, body)
        if previous:
            return previous
        code = s.get(RecoveryCode, hashlib.sha256(body.recoveryCode.encode()).hexdigest())
        if not code:
            previous = read_receipt(s, body)
            if previous:
                return previous
            raise HTTPException(401, 'Código de recuperación no válido o ya utilizado')
        user = s.get(Account, code.user_id)
        # Consume once with an atomic conditional delete, including concurrent attempts.
        consumed = s.execute(delete(RecoveryCode).where(RecoveryCode.digest == code.digest))
        if consumed.rowcount != 1:
            s.rollback()
            previous = read_receipt(s, body)
            if previous:
                return previous
            raise HTTPException(401, 'Código de recuperación no válido o ya utilizado')
        s.execute(delete(Token).where(Token.user_id == user.id))
        s.execute(delete(UserSession).where(UserSession.user_id == user.id))
        s.execute(delete(RecoveryReceipt).where(RecoveryReceipt.user_id == user.id))
        replacement = secrets.token_urlsafe(32)
        s.add(RecoveryCode(digest=hashlib.sha256(replacement.encode()).hexdigest(), user_id=user.id))
        session = issue(s, user, commit=False)
        result = {**session, 'recoveryCode': replacement}
        add_receipt(s, body, user.id, result)
        s.commit()
        return result

    @app.post('/v1/auth/logout')
    def logout(authorization: str = Header(default=''), user=Depends(identity), s=Depends(db)):
        return revoke_current(s, user, authorization)

    @app.get('/v1/library/coverage')
    def coverage(s=Depends(db)):
        from collections import Counter
        norms = list(s.scalars(select(Record).where(Record.kind == 'norm')))
        versions = list(s.scalars(select(Record.data).where(Record.kind == 'norm_version')))
        return {'identified': len(norms), 'accessibleTexts': sum(bool(n.data.get('latestVersion')) for n in norms),
                'snapshots': len(versions), 'structuredBlocks': sum(len(v.get('blocks', [])) for v in versions),
                'bySource': dict(Counter(n.data.get('source', 'unknown') for n in norms)),
                'byJurisdiction': dict(Counter(n.data.get('jurisdiction', 'unknown') for n in norms)),
                'byReviewState': dict(Counter(n.data.get('reviewState', 'pending') for n in norms)),
                'verifiedEducationalObjects': s.query(Record).filter(Record.kind == 'card', Record.owner.is_(None),
                    Record.data['editorialState'].as_string() == 'approved').count(),
                'claim': 'Inventario de esta instalación. Importación no equivale a validación jurídica.'}

    @app.get('/v1/library/norms')
    def norms(q: str = '', cursor: str = '', limit: int = 30, jurisdiction: str = '', source: str = '',
              kind: str = '', reviewState: str = '', s=Depends(db)):
        if not 1 <= limit <= 100 or len(q) > 200:
            raise HTTPException(422, 'Límite entre 1 y 100 y búsqueda de hasta 200 caracteres')
        stmt = select(Record).where(Record.kind == 'norm', Record.id > cursor).order_by(Record.id)
        if q or jurisdiction or source or kind or reviewState:
            stmt = stmt.join(NormIndex, NormIndex.norm_id == Record.id)
            for word in normalize(q).split():
                stmt = stmt.where(NormIndex.text.contains(word, autoescape=True))
            for column, value in [(NormIndex.jurisdiction, jurisdiction), (NormIndex.source, source),
                                  (NormIndex.kind, kind), (NormIndex.review_state, reviewState)]:
                if value:
                    stmt = stmt.where(column == value)
        rows = list(s.scalars(stmt.limit(limit + 1)))
        return {'items': [pack(r) for r in rows[:limit]], 'nextCursor': rows[limit - 1].id if len(rows) > limit else None,
                'coverage': {'claim': 'Solo normas importadas; revisión jurídica pendiente', 'certified': False}}

    @app.get('/v1/library/norms/{id}')
    def norm(id: str, s=Depends(db)):
        r = s.get(Record, id)
        if not r or r.kind != 'norm':
            raise HTTPException(404, 'Norma no importada')
        return pack(r)

    @app.get('/v1/library/norms/{id}/versions')
    def versions(id: str, s=Depends(db)):
        return {'items': [{k: v for k, v in pack(r).items() if k not in ('blocks', 'rawXml', 'rawMetadata')} for r in s.scalars(select(Record).where(
            Record.kind == 'norm_version', Record.data['normId'].as_string() == id).order_by(Record.created_at))]}

    @app.get('/v1/library/norms/{id}/units')
    def units(id: str, version: str, asOf: str | None = None, s=Depends(db)):
        r = s.get(Record, version)
        if not r or r.kind != 'norm_version' or r.data['normId'] != id:
            raise HTTPException(404, 'Versión no disponible')
        result = {'version': version, 'items': r.data['blocks'], 'informative': True}
        if asOf is not None:
            try:
                target = civil_date(asOf)
            except (ValueError, TypeError):
                raise HTTPException(422, 'asOf debe ser una fecha civil AAAA-MM-DD válida')
            result['asOf'] = target.isoformat()
            result['resolvedUnits'] = [resolve_block(b, target) for b in r.data['blocks']]
            result['unresolvedCount'] = sum(b['selectedVersion'] is None for b in result['resolvedUnits'])
        return result

    @app.get('/v1/library/units/{id}/compare')
    def compare(id: str, old: str, new: str, s=Depends(db)):
        import difflib
        versions_ = [s.get(Record, v) for v in (old, new)]
        if any(v is None or v.kind != 'norm_version' for v in versions_):
            raise HTTPException(404, 'Versión no disponible')
        if versions_[0].data['normId'] != versions_[1].data['normId']:
            raise HTTPException(422, 'Normas distintas')
        texts = []
        for v in versions_:
            block = next((b for b in v.data['blocks'] if b['id'] == id), None)
            texts.append(block['versions'][-1]['text'] if block else '')
        return {'diff': list(difflib.unified_diff(texts[0].splitlines(), texts[1].splitlines(), lineterm='')),
                'impact': 'possible', 'legalInterpretation': False}

    @app.get('/v1/legal-updates')
    def updates(cursor: str = '', limit: int = 50, s=Depends(db)):
        if not 1 <= limit <= 100:
            raise HTTPException(422, 'Límite entre 1 y 100')
        rows = list(s.scalars(select(Record).where(
            Record.kind == 'legal_event', Record.id > cursor).order_by(Record.id).limit(limit + 1)))
        return {'items': [pack(r) for r in rows[:limit]],
                'nextCursor': rows[limit - 1].id if len(rows) > limit else None}

    class FollowInput(BaseModel):
        normIds: list[str] = Field(default_factory=list, max_length=1000)
        enabled: bool = True
        frequency: str = 'immediate'

    @app.post('/v1/legal-updates/subscriptions')
    def follow(body: FollowInput, user=Depends(identity), s=Depends(db)):
        if body.frequency not in ('immediate', 'daily', 'weekly') or len(set(body.normIds)) != len(body.normIds):
            raise HTTPException(422, 'Frecuencia o normas no válidas')
        for norm_id in body.normIds:
            norm = s.get(Record, norm_id)
            if not norm or norm.kind != 'norm':
                raise HTTPException(422, 'Norma no disponible')
        id_ = 'follows:' + user.id
        row = s.get(Record, id_)
        data = {**(row.data if row else {}), **body.model_dump(), 'channel': 'in_app', 'since': row.data.get('since', now()) if row else now()}
        if row:
            row.data = data
        else:
            row = Record(id=id_, kind='subscription_follow', owner=user.id, data=data)
            s.add(row)
        s.commit()
        return pack(row)

    @app.get('/v1/notifications')
    def notifications(cursor: str = '', limit: int = 50, user=Depends(identity), s=Depends(db)):
        if not 1 <= limit <= 100:
            raise HTTPException(422, 'Límite entre 1 y 100')
        inbox(s, user.id)
        study_notices(s, user.id)
        release_optional_notices(s, user.id)
        rows = list(s.scalars(select(Record).where(Record.kind == 'notification_delivery', Record.owner == user.id,
                                                  Record.id > cursor, Record.data['status'].as_string() != 'queued').order_by(Record.id).limit(limit + 1)))
        return {'items': [pack(r) for r in rows[:limit]], 'nextCursor': rows[limit - 1].id if len(rows) > limit else None}

    @app.post('/v1/notifications/{id}/read')
    def read_notification(id: str, user=Depends(identity), s=Depends(db)):
        row = own(s, id, user, 'notification_delivery')
        row.data = {**row.data, 'read': True}
        s.commit()
        return pack(row)

    class ReportInput(BaseModel):
        clientId: str = Field(min_length=8, max_length=80, pattern=r'^[A-Za-z0-9_-]+$')
        cardId: str
        reason: str = Field(min_length=5, max_length=4000)
        severity: str = 'normal'

    @app.post('/v1/reports', status_code=201)
    def report(body: ReportInput, user=Depends(identity), s=Depends(db)):
        own(s, body.cardId, user, 'card')
        if body.severity not in ('normal', 'high', 'critical'):
            raise HTTPException(422, 'Severidad no válida')
        id_ = user.id + ':report:' + body.clientId
        row = s.get(Record, id_)
        if row:
            if any(row.data.get(k) != v for k, v in body.model_dump().items()):
                raise HTTPException(409, 'Reporte reutilizado con otros datos')
            return pack(row)
        row = Record(id=id_, kind='report', owner=user.id, data={**body.model_dump(), 'status': 'received',
                     'history': [{'status': 'received', 'at': now()}]})
        s.add(row)
        s.commit()
        return pack(row)

    @app.get('/v1/reports')
    def reports(user=Depends(identity), s=Depends(db)):
        return {'items': [pack(r) for r in s.scalars(select(Record).where(
            Record.kind == 'report', Record.owner == user.id).order_by(Record.created_at, Record.id))]}

    class DeckInput(BaseModel):
        title: str = Field(min_length=1, max_length=160)
        visibility: str = 'private'
        clientId: str | None = Field(default=None, min_length=8, max_length=80, pattern=r'^[A-Za-z0-9_-]+$')

    @app.get('/v1/decks')
    def decks(cursor: str = '', limit: int = 20, q: str = '', user=Depends(identity), s=Depends(db)):
        if not 1 <= limit <= 100 or len(q)>120: raise HTTPException(422, 'Consulta no válida')
        escaped = q.replace('\\','\\\\').replace('%','\\%').replace('_','\\_')
        rows = list(s.scalars(select(Record).where(Record.kind == 'deck', Record.owner == user.id,
            Record.id > cursor, Record.data['title'].as_string().ilike('%'+escaped+'%',escape='\\')).order_by(Record.id).limit(limit + 1)))
        return {'items': [pack(r) for r in rows[:limit]], 'nextCursor': rows[limit - 1].id if len(rows) > limit else None}

    @app.post('/v1/decks', status_code=201)
    def deck(body: DeckInput, user=Depends(identity), s=Depends(db)):
        if body.visibility != 'private':
            raise HTTPException(422, 'La publicación requiere moderación editorial')
        id_ = user.id + ':deck:' + body.clientId if body.clientId else uid()
        old = s.get(Record, id_)
        if old:
            if old.owner != user.id or old.kind != 'deck' or old.data != body.model_dump():
                raise HTTPException(409, 'Identificador de mazo en conflicto')
            return pack(old)
        r = Record(id=id_, kind='deck', owner=user.id, data=body.model_dump())
        s.add(r)
        s.commit()
        return pack(r)

    class CardInput(BaseModel):
        deckId: str
        clientId: str | None = Field(default=None, min_length=8, max_length=80, pattern=r'^[A-Za-z0-9_-]+$')
        front: str = Field(min_length=1, max_length=4000)
        back: str = Field(min_length=1, max_length=8000)
        explanation: str = Field(default='', max_length=8000)
        type: str = 'qa'
        citations: list[dict] = Field(default_factory=list, max_length=20)
        options: list[str] = Field(default_factory=list, max_length=12)
        correct: int | None = None

    def validate_card(s, body):
        try:
            validate_exercise(body.model_dump())
        except ValueError as exc:
            raise HTTPException(422, str(exc))
        pending = False
        for citation in body.citations:
            # A private backup retains client provenance even when this server
            # has not imported that immutable source version. Never import or
            # certify a legal source from user-supplied citation identifiers.
            for key in ('normId', 'versionId', 'unitId'):
                value = citation.get(key)
                if not isinstance(value, str) or not value.strip() or len(value) > 512:
                    raise HTTPException(422, 'Referencia normativa incompleta o no válida')
            digest = citation.get('unitVersionHash', '')
            if not isinstance(digest, str) or len(digest) > 512:
                raise HTTPException(422, 'Huella de referencia no válida')
            version = s.get(Record, citation.get('versionId', ''))
            if version is None:
                pending = True
                continue
            if version.kind != 'norm_version' or version.data.get('normId') != citation.get('normId') or not any(b['id'] == citation.get('unitId') for b in version.data['blocks']):
                raise HTTPException(422, 'Referencia normativa inexistente')
            if citation.get('unitVersionHash'):
                block = next(b for b in version.data['blocks'] if b['id'] == citation['unitId'])
                if not any(v.get('hash') == citation['unitVersionHash'] for v in block.get('versions', [])):
                    raise HTTPException(422, 'Redacción histórica inexistente')
        return 'pending_source' if pending else ('matched_source' if body.citations else 'uncited')

    @app.post('/v1/cards', status_code=201)
    def card(body: CardInput, user=Depends(identity), s=Depends(db)):
        own(s, body.deckId, user, 'deck')
        citation_state = validate_card(s, body)
        id_ = user.id + ':card:' + body.clientId if body.clientId else uid()
        old = s.get(Record, id_)
        if old is None and body.clientId:
            candidates = list(s.scalars(select(Record).where(Record.kind == 'card', Record.owner == user.id,
                Record.client_id == body.clientId).limit(2)))
            if len(candidates) > 1:
                raise HTTPException(409, 'Identificador de tarjeta ambiguo; conserva los datos y compara')
            old = candidates[0] if candidates else None
        if old:
            if old.owner != user.id or old.kind != 'card' or any(old.data.get(k) != v for k, v in body.model_dump().items()):
                raise HTTPException(409, 'Identificador de tarjeta en conflicto')
            return pack(old)
        r = Record(id=id_, kind='card', owner=user.id, data={**body.model_dump(), 'citationState': citation_state, 'editorialState': 'user', 'authorId': user.id})
        s.add(r)
        publication = s.get(Record, body.deckId + ':publication')
        if publication:
            publication.data = {**publication.data, 'state': 'pending'}
        s.commit()
        return pack(r)

    @app.get('/v1/cards/by-client/{client_id}')
    def card_by_client(client_id: str, user=Depends(identity), s=Depends(db)):
        if not 8 <= len(client_id) <= 80:raise HTTPException(404, 'Tarjeta no encontrada')
        rows = list(s.scalars(select(Record).where(Record.kind == 'card', Record.owner == user.id,
            Record.client_id == client_id).limit(2)))
        if len(rows) != 1:raise HTTPException(404 if not rows else 409, 'Tarjeta no disponible o ambigua')
        deck = own(s, rows[0].data['deckId'], user, 'deck')
        return {**pack(rows[0]), 'deckTitle': deck.data['title']}

    class CardLookup(BaseModel):
        clientIds: list[str] = Field(min_length=1, max_length=100)

    @app.post('/v1/cards/lookup')
    def cards_lookup(body: CardLookup, user=Depends(identity), s=Depends(db)):
        if any(not 8 <= len(value) <= 80 for value in body.clientIds):
            raise HTTPException(422, 'Identificador de tarjeta no válido')
        rows = s.scalars(select(Record).where(Record.kind=='card',Record.owner==user.id,
            Record.client_id.in_(body.clientIds)))
        result = {}; decks = {}
        for row in rows:
            client_id = row.data['clientId']
            if client_id in result:raise HTTPException(409,'Identificador de tarjeta ambiguo; conserva y compara')
            deck_id = row.data['deckId']
            if deck_id not in decks:decks[deck_id] = own(s,deck_id,user,'deck').data['title']
            result[client_id] = {**pack(row),'deckTitle':decks[deck_id]}
        missing = set(body.clientIds) - set(result)
        if missing:
            for row in s.scalars(select(Record).where(Record.kind=='card',Record.owner==user.id,
                Record.client_id.is_(None))):
                legacy_id = str(uuid5(NAMESPACE_DNS,row.id))
                if legacy_id not in missing:continue
                deck_id = row.data['deckId']
                if deck_id not in decks:decks[deck_id] = own(s,deck_id,user,'deck').data['title']
                result[legacy_id] = {**pack(row),'lookupClientId':legacy_id,'deckTitle':decks[deck_id]}
        return {'items': list(result.values())}

    @app.get('/v1/cards/{id}/history')
    def card_history(id: str, user=Depends(identity), s=Depends(db)):
        own(s, id, user, 'card')
        rows = s.scalars(select(Record).where(Record.kind == 'card_revision', Record.owner == user.id,
                                            Record.data['cardId'].as_string() == id).order_by(Record.created_at, Record.id))
        return {'items': [pack(r) for r in rows]}

    @app.put('/v1/cards/{id}')
    def edit_card(id: str, body: CardInput, if_match: str = Header(), user=Depends(identity), s=Depends(db)):
        card = own(s, id, user, 'card')
        own(s, body.deckId, user, 'deck')
        citation_state = validate_card(s, body)
        if body.clientId != card.data.get('clientId'):
            raise HTTPException(422, 'El identificador estable no puede cambiar')
        if all(card.data.get(k) == v for k, v in body.model_dump().items()):
            return JSONResponse(pack(card), headers={'ETag': str(card.revision)})
        if if_match.strip('"') != str(card.revision):
            raise HTTPException(409, 'Conflicto de edición; conserva ambas versiones')
        s.add(Record(kind='card_revision', owner=user.id, data={
            'cardId': id, 'cardRevision': card.revision, 'content': card.data, 'archivedAt': now()}))
        card.data = {**body.model_dump(), 'citationState': citation_state, 'editorialState': 'user', 'authorId': user.id,
                     'blocked': bool(card.data.get('blocked')), 'updatedAt': now(),
                     **({k: card.data[k] for k in ('sourceCardId', 'sourceCardRevision') if k in card.data}),
                     **({'sourceDetached': True} if card.data.get('sourceCardId') else {})}
        publication = s.get(Record, body.deckId + ':publication')
        if publication:
            publication.data = {**publication.data, 'state': 'pending'}
        s.commit()
        return JSONResponse(pack(card), headers={'ETag': str(card.revision)})

    class ReviewInput(BaseModel):
        cardId: str
        cardRevision: int = Field(ge=1)
        rating: int = Field(ge=1, le=4)
        occurredAt: datetime
        idempotencyKey: str = Field(min_length=8, max_length=128)
        state: dict = Field(default_factory=dict)
        latencyMs: int = Field(default=0, ge=0, le=86400000)
        response: int | list[int] | dict[str, str] | None = None

    @app.post('/v1/reviews', status_code=201)
    def review(body: ReviewInput, user=Depends(identity), s=Depends(db)):
        if body.occurredAt.tzinfo is None or body.occurredAt > datetime.now(timezone.utc) + timedelta(minutes=5):
            raise HTTPException(422, 'Fecha UTC válida requerida')
        payload_hash = hashlib.sha256(body.model_dump_json().encode()).hexdigest()
        previous = s.scalar(select(Mutation).where(Mutation.user_id == user.id, Mutation.key == body.idempotencyKey))
        if previous:
            if previous.payload_hash != payload_hash:
                raise HTTPException(409, 'Clave reutilizada con otro contenido')
            return previous.result
        c = own(s, body.cardId, user, 'card')
        historical = None
        if c.revision != body.cardRevision:
            historical = s.scalar(select(Record).where(Record.kind == 'card_revision', Record.owner == user.id,
                Record.data['cardId'].as_string() == c.id,
                Record.data['cardRevision'].as_integer() == body.cardRevision))
        if c.data.get('blocked') or (c.revision != body.cardRevision and historical is None):
            raise HTTPException(409, 'Tarjeta modificada o pendiente de revisión')
        try:
            objective = grade_exercise(historical.data['content'] if historical else c.data, body.response)
        except ValueError as exc:
            raise HTTPException(422, str(exc))
        state_id = user.id + ':' + c.id
        r = s.get(Record, state_id)
        # Do not trust a client-provided interval or ease.
        state = {**schedule(r.data if r else {}, body.rating, body.occurredAt), 'cardId': c.id}
        if r:
            if datetime.fromisoformat(r.data['reviewedAt']) > body.occurredAt:
                raise HTTPException(409, 'Revisión anterior al estado sincronizado; resolver conflicto')
            r.data = state
        else:
            s.add(Record(id=state_id, kind='review_state', owner=user.id, data=state))
        result = {'cardId': c.id, 'state': state}
        s.add(Record(kind='review_event', owner=user.id, data={**body.model_dump(mode='json'), 'algorithm': 'sm2-1', 'objectiveCorrect': objective}))
        s.add(Mutation(user_id=user.id, key=body.idempotencyKey, payload_hash=payload_hash, result=result))
        try:
            s.commit()
        except IntegrityError:
            s.rollback()
            raise HTTPException(409, 'Operación concurrente; reintentar con la misma clave')
        return result

    @app.get('/v1/study/today')
    def today(user=Depends(identity), s=Depends(db)):
        return {'cards': [pack(r) for r in s.scalars(select(Record).where(Record.kind == 'card', Record.owner == user.id))],
                'states': [pack(r) for r in s.scalars(select(Record).where(Record.kind == 'review_state', Record.owner == user.id))]}

    class WorkspaceInput(BaseModel):
        profile: dict = Field(default_factory=dict)
        notes: dict[str, str] = Field(default_factory=dict)
        courses: list[dict] = Field(default_factory=list, max_length=500)
        follows: list[str] = Field(default_factory=list, max_length=1000)
        bookmarks: list[str] = Field(default_factory=list, max_length=10000)
        favoriteCards: list[str] = Field(default_factory=list, max_length=20000)
        readerPositions: dict = Field(default_factory=dict)
        examHistory: list[dict] = Field(default_factory=list, max_length=2000)
        activeExam: dict | None = None

    @app.get('/v1/workspace')
    def workspace(user=Depends(identity), s=Depends(db)):
        row = s.get(Record, user.id + ':workspace')
        return {'data': row.data if row else None, 'revision': row.revision if row else 0}

    @app.put('/v1/workspace')
    def save_workspace(body: WorkspaceInput, if_match: str = Header(), user=Depends(identity), s=Depends(db)):
        id_ = user.id + ':workspace'
        row = s.get(Record, id_)
        if if_match.strip('"') != str(row.revision if row else 0):
            raise HTTPException(409, 'El espacio de estudio ha cambiado; conserva ambas versiones y vuelve a sincronizar')
        if any(len(k) > 256 or len(v) > 20000 for k, v in body.notes.items()):
            raise HTTPException(422, 'Nota demasiado larga')
        # Older clients only know four sections. Do not erase newer sections
        # when those clients save their explicitly supplied fields.
        data = {**(row.data if row else {}), **body.model_dump(exclude_unset=True)}
        if row:
            row.data = data
        else:
            row = Record(id=id_, kind='workspace', owner=user.id, data=data)
            s.add(row)
        try:
            s.commit()
        except IntegrityError:
            s.rollback()
            raise HTTPException(409, 'Edición concurrente del espacio de estudio; reintenta')
        return JSONResponse({'data': row.data, 'revision': row.revision}, headers={'ETag': str(row.revision)})

    class PrivateInput(BaseModel):
        kind: str
        data: dict

    @app.post('/v1/private', status_code=201)
    def private(body: PrivateInput, user=Depends(identity), s=Depends(db)):
        if body.kind not in ['profile', 'plan', 'note', 'report', 'notification_preferences', 'subscription_follow']:
            raise HTTPException(422, 'Tipo no permitido')
        r = Record(kind=body.kind, owner=user.id, data=body.data)
        s.add(r)
        s.commit()
        return pack(r)

    class RevisionInput(BaseModel):
        data: dict

    @app.put('/v1/private/{id}')
    def edit(id: str, body: RevisionInput, if_match: str = Header(), user=Depends(identity), s=Depends(db)):
        r = own(s, id, user)
        if r.kind not in ['profile', 'plan', 'note', 'deck']:
            raise HTTPException(403, 'Registro inmutable')
        if if_match.strip('"') != str(r.revision):
            raise HTTPException(409, 'Conflicto de edición; conserva ambas versiones')
        if r.kind == 'deck':
            if set(body.data) - {'title', 'visibility'} or body.data.get('visibility', 'private') != 'private':
                raise HTTPException(422, 'Usa los permisos de colaboración; no se puede modificar la procedencia del mazo')
            title = body.data.get('title', r.data.get('title'))
            if not isinstance(title, str) or not 1 <= len(title.strip()) <= 160:
                raise HTTPException(422, 'Título no válido')
            r.data = {**r.data, 'title': title.strip(), 'visibility': 'private'}
            publication = s.get(Record, r.id + ':publication')
            if publication: publication.data = {**publication.data, 'state': 'pending'}
        else:
            r.data = body.data
        r.revision += 1
        s.commit()
        return JSONResponse(pack(r), headers={'ETag': str(r.revision)})

    @app.get('/v1/account/export')
    def export(user=Depends(identity), s=Depends(db)):
        return {'schemaVersion': 1, 'exportedAt': now(), 'userId': user.id,
                'accountCreatedAt': user.created_at,
                'collaboration': {
                    'memberships': [{'targetId': m.target_id, 'role': m.role} for m in s.scalars(select(Membership).where(Membership.user_id == user.id))],
                    'connections': [{'id': r.id, 'otherUserId': r.target_id if r.source_id == user.id else r.source_id,
                                     'kind': r.kind, 'outgoing': r.source_id == user.id} for r in s.scalars(select(Relationship).where(
                                        (Relationship.source_id == user.id) | ((Relationship.target_id == user.id) & (Relationship.kind != 'blocked'))))],
                    'invitations': [{'id': i.id, 'targetId': i.target_id, 'role': i.role, 'expiresAt': i.expires_at,
                                     'revoked': i.revoked} for i in s.scalars(select(Invitation).where(
                                        (Invitation.issuer_id == user.id) | (Invitation.recipient_id == user.id)))]},
                'records': [{**pack(r), 'kind': r.kind} for r in s.scalars(select(Record).where(Record.owner == user.id))]}

    @app.delete('/v1/account')
    def erase(confirmation: str, user=Depends(identity), s=Depends(db)):
        if confirmation != 'ELIMINAR':
            raise HTTPException(422, 'Confirmación específica requerida')
        owned_groups = select(Record.id).where(Record.kind == 'study_group', Record.owner == user.id)
        s.execute(delete(Record).where(Record.kind == 'group_resource', Record.data['groupId'].as_string().in_(owned_groups)))
        for copy in s.scalars(select(Record).where(Record.kind == 'deck', Record.data['attribution']['id'].as_string() == user.id)):
            copy.data = {**copy.data, 'attribution': {'displayName': 'Autor retirado'}}
        s.execute(delete(Record).where(Record.owner == user.id))
        s.execute(delete(Mutation).where(Mutation.user_id == user.id))
        s.execute(delete(Token).where(Token.user_id == user.id))
        s.execute(delete(UserSession).where(UserSession.user_id == user.id))
        s.execute(delete(AliasClaim).where(AliasClaim.user_id == user.id))
        s.execute(delete(RecoveryCode).where(RecoveryCode.user_id == user.id))
        s.execute(delete(ExternalIdentity).where(ExternalIdentity.user_id == user.id))
        s.delete(s.get(Account, user.id))
        s.commit()
        return {'deleted': True, 'backupRetention': 'Configure según política antes de producción'}

    class IdentityDeletion(BaseModel):
        idToken: str = Field(min_length=20, max_length=16000)
        confirmation: str
        expectedUserId: str | None = None

    def deletion_identity(body, s):
        try:
            claim = app.state.identity_verifier.verify(body.idToken, max_auth_age=300)
        except IdentityError:
            raise HTTPException(401, 'Identifícate de nuevo para eliminar la cuenta')
        external = s.scalar(select(ExternalIdentity).where(ExternalIdentity.issuer == claim['issuer'], ExternalIdentity.subject == claim['subject']))
        if external and body.expectedUserId and external.user_id != body.expectedUserId:
            raise HTTPException(409, 'La identidad elegida corresponde a otra cuenta')
        return external

    @app.post('/v1/account/check-deletion-identity')
    def check_deletion_identity(body: IdentityDeletion, s=Depends(db)):
        external = deletion_identity(body, s)
        if not external and body.expectedUserId:
            raise HTTPException(409, 'Esta identidad no está vinculada a la cuenta activa')
        return {'verified': True}

    @app.post('/v1/account/delete-with-identity')
    def erase_with_identity(body: IdentityDeletion, s=Depends(db)):
        if body.confirmation != 'ELIMINAR':
            raise HTTPException(422, 'Confirmación específica requerida')
        external = deletion_identity(body, s)
        if not external:
            return {'deleted': True, 'alreadyAbsent': True, 'firebaseDeletion': 'client_must_complete'}
        result = erase('ELIMINAR', s.get(Account, external.user_id), s)
        return {**result, 'firebaseDeletion': 'client_must_complete'}

    @app.get('/account/delete', response_class=HTMLResponse)
    def deletion_page():
        from pathlib import Path
        nonce = secrets.token_urlsafe(24)
        html = (Path(__file__).parent / 'web' / 'delete_account.html').read_text().replace('__NONCE__', nonce)
        return HTMLResponse(html, headers={'Referrer-Policy': 'no-referrer',
            'Content-Security-Policy': f"default-src 'none'; script-src 'nonce-{nonce}' https://www.gstatic.com; style-src 'nonce-{nonce}'; connect-src 'self' https://*.googleapis.com https://*.firebaseapp.com https://securetoken.googleapis.com; frame-src https://*.firebaseapp.com https://accounts.google.com; frame-ancestors 'none'; base-uri 'none'"})

    @app.get('/v1/public/identity-config')
    def public_identity_configuration():
        project = app.state.identity_verifier.project
        key = os.getenv('FIREBASE_WEB_API_KEY', '')
        if not project or not key:
            raise HTTPException(503, 'Acceso web pendiente de configuración; usa la eliminación desde la aplicación')
        return {'apiKey': key, 'projectId': project, 'authDomain': project + '.firebaseapp.com'}

    @app.get('/account/privacy', response_class=HTMLResponse)
    def privacy_contact_page():
        from html import escape
        name = os.getenv('PUBLIC_CONTROLLER_NAME', '')
        email = os.getenv('PUBLIC_SUPPORT_EMAIL', '')
        policy = os.getenv('PUBLIC_PRIVACY_POLICY_URL', '')
        configured = bool(name and email and policy.startswith('https://'))
        content = ('<p>Responsable: '+escape(name)+'</p><p>Contacto: '+escape(email)+'</p><p><a href="'+escape(policy, quote=True)+'">Política de privacidad</a></p>') if configured else '<p>Este servicio está en pruebas. La política definitiva y el contacto público del responsable están pendientes de configuración. Consulta la información de datos y fuentes de la aplicación.</p>'
        return HTMLResponse('<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Privacidad · LexMemoria</title><main><h1>Privacidad de LexMemoria</h1>'+content+'<p><a href="/account/delete">Eliminar cuenta</a></p></main></html>',
            status_code=200 if configured else 503,
            headers={'Referrer-Policy': 'no-referrer', 'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'; base-uri 'none'"})

    @app.get('/v1/payments/entitlements')
    def entitlements(user=Depends(identity), s=Depends(db)):
        return effective_entitlements(s, user)

    @app.post('/v1/payments/validate')
    def payment(user=Depends(identity)):
        raise HTTPException(503, 'Validación StoreKit/Play no configurada; no se conceden compras sin verificar')

    class AttemptInput(BaseModel):
        cardIds: list[str] = Field(min_length=1, max_length=200)
        penalty: float = Field(default=.25, ge=0, le=1)

    @app.post('/v1/exams/attempts', status_code=201)
    def attempt(body: AttemptInput, user=Depends(identity), s=Depends(db)):
        if len(set(body.cardIds)) != len(body.cardIds):
            raise HTTPException(422, 'Preguntas duplicadas')
        questions = []
        for id in body.cardIds:
            c = own(s, id, user, 'card')
            if c.data.get('blocked') or len(c.data.get('options', [])) < 2 or c.data.get('correct') is None:
                raise HTTPException(422, 'Pregunta no apta para simulacro')
            questions.append({'id': c.id, 'revision': c.revision, **c.data})
        r = Record(kind='attempt', owner=user.id, data={'questions': questions, 'penalty': body.penalty, 'status': 'started'})
        s.add(r)
        s.commit()
        return {'id': r.id, 'questions': [{k: v for k, v in q.items() if k not in ['correct', 'back', 'explanation']} for q in questions]}

    class Answers(BaseModel):
        responses: dict[str, int | None]

    @app.post('/v1/exams/attempts/{id}/submit')
    def submit(id: str, body: Answers, user=Depends(identity), s=Depends(db)):
        r = own(s, id, user, 'attempt')
        if r.data['status'] == 'completed':
            return r.data
        allowed = {q['id']: len(q['options']) for q in r.data['questions']}
        if any(k not in allowed or (v is not None and (v < 0 or v >= allowed[k])) for k, v in body.responses.items()):
            raise HTTPException(422, 'Respuesta fuera del banco congelado')
        result = score(r.data['questions'], body.responses, r.data['penalty'])
        r.data = {**r.data, 'status': 'completed', 'result': result, 'responses': body.responses, 'completedAt': now()}
        s.commit()
        return r.data

    def editorial(user, request, session):
        require_editorial(user, request, session)

    @app.get('/v1/admin/ingestions')
    def ingestions(request: Request, user=Depends(identity), s=Depends(db)):
        editorial(user, request, s)
        return {'items': [pack(r) for r in s.scalars(select(Record).where(Record.kind == 'ingestion'))]}

    class Approval(BaseModel):
        revision: int
        reason: str = Field(min_length=20, max_length=4000)

    @app.post('/v1/admin/editorial/{id}/approve')
    def approve(id: str, body: Approval, request: Request, user=Depends(identity), s=Depends(db)):
        editorial(user, request, s)
        r = s.get(Record, id)
        if not r or r.kind != 'card':
            raise HTTPException(404, 'Tarjeta no encontrada')
        if r.data.get('authorId') == user.id:
            raise HTTPException(403, 'No puedes aprobar tu propio contenido')
        if r.revision != body.revision:
            raise HTTPException(409, 'Revisión cambiada')
        if not r.data.get('citations'):
            raise HTTPException(422, 'Fuente y versión obligatorias')
        for citation in r.data['citations']:
            v = s.get(Record, citation.get('versionId', ''))
            norm = s.get(Record, citation.get('normId', ''))
            if not v or not norm or v.kind != 'norm_version' or norm.data.get('latestVersion') != v.id:
                raise HTTPException(422, 'Referencia obsoleta o no disponible')
            if not any(b['id'] == citation.get('unitId') for b in v.data['blocks']):
                raise HTTPException(422, 'Artículo no disponible')
        decisions = list(s.scalars(select(Audit).where(Audit.entity == id, Audit.action == 'approve')))
        reviewers = {a.actor for a in decisions if a.data.get('revision') == r.revision}
        if user.id in reviewers:
            raise HTTPException(409, 'Ya revisaste esta versión')
        s.add(Audit(actor=user.id, entity=id, action='approve', data=body.model_dump()))
        reviewers.add(user.id)
        if len(reviewers) >= 2:
            r.data = {**r.data, 'editorialState': 'approved', 'blocked': False, 'reviewers': sorted(reviewers)}
        s.commit()
        return pack(r)

    register_account_routes(app, identity, db, editorial)
    register_collaboration(app, identity, db, pack, CardInput, validate_card, editorial)
    return app


app = create_app()
