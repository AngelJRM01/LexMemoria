import hashlib
import json
import os
import secrets
import time
from collections import defaultdict, deque
from datetime import datetime, timedelta, timezone
from uuid import uuid4
from fastapi import FastAPI, Depends, Header, Request, HTTPException
from fastapi.responses import JSONResponse, Response
from pydantic import BaseModel, Field
from sqlalchemy import select, delete
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm.exc import StaleDataError
from .db import connect, Record, Account, Token, Mutation, Audit, now, uid
from .learning import schedule, score


def create_app(database_url=None):
    engine, factory = connect(database_url)
    app = FastAPI(title='LexMemoria', version='0.1.0')
    app.state.factory = factory
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
        if int(request.headers.get('content-length', '0')) > 2_000_000:
            return JSONResponse({'title': 'Solicitud demasiado grande', 'status': 413}, status_code=413)
        response = await call_next(request)
        response.headers['X-Request-ID'] = request_id
        response.headers['X-Content-Type-Options'] = 'nosniff'
        response.headers['Cache-Control'] = 'no-store'
        return response

    @app.exception_handler(HTTPException)
    async def error(request, exc):
        return JSONResponse({'type': 'about:blank', 'title': str(exc.detail), 'status': exc.status_code,
                             'requestId': request.state.request_id, 'retryable': exc.status_code in (429, 503)},
                            status_code=exc.status_code, media_type='application/problem+json')

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
        return {'id': r.id, 'revision': r.revision, **r.data}

    def own(s, id, user, kind=None):
        r = s.get(Record, id)
        if not r or r.owner != user.id or (kind and r.kind != kind):
            raise HTTPException(404, 'Recurso no encontrado')
        return r

    def issue(s, user):
        result = {'userId': user.id, 'role': user.role}
        for kind, duration in [('access', timedelta(minutes=15)), ('refresh', timedelta(days=30))]:
            raw = secrets.token_urlsafe(48)
            s.add(Token(digest=hashlib.sha256(raw.encode()).hexdigest(), user_id=user.id,
                        kind=kind, expires_at=(datetime.now(timezone.utc) + duration).isoformat()))
            result[kind + 'Token'] = raw
        s.commit()
        return result

    @app.get('/health')
    def health(s=Depends(db)):
        s.execute(select(1))
        return {'status': 'ok', 'version': '0.1.0', 'coverage': 'not-certified'}

    @app.post('/v1/auth/guest', status_code=201)
    def guest(s=Depends(db)):
        user = Account()
        s.add(user)
        s.flush()
        return issue(s, user)

    class Refresh(BaseModel):
        refreshToken: str = Field(min_length=20, max_length=256)

    @app.post('/v1/auth/refresh')
    def refresh(body: Refresh, s=Depends(db)):
        t = s.get(Token, hashlib.sha256(body.refreshToken.encode()).hexdigest())
        if not t or t.kind != 'refresh' or t.expires_at < now():
            raise HTTPException(401, 'Renovación no disponible')
        user = s.get(Account, t.user_id)
        s.delete(t)
        return issue(s, user)

    @app.post('/v1/auth/logout')
    def logout(user=Depends(identity), s=Depends(db)):
        s.execute(delete(Token).where(Token.user_id == user.id))
        s.commit()
        return {'revoked': True}

    @app.get('/v1/library/norms')
    def norms(q: str = '', cursor: str = '', limit: int = 30, s=Depends(db)):
        if not 1 <= limit <= 100:
            raise HTTPException(422, 'Límite entre 1 y 100')
        stmt = select(Record).where(Record.kind == 'norm', Record.id > cursor).order_by(Record.id)
        if q:
            # PostgreSQL JSON text cast supports indexed derived search in production migration.
            stmt = stmt.where(Record.data.cast(__import__('sqlalchemy').Text).ilike('%' + q[:200] + '%'))
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
        return {'items': [pack(r) for r in s.scalars(select(Record).where(
            Record.kind == 'norm_version', Record.data['normId'].as_string() == id).order_by(Record.created_at))]}

    @app.get('/v1/library/norms/{id}/units')
    def units(id: str, version: str, s=Depends(db)):
        r = s.get(Record, version)
        if not r or r.kind != 'norm_version' or r.data['normId'] != id:
            raise HTTPException(404, 'Versión no disponible')
        return {'version': version, 'items': r.data['blocks'], 'informative': True}

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
    def updates(cursor: str = '', s=Depends(db)):
        return {'items': [pack(r) for r in s.scalars(select(Record).where(
            Record.kind == 'legal_event', Record.id > cursor).order_by(Record.id).limit(100))]}

    class DeckInput(BaseModel):
        title: str = Field(min_length=1, max_length=160)
        visibility: str = 'private'
        clientId: str | None = Field(default=None, min_length=8, max_length=80, pattern=r'^[A-Za-z0-9_-]+$')

    @app.get('/v1/decks')
    def decks(user=Depends(identity), s=Depends(db)):
        return {'items': [pack(r) for r in s.scalars(select(Record).where(
            Record.kind == 'deck', Record.owner == user.id))]}

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
        options: list[str] = Field(default_factory=list, max_length=6)
        correct: int | None = None

    @app.post('/v1/cards', status_code=201)
    def card(body: CardInput, user=Depends(identity), s=Depends(db)):
        own(s, body.deckId, user, 'deck')
        if body.type not in ['qa', 'cloze', 'truefalse', 'order', 'case', 'test']:
            raise HTTPException(422, 'Tipo de ejercicio desconocido')
        if body.type == 'test' and (len(body.options) < 2 or body.correct is None or not 0 <= body.correct < len(body.options)):
            raise HTTPException(422, 'Opciones o solución no válidas')
        for c in body.citations:
            v = s.get(Record, c.get('versionId', ''))
            if not v or v.kind != 'norm_version' or not any(b['id'] == c.get('unitId') for b in v.data['blocks']):
                raise HTTPException(422, 'Referencia normativa inexistente')
        id_ = user.id + ':card:' + body.clientId if body.clientId else uid()
        old = s.get(Record, id_)
        if old:
            if old.owner != user.id or old.kind != 'card' or any(old.data.get(k) != v for k, v in body.model_dump().items()):
                raise HTTPException(409, 'Identificador de tarjeta en conflicto')
            return pack(old)
        r = Record(id=id_, kind='card', owner=user.id, data={**body.model_dump(), 'editorialState': 'user', 'authorId': user.id})
        s.add(r)
        s.commit()
        return pack(r)

    class ReviewInput(BaseModel):
        cardId: str
        cardRevision: int = Field(ge=1)
        rating: int = Field(ge=1, le=4)
        occurredAt: datetime
        idempotencyKey: str = Field(min_length=8, max_length=128)
        state: dict = Field(default_factory=dict)

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
        if c.revision != body.cardRevision or c.data.get('blocked'):
            raise HTTPException(409, 'Tarjeta modificada o pendiente de revisión')
        state_id = user.id + ':' + c.id
        r = s.get(Record, state_id)
        # Do not trust a client-provided interval or ease.
        state = schedule(r.data if r else {}, body.rating, body.occurredAt)
        if r:
            if datetime.fromisoformat(r.data['reviewedAt']) > body.occurredAt:
                raise HTTPException(409, 'Revisión anterior al estado sincronizado; resolver conflicto')
            r.data = state
        else:
            s.add(Record(id=state_id, kind='review_state', owner=user.id, data=state))
        result = {'cardId': c.id, 'state': state}
        s.add(Record(kind='review_event', owner=user.id, data={**body.model_dump(mode='json'), 'algorithm': 'sm2-1'}))
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
        r.data = body.data
        r.revision += 1
        s.commit()
        return JSONResponse(pack(r), headers={'ETag': str(r.revision)})

    @app.get('/v1/account/export')
    def export(user=Depends(identity), s=Depends(db)):
        return {'schemaVersion': 1, 'exportedAt': now(), 'userId': user.id,
                'records': [{'kind': r.kind, **pack(r)} for r in s.scalars(select(Record).where(Record.owner == user.id))]}

    @app.delete('/v1/account')
    def erase(confirmation: str, user=Depends(identity), s=Depends(db)):
        if confirmation != 'ELIMINAR':
            raise HTTPException(422, 'Confirmación específica requerida')
        s.execute(delete(Record).where(Record.owner == user.id))
        s.execute(delete(Mutation).where(Mutation.user_id == user.id))
        s.execute(delete(Token).where(Token.user_id == user.id))
        s.delete(s.get(Account, user.id))
        s.commit()
        return {'deleted': True, 'backupRetention': 'Configure según política antes de producción'}

    @app.get('/v1/payments/entitlements')
    def entitlements(user=Depends(identity), s=Depends(db)):
        # Promotions never become a store subscription or trigger charges.
        end = datetime.fromisoformat(user.created_at) + timedelta(days=30)
        return {'plan': 'promotion' if end.isoformat() > now() else 'free', 'expiresAt': end.isoformat(),
                'autoRenew': False, 'storePurchasesAvailable': False}

    @app.post('/v1/payments/validate')
    def payment(user=Depends(identity)):
        raise HTTPException(503, 'Validación StoreKit/Play no configurada; no se conceden compras sin verificar')

    class AttemptInput(BaseModel):
        cardIds: list[str] = Field(min_length=1, max_length=200)
        penalty: float = Field(default=.25, ge=0, le=1)

    @app.post('/v1/exams/attempts', status_code=201)
    def attempt(body: AttemptInput, user=Depends(identity), s=Depends(db)):
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

    def editorial(user):
        if user.role not in ['reviewer', 'publisher', 'admin']:
            raise HTTPException(403, 'Rol editorial requerido')
        # Editorial routes are disabled until external MFA gateway is configured.
        if os.getenv('EDITORIAL_MFA_GATEWAY') != 'configured':
            raise HTTPException(503, 'Configura y verifica la pasarela MFA editorial antes de habilitar publicaciones')

    @app.get('/v1/admin/ingestions')
    def ingestions(user=Depends(identity), s=Depends(db)):
        editorial(user)
        return {'items': [pack(r) for r in s.scalars(select(Record).where(Record.kind == 'ingestion'))]}

    class Approval(BaseModel):
        revision: int
        reason: str = Field(min_length=20, max_length=4000)

    @app.post('/v1/admin/editorial/{id}/approve')
    def approve(id: str, body: Approval, user=Depends(identity), s=Depends(db)):
        editorial(user)
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

    return app


app = create_app()
