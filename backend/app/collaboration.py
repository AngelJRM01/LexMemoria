"""Opt-in collaboration. Shared content never grants access to private progress."""
import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Literal

from fastapi import Depends, Header, HTTPException, Request
from fastapi.responses import HTMLResponse
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import ForeignKey, String, UniqueConstraint, delete, select, func
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Mapped, mapped_column

from .accounts import AliasClaim, alias_normalized
from .db import Base, Record, Audit, now, uid
from .notifications import optional_notice
from .catalogue import normalize
from .rate_limits import account_limit


class Membership(Base):
    __tablename__ = 'collaboration_members'
    __table_args__ = (UniqueConstraint('target_id', 'user_id'),)
    id: Mapped[str] = mapped_column(primary_key=True, default=uid)
    target_id: Mapped[str] = mapped_column(ForeignKey('records.id', ondelete='CASCADE'), index=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('accounts.id', ondelete='CASCADE'), index=True)
    role: Mapped[str] = mapped_column(String(20))


class Invitation(Base):
    __tablename__ = 'collaboration_invitations'
    id: Mapped[str] = mapped_column(primary_key=True, default=uid)
    digest: Mapped[str] = mapped_column(String(64), unique=True)
    issuer_id: Mapped[str] = mapped_column(ForeignKey('accounts.id', ondelete='CASCADE'), index=True)
    target_id: Mapped[str] = mapped_column(ForeignKey('records.id', ondelete='CASCADE'), index=True)
    recipient_id: Mapped[str | None] = mapped_column(ForeignKey('accounts.id', ondelete='CASCADE'), nullable=True)
    role: Mapped[str] = mapped_column(String(20))
    expires_at: Mapped[str | None] = mapped_column(nullable=True)
    remaining: Mapped[int]
    revoked: Mapped[bool] = mapped_column(default=False)
    revision: Mapped[int] = mapped_column(default=1)
    __mapper_args__ = {'version_id_col': revision}


class Relationship(Base):
    __tablename__ = 'user_relationships'
    __table_args__ = (UniqueConstraint('source_id', 'target_id', 'kind'),)
    id: Mapped[str] = mapped_column(primary_key=True, default=uid)
    source_id: Mapped[str] = mapped_column(ForeignKey('accounts.id', ondelete='CASCADE'), index=True)
    target_id: Mapped[str] = mapped_column(ForeignKey('accounts.id', ondelete='CASCADE'), index=True)
    kind: Mapped[str] = mapped_column(String(20))


class Input(BaseModel):
    model_config = ConfigDict(extra='forbid')


class InviteInput(Input):
    role: Literal['reader', 'editor', 'member', 'collaborator', 'admin'] = 'reader'
    days: int | None = Field(default=7, ge=1, le=30)
    uses: int = Field(default=1, ge=1, le=100)
    recipientId: str | None = Field(default=None, max_length=128)


class RedeemInput(Input):
    token: str = Field(min_length=32, max_length=128)


class GroupInput(Input):
    name: str = Field(min_length=1, max_length=120)
    description: str = Field(default='', max_length=1000)
    topic: str = Field(default='', max_length=120)
    type: Literal['general', 'university', 'exam'] = 'general'
    icon: Literal['book', 'balance', 'school'] = 'book'


class RoleInput(Input):
    role: Literal['reader', 'editor', 'member', 'collaborator', 'admin']


class ResourceInput(Input):
    deckId: str = Field(max_length=128)
    topic: str = Field(default='', max_length=120)


class ContactInput(Input):
    alias: str = Field(min_length=3, max_length=60)


class ReportInput(Input):
    targetId: str = Field(max_length=128)
    reason: str = Field(min_length=10, max_length=2000)
    severity: Literal['normal', 'high', 'critical'] = 'normal'
    appealOf: str | None = Field(default=None, max_length=128)


class ReportDecision(Input):
    status: Literal['triaged', 'resolved', 'dismissed']
    reason: str = Field(min_length=20, max_length=2000)


class RestrictionDecision(Input):
    suspended: bool
    reason: str = Field(min_length=20, max_length=2000)


class PublicationInput(Input):
    confirmation: Literal['PUBLICAR']
    subject: str = Field(default='', max_length=80)
    normId: str = Field(default='', max_length=128)


class DecisionInput(Input):
    action: Literal['allow', 'hide']
    reason: str = Field(min_length=20, max_length=2000)


class CopyUpdateInput(Input):
    confirmation: Literal['ACTUALIZAR']


def blocked(s, a, b):
    return bool(s.scalar(select(Relationship.id).where(Relationship.kind == 'blocked',
        ((Relationship.source_id == a) & (Relationship.target_id == b)) |
        ((Relationship.source_id == b) & (Relationship.target_id == a))).limit(1)))


def limited(s, user, action):
    restriction = s.get(Record, user.id + ':collaboration-status')
    if restriction and restriction.data.get('suspended') and action != 'collaboration_report':
        raise HTTPException(403, 'La colaboración de esta cuenta está suspendida. Conservas estudio, copias y acceso a tus datos.')
    account_limit(s,user.id,action)
    s.add(Audit(actor=user.id, entity=user.id, action=action, data={}))
    s.commit()


def profile(s, user_id):
    r = s.get(Record, user_id + ':account-profile')
    return r.data if r else {}


def public_person(s, user_id):
    p = profile(s, user_id)
    return {'id': user_id, 'displayName': p.get('displayName', '') or p.get('alias', '') or 'Compañero',
            'alias': p.get('alias', ''), 'avatar': p.get('avatar', 'initials')}


def target(s, target_id, kind=None, lock=False):
    row = s.scalar(select(Record).where(Record.id == target_id).with_for_update().execution_options(populate_existing=True)) if lock else s.get(Record, target_id)
    if not row or (kind and row.kind != kind):
        raise HTTPException(404, 'Material no disponible')
    return row


def group_role(s, group, user_id):
    if group.owner == user_id:
        return 'owner'
    if blocked(s, group.owner, user_id):
        return None
    member = s.scalar(select(Membership).where(Membership.target_id == group.id, Membership.user_id == user_id))
    return member.role if member else None


def deck_role(s, deck, user_id):
    if deck.owner == user_id:
        return 'owner'
    if blocked(s, deck.owner, user_id):
        return None
    direct = s.scalar(select(Membership).where(Membership.target_id == deck.id, Membership.user_id == user_id))
    if direct:
        return direct.role
    for resource in s.scalars(select(Record).where(Record.kind == 'group_resource', Record.data['deckId'].as_string() == deck.id)):
        group = s.get(Record, resource.data['groupId'])
        # Sharing is valid only while the owner still belongs to that group.
        if group and group_role(s, group, user_id) and group_role(s, group, deck.owner):
            return 'reader'
    publication = s.get(Record, deck.id + ':publication')
    if publication and publication.data.get('state') == 'allowed':
        return 'reader'
    return None


def require_role(s, row, user, allowed):
    role = group_role(s, row, user.id) if row.kind == 'study_group' else deck_role(s, row, user.id)
    if role not in allowed:
        raise HTTPException(404, 'Material no disponible o permiso retirado')
    return role


def register_collaboration(app, identity, db, pack, card_input, validate_card, editorial):
    @app.post('/v1/collaboration/contacts/link', status_code=201)
    def contact_link(user=Depends(identity), s=Depends(db)):
        if not profile(s, user.id).get('allowLinkInvitations'):
            raise HTTPException(409, 'Activa las invitaciones por enlace en Mi perfil')
        limited(s, user, 'contact_link')
        key = user.id + ':contact-link'
        if not s.get(Record, key):
            s.add(Record(id=key, kind='contact_link', owner=user.id, data={})); s.flush()
        raw = secrets.token_urlsafe(32)
        row = Invitation(digest=hashlib.sha256(raw.encode()).hexdigest(), issuer_id=user.id,
            target_id=key, role='contact', remaining=1,
            expires_at=(datetime.now(timezone.utc)+timedelta(days=7)).isoformat())
        s.add(row); s.commit()
        return {'id': row.id, 'path': '/invite#'+raw, 'expiresAt': row.expires_at}

    @app.get('/invite', response_class=HTMLResponse)
    def invite_landing():
        return HTMLResponse('<!doctype html><html lang="es"><meta charset="utf-8"><meta name="viewport" content="width=device-width"><title>Invitación · LexMemoria</title><body><main><h1>Invitación de estudio</h1><p>Abre LexMemoria → Perfil → Invitaciones y pega el enlace. Necesitas una cuenta para aceptar. No se concede acceso hasta confirmar la invitación.</p><p>Si no tienes la app, consulta el enlace de instalación que te facilitó quien te invitó.</p></main></body></html>',
            headers={'Content-Security-Policy': "default-src 'none'; frame-ancestors 'none'", 'Referrer-Policy': 'no-referrer'})

    @app.post('/v1/collaboration/{target_id}/invitations', status_code=201)
    def create_invitation(target_id: str, body: InviteInput, user=Depends(identity), s=Depends(db)):
        row = target(s, target_id)
        if row.kind not in ('deck', 'study_group'):
            raise HTTPException(404, 'Material no disponible')
        require_role(s, row, user, ['owner'] if row.kind == 'deck' else ['owner', 'admin'])
        valid = ('reader', 'editor') if row.kind == 'deck' else ('member', 'collaborator', 'admin')
        if body.role not in valid:
            raise HTTPException(422, 'Rol no válido para este material')
        if body.role == 'admin' and row.owner != user.id:
            raise HTTPException(403, 'Solo el propietario puede invitar administradores')
        limited(s, user, 'collaboration_invite')
        if body.recipientId:
            if blocked(s, user.id, body.recipientId):
                raise HTTPException(404, 'Destinatario no disponible')
            contacts = s.scalar(select(Relationship.id).where(Relationship.kind == 'contact',
                Relationship.source_id == user.id, Relationship.target_id == body.recipientId))
            if not contacts:
                raise HTTPException(404, 'Destinatario no disponible')
        raw = secrets.token_urlsafe(32)
        invite = Invitation(digest=hashlib.sha256(raw.encode()).hexdigest(), issuer_id=user.id,
            target_id=row.id, recipient_id=body.recipientId, role=body.role,
            expires_at=(datetime.now(timezone.utc)+timedelta(days=body.days)).isoformat() if body.days else None, remaining=body.uses)
        s.add(invite); s.flush()
        if body.recipientId:
            optional_notice(s, body.recipientId, 'collaboration', invite.id, row.id)
        s.commit()
        return {'id': invite.id, 'token': raw, 'expiresAt': invite.expires_at, 'remaining': invite.remaining,
                'path': '/invite#' + raw}

    @app.get('/v1/collaboration/invitations')
    def invitations(cursor:str='',limit:int=20,user=Depends(identity), s=Depends(db)):
        if not 1<=limit<=100:raise HTTPException(422,'Límite entre 1 y 100')
        rows = list(s.scalars(select(Invitation).where(((Invitation.issuer_id == user.id) | (Invitation.recipient_id == user.id)),
            Invitation.id>cursor).order_by(Invitation.id).limit(limit+1)))
        return {'items': [{'id': r.id, 'targetId': r.target_id, 'role': r.role, 'expiresAt': r.expires_at,
                          'remaining': r.remaining, 'revoked': r.revoked, 'sent': r.issuer_id == user.id} for r in rows[:limit]],
                'nextCursor':rows[limit-1].id if len(rows)>limit else None}

    @app.delete('/v1/collaboration/invitations/{invitation_id}')
    def cancel(invitation_id: str, user=Depends(identity), s=Depends(db)):
        row = s.get(Invitation, invitation_id)
        if not row or user.id not in (row.issuer_id, row.recipient_id):
            raise HTTPException(404, 'Invitación no disponible')
        row.revoked = True; s.commit()
        return {'revoked': True}

    @app.post('/v1/collaboration/invitations/accept')
    def accept(body: RedeemInput, user=Depends(identity), s=Depends(db)):
        limited(s, user, 'collaboration_accept')
        invite = s.scalar(select(Invitation).where(Invitation.digest == hashlib.sha256(body.token.encode()).hexdigest()))
        return finish_accept(invite, user, s)

    @app.post('/v1/collaboration/invitations/{invitation_id}/accept')
    def accept_direct(invitation_id: str, user=Depends(identity), s=Depends(db)):
        limited(s, user, 'collaboration_accept')
        invite = s.scalar(select(Invitation).where(Invitation.id == invitation_id,
                            Invitation.recipient_id == user.id))
        return finish_accept(invite, user, s)

    def finish_accept(invite, user, s):
        if not invite or invite.revoked or (invite.expires_at is not None and invite.expires_at <= now()) or invite.remaining < 1:
            raise HTTPException(404, 'Invitación no disponible')
        row = target(s, invite.target_id, lock=True)
        invite = s.scalar(select(Invitation).where(Invitation.id == invite.id).with_for_update().execution_options(populate_existing=True))
        if not invite or invite.revoked or (invite.expires_at is not None and invite.expires_at <= now()) or invite.remaining < 1:
            raise HTTPException(404, 'Invitación no disponible')
        if invite.recipient_id and invite.recipient_id != user.id:
            raise HTTPException(404, 'Invitación no disponible')
        if user.id == row.owner:
            raise HTTPException(409, 'Ya eres propietario')
        if blocked(s, user.id, row.owner) or blocked(s, user.id, invite.issuer_id):
            raise HTTPException(404, 'Invitación no disponible')
        if row.kind == 'study_group' and group_role(s, row, invite.issuer_id) not in ('owner', 'admin'):
            raise HTTPException(404, 'Invitación retirada')
        if row.kind == 'deck' and row.owner != invite.issuer_id:
            raise HTTPException(404, 'Invitación retirada')
        if not profile(s, user.id).get('allowLinkInvitations') and not invite.recipient_id:
            raise HTTPException(409, 'Activa las invitaciones por enlace en Mi perfil antes de aceptar')
        if row.kind == 'contact_link':
            if not profile(s, row.owner).get('allowLinkInvitations'):
                raise HTTPException(404, 'Invitación retirada')
            for source, destination in [(user.id, row.owner), (row.owner, user.id)]:
                if not s.scalar(select(Relationship.id).where(Relationship.source_id == source,
                        Relationship.target_id == destination, Relationship.kind == 'contact')):
                    s.add(Relationship(source_id=source, target_id=destination, kind='contact'))
            invite.remaining -= 1
            s.commit()
            return {'targetId': row.owner, 'role': 'contact'}
        old = s.scalar(select(Membership).where(Membership.target_id == row.id, Membership.user_id == user.id))
        if old:
            return {'targetId': row.id, 'role': old.role, 'alreadyMember': True}
        s.add(Membership(target_id=row.id, user_id=user.id, role=invite.role))
        invite.remaining -= 1
        try:
            s.commit()
        except IntegrityError:
            s.rollback(); raise HTTPException(409, 'Invitación aceptada simultáneamente; consulta tus materiales')
        return {'targetId': row.id, 'role': invite.role}

    @app.get('/v1/collaboration/decks')
    def shared_decks(cursor:str='',limit:int=20,user=Depends(identity),s=Depends(db)):
        if not 1<=limit<=100:raise HTTPException(422,'Límite entre 1 y 100')
        memberships=select(Membership.target_id).where(Membership.user_id==user.id)
        groups=select(Record.id).where(Record.kind=='study_group', (Record.owner==user.id)|Record.id.in_(memberships))
        resources=select(Record.data['deckId'].as_string()).where(Record.kind=='group_resource',Record.data['groupId'].as_string().in_(groups))
        rows=list(s.scalars(select(Record).where(Record.kind=='deck',Record.owner!=user.id,
            (Record.id.in_(memberships))|(Record.id.in_(resources)),Record.id>cursor).order_by(Record.id).limit(limit+1)))
        items=[]
        for row in rows[:limit]:
            role=deck_role(s,row,user.id)
            if role:items.append({'id':row.id,'title':row.data['title'],'role':role,'author':public_person(s,row.owner)})
        return {'items':items,'nextCursor':rows[limit-1].id if len(rows)>limit else None}

    @app.get('/v1/collaboration/decks/{deck_id}')
    def shared_content(deck_id: str, cursor: str = '', limit: int = 20, user=Depends(identity), s=Depends(db)):
        deck = target(s, deck_id, 'deck'); role = require_role(s, deck, user, ['owner', 'editor', 'reader'])
        if not 1 <= limit <= 100:
            raise HTTPException(422, 'Límite entre 1 y 100')
        rows = list(s.scalars(select(Record).where(Record.kind == 'card', Record.data['deckId'].as_string() == deck.id,
                         Record.id > cursor).order_by(Record.id).limit(limit+1)))
        # Only shared content: never owner, review events, favorites or states.
        allowed = ('clientId', 'front', 'back', 'explanation', 'type', 'options', 'correct', 'citations', 'editorialState', 'citationState')
        return {'id': deck.id, 'title': deck.data['title'], 'role': role,
                'canCheckUpdates': bool(deck.owner == user.id and deck.data.get('sourceDeckId')),
                'items': [{**{k: r.data[k] for k in allowed if k in r.data}, 'id': r.id, 'revision': r.revision} for r in rows[:limit]],
                'nextCursor': rows[limit-1].id if len(rows)>limit else None}

    @app.put('/v1/collaboration/cards/{card_id}')
    def shared_edit(card_id: str, body: card_input, if_match: str = Header(), user=Depends(identity), s=Depends(db)):
        limited(s, user, 'collaboration_edit')
        card = target(s, card_id, 'card'); deck = target(s, card.data['deckId'], 'deck', lock=True)
        s.refresh(card)
        require_role(s, deck, user, ['owner', 'editor'])
        if body.deckId != deck.id or body.clientId != card.data.get('clientId'):
            raise HTTPException(422, 'No puedes cambiar la identidad del material compartido')
        if if_match.strip('"') != str(card.revision):
            raise HTTPException(409, 'Edición concurrente; conserva tu borrador')
        citation_state = validate_card(s, body)
        if all(card.data.get(k) == v for k,v in body.model_dump().items()):
            return pack(card)
        s.add(Record(kind='card_revision', owner=card.owner, data={'cardId': card.id,
            'cardRevision': card.revision, 'content': card.data, 'archivedAt': now()}))
        card.data = {**body.model_dump(), 'citationState': citation_state, 'editorialState': 'user',
                     'authorId': user.id, 'blocked': bool(card.data.get('blocked')), 'updatedAt': now(),
                     **({k: card.data[k] for k in ('sourceCardId', 'sourceCardRevision') if k in card.data}),
                     **({'sourceDetached': True} if card.data.get('sourceCardId') else {})}
        publication = s.get(Record, deck.id + ':publication')
        if publication:
            publication.data = {**publication.data, 'state': 'pending'}
        s.add(Audit(actor=user.id, entity=card.id, action='shared_edit', data={'previousRevision': card.revision}))
        s.commit(); return pack(card)

    @app.post('/v1/collaboration/decks/{deck_id}/copy', status_code=201)
    def copy_deck(deck_id: str, idempotency_key: str | None = Header(default=None), user=Depends(identity), s=Depends(db)):
        original = target(s, deck_id, 'deck'); require_role(s, original, user, ['owner','editor','reader'])
        limited(s, user, 'collaboration_copy')
        from .db import Account
        s.scalar(select(Account).where(Account.id == user.id).with_for_update())
        copy_id = user.id + ':copy:' + hashlib.sha256(idempotency_key.encode()).hexdigest()[:40] if idempotency_key else uid()
        if idempotency_key and not 8 <= len(idempotency_key) <= 128:
            raise HTTPException(422, 'Identificador de copia no válido')
        existing = s.get(Record, copy_id)
        if existing:
            if existing.owner != user.id or existing.kind != 'deck' or existing.data.get('sourceDeckId') != original.id:
                raise HTTPException(409, 'Identificador de copia reutilizado')
            count = s.scalar(select(func.count()).select_from(Record).where(Record.kind=='card',Record.data['deckId'].as_string()==existing.id))
            return {'id': existing.id, 'cards': count, 'independent': True}
        rows = list(s.scalars(select(Record).where(Record.kind == 'card', Record.data['deckId'].as_string() == original.id)))
        if len(rows)>2000:
            raise HTTPException(422, 'El mazo supera el límite de copia de este lote (2000 tarjetas)')
        names = set(s.scalars(select(Record.data['title'].as_string()).where(Record.kind=='deck',Record.owner==user.id)))
        number = 1
        base_title = original.data['title'][:130].rstrip()
        while f"{base_title} · copia {number}" in names:number += 1
        deck = Record(id=copy_id, kind='deck', owner=user.id, data={'title': base_title+f' · copia {number}', 'visibility':'private',
            'sourceDeckId':original.id, 'attribution':public_person(s, original.owner), 'copiedAt':now()})
        s.add(deck); s.flush()
        for row in rows:
            data = {**row.data, 'deckId':deck.id, 'clientId':uid(), 'editorialState':'user', 'authorId':user.id,
                    'sourceCardId':row.id, 'sourceCardRevision':row.revision, 'sourceDetached':False}
            s.add(Record(kind='card',owner=user.id,data=data))
        s.commit(); return {'id':deck.id,'cards':len(rows),'independent':True}

    def copy_changes(s, copy_id, user):
        deck=target(s,copy_id,'deck',lock=True)
        if deck.owner!=user.id or not deck.data.get('sourceDeckId'):raise HTTPException(404,'Copia no disponible')
        original=target(s,deck.data['sourceDeckId'],'deck',lock=True)
        require_role(s,original,user,['owner','editor','reader'])
        sources={r.id:r for r in s.scalars(select(Record).where(Record.kind=='card',Record.data['deckId'].as_string()==original.id))}
        copies={r.data.get('sourceCardId'):r for r in s.scalars(select(Record).where(Record.kind=='card',Record.data['deckId'].as_string()==deck.id)) if r.data.get('sourceCardId')}
        changed=[(source,copies.get(source.id)) for source in sources.values() if source.id not in copies or
                 (not copies[source.id].data.get('sourceDetached') and copies[source.id].data.get('sourceCardRevision')!=source.revision)]
        return deck,changed

    @app.get('/v1/collaboration/copies/{copy_id}/updates')
    def preview_copy_updates(copy_id:str,user=Depends(identity),s=Depends(db)):
        deck,changed=copy_changes(s,copy_id,user)
        return {'revision':deck.revision,'new':sum(copy is None for _,copy in changed),
                'changed':sum(copy is not None for _,copy in changed),
                'note':'Las tarjetas editadas personalmente no se sustituyen. Se conserva el historial de las demás.'}

    @app.post('/v1/collaboration/copies/{copy_id}/updates')
    def apply_copy_updates(copy_id:str,body:CopyUpdateInput,if_match:str=Header(),user=Depends(identity),s=Depends(db)):
        deck,changed=copy_changes(s,copy_id,user)
        if if_match.strip('"')!=str(deck.revision):raise HTTPException(409,'La copia cambió; consulta de nuevo')
        if len(changed)>2000:raise HTTPException(422,'Demasiados cambios para este lote')
        for source,copy in changed:
            data={**source.data,'deckId':deck.id,'clientId':copy.data['clientId'] if copy else uid(),
                'sourceCardId':source.id,'sourceCardRevision':source.revision,'sourceDetached':False,'editorialState':'user','authorId':user.id}
            if copy:
                s.add(Record(kind='card_revision',owner=user.id,data={'cardId':copy.id,'cardRevision':copy.revision,
                    'content':copy.data,'archivedAt':now()}));copy.data=data
            else:s.add(Record(kind='card',owner=user.id,data=data))
        if changed:deck.data={**deck.data,'lastSourceUpdateAt':now()}
        s.commit();return {'updated':len(changed),'revision':deck.revision,'progressPreserved':True}

    @app.post('/v1/collaboration/groups', status_code=201)
    def create_group(body: GroupInput, user=Depends(identity), s=Depends(db)):
        limited(s,user,'collaboration_group')
        row=Record(kind='study_group',owner=user.id,data={**body.model_dump(),'privacy':'private'})
        s.add(row);s.commit();return pack(row)

    @app.get('/v1/collaboration/groups')
    def groups(cursor:str='',limit:int=20,user=Depends(identity),s=Depends(db)):
        if not 1<=limit<=100:raise HTTPException(422,'Límite entre 1 y 100')
        member_ids=select(Membership.target_id).where(Membership.user_id==user.id)
        rows=list(s.scalars(select(Record).where(Record.kind=='study_group',Record.id>cursor,
            (Record.owner==user.id)|Record.id.in_(member_ids)).order_by(Record.id).limit(limit+1)))
        return {'items':[{**pack(r),'role':role} for r in rows[:limit] if (role:=group_role(s,r,user.id))],
                'nextCursor':rows[limit-1].id if len(rows)>limit else None}

    @app.get('/v1/collaboration/groups/{group_id}')
    def group_details(group_id:str,membersCursor:str='',resourcesCursor:str='',limit:int=20,user=Depends(identity),s=Depends(db)):
        if not 1<=limit<=100:raise HTTPException(422,'Límite entre 1 y 100')
        group=target(s,group_id,'study_group');role=require_role(s,group,user,['owner','admin','collaborator','member'])
        member_rows=list(s.scalars(select(Membership).where(Membership.target_id==group.id,
            Membership.user_id>membersCursor).order_by(Membership.user_id).limit(limit+1)))
        members=([{**public_person(s,group.owner),'role':'owner'}] if not membersCursor else [])+[
            {**public_person(s,m.user_id),'role':m.role} for m in member_rows[:limit]]
        resource_rows=list(s.scalars(select(Record).where(Record.kind=='group_resource',
            Record.data['groupId'].as_string()==group.id,Record.id>resourcesCursor).order_by(Record.id).limit(limit+1)))
        resources=[]
        for r in resource_rows[:limit]:
            deck=s.get(Record,r.data['deckId'])
            if deck and deck_role(s,deck,user.id):resources.append({**pack(r),'title':deck.data['title']})
        return {**pack(group),'role':role,'members':members,'resources':resources,
                'membersNextCursor':member_rows[limit-1].user_id if len(member_rows)>limit else None,
                'resourcesNextCursor':resource_rows[limit-1].id if len(resource_rows)>limit else None}

    @app.put('/v1/collaboration/groups/{group_id}')
    def update_group(group_id:str,body:GroupInput,if_match:str=Header(),user=Depends(identity),s=Depends(db)):
        group=target(s,group_id,'study_group',lock=True);require_role(s,group,user,['owner','admin'])
        if if_match.strip('"') != str(group.revision):raise HTTPException(409,'El grupo cambió; vuelve a consultarlo')
        group.data={**body.model_dump(),'privacy':'private'};s.commit();return pack(group)

    @app.get('/v1/collaboration/decks/{deck_id}/members')
    def deck_members(deck_id:str,user=Depends(identity),s=Depends(db)):
        deck=target(s,deck_id,'deck');require_role(s,deck,user,['owner'])
        return {'items':[{**public_person(s,m.user_id),'role':m.role} for m in s.scalars(
            select(Membership).where(Membership.target_id==deck.id))]}

    @app.delete('/v1/collaboration/decks/{deck_id}/publication')
    def withdraw_publication(deck_id:str,user=Depends(identity),s=Depends(db)):
        deck=target(s,deck_id,'deck');require_role(s,deck,user,['owner'])
        row=s.get(Record,deck.id+':publication')
        if row:row.data={**row.data,'state':'withdrawn'}
        s.commit();return {'withdrawn':True}

    @app.post('/v1/collaboration/groups/{group_id}/resources',status_code=201)
    def add_resource(group_id:str,body:ResourceInput,user=Depends(identity),s=Depends(db)):
        group=target(s,group_id,'study_group',lock=True);require_role(s,group,user,['owner','admin','collaborator'])
        deck=target(s,body.deckId,'deck')
        if deck.owner!=user.id:raise HTTPException(403,'Solo puedes compartir tu propio material')
        key=group.id+':'+hashlib.sha256(deck.id.encode()).hexdigest()[:32]
        row=s.get(Record,key)
        if not row:
            row=Record(id=key,kind='group_resource',owner=user.id,data={'groupId':group.id,**body.model_dump()});s.add(row)
        s.commit();return pack(row)

    @app.delete('/v1/collaboration/groups/{group_id}/resources/{resource_id}')
    def remove_resource(group_id:str,resource_id:str,user=Depends(identity),s=Depends(db)):
        group=target(s,group_id,'study_group');role=require_role(s,group,user,['owner','admin','collaborator','member'])
        row=target(s,resource_id,'group_resource')
        if row.data['groupId']!=group.id or (row.owner!=user.id and role not in ('owner','admin')):
            raise HTTPException(404,'Material no disponible')
        s.delete(row);s.commit();return {'removed':True}

    @app.put('/v1/collaboration/{target_id}/members/{user_id}')
    def change_role(target_id:str,user_id:str,body:RoleInput,user=Depends(identity),s=Depends(db)):
        row=target(s,target_id,lock=True)
        if row.kind not in ('deck','study_group') or row.owner!=user.id:raise HTTPException(404,'Material no disponible')
        valid=('reader','editor') if row.kind=='deck' else ('member','collaborator','admin')
        if body.role not in valid:raise HTTPException(422,'Rol no válido')
        member=s.scalar(select(Membership).where(Membership.target_id==row.id,Membership.user_id==user_id).with_for_update())
        if not member:raise HTTPException(404,'Miembro no disponible')
        member.role=body.role
        optional_notice(s,user_id,'collaboration',uid(),row.id)
        s.commit();return {'role':body.role}

    @app.delete('/v1/collaboration/{target_id}/members/{user_id}')
    def remove_member(target_id:str,user_id:str,user=Depends(identity),s=Depends(db)):
        row=target(s,target_id,lock=True)
        if row.kind not in ('deck','study_group'):raise HTTPException(404,'Material no disponible')
        role=group_role(s,row,user.id) if row.kind=='study_group' else deck_role(s,row,user.id)
        member=s.scalar(select(Membership).where(Membership.target_id==row.id,Membership.user_id==user_id).with_for_update())
        if user_id==row.owner:raise HTTPException(409,'El propietario debe eliminar o transferir el espacio antes de salir')
        if not member or (user_id!=user.id and role not in ('owner','admin')):raise HTTPException(404,'Miembro no disponible')
        if role=='admin' and member.role=='admin' and user.id!=user_id:raise HTTPException(403,'Solo el propietario administra otros administradores')
        s.delete(member)
        if row.kind == 'study_group':
            s.execute(delete(Record).where(Record.kind=='group_resource',Record.owner==user_id,
                                          Record.data['groupId'].as_string()==row.id))
        optional_notice(s,user_id,'collaboration',uid(),row.id)
        # Stale invitations issued before a removal must not silently restore access.
        for invitation in s.scalars(select(Invitation).where(Invitation.target_id==row.id)):
            invitation.revoked = True
        s.commit();return {'removed':True}

    @app.delete('/v1/collaboration/groups/{group_id}')
    def delete_group(group_id:str,user=Depends(identity),s=Depends(db)):
        group=target(s,group_id,'study_group')
        if group.owner!=user.id:raise HTTPException(404,'Grupo no disponible')
        s.execute(delete(Record).where(Record.kind=='group_resource',Record.data['groupId'].as_string()==group.id))
        s.delete(group);s.commit();return {'deleted':True,'personalCopiesPreserved':True}

    @app.post('/v1/collaboration/contacts/requests',status_code=201)
    def contact_request(body:ContactInput,user=Depends(identity),s=Depends(db)):
        limited(s,user,'contact_request')
        try:alias=alias_normalized(body.alias)
        except ValueError:raise HTTPException(404,'Compañero no disponible')
        claim=s.scalar(select(AliasClaim).where(AliasClaim.alias==alias))
        if not claim or claim.user_id==user.id or not profile(s,claim.user_id).get('allowAliasInvitations') or blocked(s,user.id,claim.user_id):
            raise HTTPException(404,'Compañero no disponible')
        existing=s.scalar(select(Relationship).where(Relationship.source_id==user.id,Relationship.target_id==claim.user_id,
                                                    Relationship.kind.in_(['request','contact'])))
        if existing:return {'id':existing.id,'status':existing.kind}
        row=Relationship(source_id=user.id,target_id=claim.user_id,kind='request');s.add(row);s.flush()
        optional_notice(s,claim.user_id,'collaboration',row.id,user.id)
        try:s.commit()
        except IntegrityError:s.rollback();raise HTTPException(409,'Solicitud simultánea; consulta compañeros')
        return {'id':row.id,'status':'request'}

    @app.get('/v1/collaboration/contacts')
    def contacts(cursor:str='',limit:int=20,user=Depends(identity),s=Depends(db)):
        if not 1<=limit<=100:raise HTTPException(422,'Límite entre 1 y 100')
        rows=list(s.scalars(select(Relationship).where((Relationship.source_id==user.id)|((Relationship.target_id==user.id)&(Relationship.kind=='request')),
            Relationship.id>cursor).order_by(Relationship.id).limit(limit+1)))
        result=[]
        for row in rows[:limit]:
            other=row.target_id if row.source_id==user.id else row.source_id
            if row.kind=='blocked':
                if row.source_id==user.id:result.append({'id':row.id,'status':'blocked','person':{'id':other}})
            elif not blocked(s,user.id,other) and (row.kind=='request' or row.source_id==user.id):
                result.append({'id':row.id,'status':row.kind,'incoming':row.target_id==user.id,'person':public_person(s,other)})
        return {'items':result,'nextCursor':rows[limit-1].id if len(rows)>limit else None}

    @app.post('/v1/collaboration/contacts/{request_id}/accept')
    def accept_contact(request_id:str,user=Depends(identity),s=Depends(db)):
        row=s.scalar(select(Relationship).where(Relationship.id==request_id).with_for_update())
        if not row or row.kind!='request' or row.target_id!=user.id or blocked(s,row.source_id,user.id):raise HTTPException(404,'Solicitud no disponible')
        a,b=row.source_id,row.target_id
        s.execute(delete(Relationship).where(Relationship.kind=='request',((Relationship.source_id==a)&(Relationship.target_id==b))|((Relationship.source_id==b)&(Relationship.target_id==a))))
        for source,destination in [(a,b),(b,a)]:
            if not s.scalar(select(Relationship.id).where(Relationship.source_id==source,Relationship.target_id==destination,Relationship.kind=='contact')):
                s.add(Relationship(source_id=source,target_id=destination,kind='contact'))
        s.commit();return {'accepted':True}

    @app.delete('/v1/collaboration/contacts/{relationship_id}')
    def remove_contact(relationship_id:str,user=Depends(identity),s=Depends(db)):
        row=s.get(Relationship,relationship_id)
        if not row or user.id not in (row.source_id,row.target_id):raise HTTPException(404,'Contacto no disponible')
        if row.kind=='blocked':
            if row.source_id!=user.id:raise HTTPException(404,'Contacto no disponible')
            s.delete(row)
        else:
            a,b=row.source_id,row.target_id
            s.execute(delete(Relationship).where(Relationship.kind.in_(['contact','request']),((Relationship.source_id==a)&(Relationship.target_id==b))|((Relationship.source_id==b)&(Relationship.target_id==a))))
        s.commit();return {'removed':True}

    @app.post('/v1/collaboration/blocks/{user_id}')
    def block_user(user_id:str,user=Depends(identity),s=Depends(db)):
        # No user directory or private fields are exposed. Input IDs are random
        # and authenticated block requests are rate-limited separately.
        from .db import Account
        account_limit(s,user.id,'privacy_block',limit=10)
        if user_id==user.id or not s.get(Account,user_id):raise HTTPException(404,'Usuario no disponible')
        old=s.scalar(select(Relationship).where(Relationship.source_id==user.id,Relationship.target_id==user_id,Relationship.kind=='blocked'))
        if not old:s.add(Relationship(source_id=user.id,target_id=user_id,kind='blocked'))
        s.execute(delete(Relationship).where(Relationship.kind.in_(['contact','request']),((Relationship.source_id==user.id)&(Relationship.target_id==user_id))|((Relationship.source_id==user_id)&(Relationship.target_id==user.id))))
        owned = list(s.scalars(select(Record).where(Record.kind.in_(['deck','study_group']),Record.owner.in_([user.id,user_id]))))
        for resource in owned:
            other = user_id if resource.owner == user.id else user.id
            member = s.scalar(select(Membership).where(Membership.target_id==resource.id,Membership.user_id==other))
            if not member:continue
            s.delete(member)
            for invitation in s.scalars(select(Invitation).where(Invitation.target_id==resource.id)):
                invitation.revoked=True
            if resource.kind=='study_group':
                s.execute(delete(Record).where(Record.kind=='group_resource',Record.owner==other,Record.data['groupId'].as_string()==resource.id))
        s.add(Audit(actor=user.id,entity=user_id,action='user_block',data={}))
        s.commit();return {'blocked':True}

    @app.post('/v1/collaboration/reports',status_code=201)
    def report(body:ReportInput,user=Depends(identity),s=Depends(db)):
        limited(s,user,'collaboration_report')
        if body.appealOf:
            previous=s.get(Record,body.appealOf)
            if not previous or previous.kind!='collaboration_report' or previous.owner!=user.id or previous.data.get('targetId')!=body.targetId:
                raise HTTPException(404,'Incidencia no disponible')
        row=Record(kind='collaboration_report',owner=user.id,data={**body.model_dump(),'status':'pending','at':now()})
        s.add(row);s.commit();return {'id':row.id,'status':'pending'}

    @app.get('/v1/collaboration/reports')
    def own_reports(cursor:str='',limit:int=20,user=Depends(identity),s=Depends(db)):
        if not 1<=limit<=100:raise HTTPException(422,'Límite entre 1 y 100')
        rows=list(s.scalars(select(Record).where(Record.kind=='collaboration_report',Record.owner==user.id,Record.id>cursor).order_by(Record.id).limit(limit+1)))
        return {'items':[pack(r) for r in rows[:limit]],'nextCursor':rows[limit-1].id if len(rows)>limit else None}

    @app.post('/v1/collaboration/decks/{deck_id}/publication')
    def request_publication(deck_id:str,body:PublicationInput,user=Depends(identity),s=Depends(db)):
        limited(s,user,'collaboration_publish')
        deck=target(s,deck_id,'deck')
        if deck.owner!=user.id:raise HTTPException(404,'Mazo no disponible')
        key=deck.id+':publication';row=s.get(Record,key)
        data={**body.model_dump(),'deckId':deck.id,'state':'pending','requestedAt':now()}
        if row:row.data=data
        else:row=Record(id=key,kind='deck_publication',owner=user.id,data=data);s.add(row)
        s.commit();return {'state':'pending','message':'Pendiente de moderación; no es revisión jurídica'}

    @app.get('/v1/collaboration/catalogue')
    def catalogue(q:str='',subject:str='',normId:str='',cursor:str='',limit:int=20,s=Depends(db)):
        if not 1<=limit<=100 or len(q)>120:raise HTTPException(422,'Consulta no válida')
        rows=list(s.scalars(select(Record).where(Record.kind=='deck_publication',Record.id>cursor,
            Record.data['state'].as_string()=='allowed').order_by(Record.id)))
        result=[]
        for row in rows:
            deck=s.get(Record,row.data['deckId'])
            if not deck or (q and normalize(q) not in normalize(deck.data['title'])):continue
            if subject and normalize(row.data.get('subject',''))!=normalize(subject):continue
            if normId and row.data.get('normId')!=normId:continue
            count=s.scalar(select(func.count()).select_from(Record).where(Record.kind=='card',Record.data['deckId'].as_string()==deck.id))
            result.append({'id':deck.id,'cursor':row.id,'title':deck.data['title'],'cards':count,
                'author':public_person(s,deck.owner),'updatedAt':row.data.get('requestedAt'),
                'contentStatus':'user_content_not_legally_reviewed'})
            if len(result)>limit:break
        return {'items':result[:limit],'nextCursor':result[limit-1]['cursor'] if len(result)>limit else None}

    @app.get('/v1/admin/collaboration')
    def moderation(request:Request,user=Depends(identity),s=Depends(db)):
        editorial(user,request,s)
        return {'items':[{**pack(r),'kind':r.kind} for r in s.scalars(select(Record).where(Record.kind.in_(['collaboration_report','deck_publication'])))]}

    @app.post('/v1/admin/collaboration/{deck_id}/decision')
    def moderate(deck_id:str,body:DecisionInput,request:Request,user=Depends(identity),s=Depends(db)):
        editorial(user,request,s);deck=target(s,deck_id,'deck');publication=target(s,deck.id+':publication','deck_publication')
        if deck.owner==user.id:raise HTTPException(403,'No puedes moderar tu propia publicación')
        publication.data={**publication.data,'state':'allowed' if body.action=='allow' else 'hidden','moderatedAt':now()}
        s.add(Audit(actor=user.id,entity=deck.id,action='sharing_moderation',data=body.model_dump()))
        s.commit();return {'state':publication.data['state'],'legalReview':False}

    @app.post('/v1/admin/collaboration/reports/{report_id}/decision')
    def decide_report(report_id:str,body:ReportDecision,request:Request,user=Depends(identity),s=Depends(db)):
        editorial(user,request,s);row=target(s,report_id,'collaboration_report',lock=True)
        row.data={**row.data,'status':body.status,'resolution':body.reason,'resolvedAt':now()}
        s.add(Audit(actor=user.id,entity=row.id,action='report_decision',data=body.model_dump()))
        s.commit();return pack(row)

    @app.get('/v1/admin/collaboration/decks/{deck_id}')
    def moderation_preview(deck_id:str,request:Request,cursor:str='',limit:int=20,user=Depends(identity),s=Depends(db)):
        editorial(user,request,s);deck=target(s,deck_id,'deck')
        if not 1<=limit<=100:raise HTTPException(422,'Límite entre 1 y 100')
        rows=list(s.scalars(select(Record).where(Record.kind=='card',Record.data['deckId'].as_string()==deck.id,
            Record.id>cursor).order_by(Record.id).limit(limit+1)))
        return {'title':deck.data['title'],'items':[pack(r) for r in rows[:limit]],'nextCursor':rows[limit-1].id if len(rows)>limit else None}

    @app.post('/v1/admin/collaboration/accounts/{account_id}/restriction')
    def restrict(account_id:str,body:RestrictionDecision,request:Request,user=Depends(identity),s=Depends(db)):
        from .db import Account
        editorial(user,request,s)
        if user.role!='admin' or account_id==user.id:raise HTTPException(403,'Administrador independiente requerido')
        person=s.get(Account,account_id)
        if not person or person.role!='user':raise HTTPException(404,'Cuenta no disponible')
        key=account_id+':collaboration-status';row=s.get(Record,key)
        data={**body.model_dump(),'at':now()}
        if row:row.data=data
        else:s.add(Record(id=key,kind='collaboration_restriction',owner=account_id,data=data))
        s.add(Audit(actor=user.id,entity=account_id,action='collaboration_restriction',data=body.model_dump()))
        s.commit();return {'suspended':body.suspended,'privateStudyPreserved':True}
