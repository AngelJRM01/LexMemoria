"""Opt-in in-app inbox. External push is deliberately a separate transport."""
import hashlib
from datetime import datetime, timezone, timedelta
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from .db import Record, now


def inbox(session, user_id):
    subscription = session.get(Record, 'follows:' + user_id)
    if not subscription or not subscription.data.get('enabled'):
        return
    interval = {'immediate': 0, 'daily': 1, 'weekly': 7}[subscription.data.get('frequency', 'immediate')]
    last = subscription.data.get('lastDispatchAt')
    if last and datetime.now(timezone.utc) < datetime.fromisoformat(last) + timedelta(days=interval):
        return
    created = False
    followed = set(subscription.data.get('normIds', []))
    events = session.scalars(select(Record).where(Record.kind == 'legal_event').order_by(Record.created_at, Record.id))
    for event in events:
        if event.data.get('normId', event.data.get('officialId')) not in followed:
            continue
        if event.created_at < subscription.data.get('since', ''):
            continue
        key = 'inbox:' + hashlib.sha256((user_id + ':' + event.id).encode()).hexdigest()
        if session.get(Record, key):
            continue
        # No private study details are copied into delivery content.
        try:
            with session.begin_nested():
                session.add(Record(id=key, kind='notification_delivery', owner=user_id, data={
                'eventId': event.id, 'normId': event.data.get('normId', event.data.get('officialId')),
                'channel': 'in_app', 'status': 'available', 'read': False,
                'createdAt': now(), 'deepLink': '/updates/' + event.id,
                }))
            created = True
        except IntegrityError:
            pass
    if created:
        subscription.data = {**subscription.data, 'lastDispatchAt': now()}
    try:
        session.commit()
    except IntegrityError:
        session.rollback()
