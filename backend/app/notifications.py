"""Opt-in in-app inbox. External push is deliberately a separate transport."""
import hashlib
from datetime import datetime, timezone, timedelta
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from .db import Record, now


def inbox(session, user_id):
    preferences = session.get(Record, user_id + ':account-profile')
    if preferences and not preferences.data.get('legalNotifications', False):
        return
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
                'channel': 'in_app', 'status': 'queued' if preferences else 'available', 'read': False,
                **({'category': 'legal'} if preferences else {}),
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


def optional_notice(session, user_id, category, event_id, entity_id):
    """Opt-in generic in-app notice, never a push or a legal conclusion."""
    profile = session.get(Record, user_id + ':account-profile')
    key_name = {'study': 'studyNotifications', 'legal': 'legalNotifications',
                'collaboration': 'collaborationNotifications'}[category]
    if not profile or not profile.data.get(key_name, False):
        return
    key = 'notice:' + hashlib.sha256((user_id + ':' + category + ':' + event_id).encode()).hexdigest()
    if session.get(Record, key):
        return
    session.add(Record(id=key, kind='notification_delivery', owner=user_id, data={
        'eventId': event_id, 'entityId': entity_id, 'category': category,
        'channel': 'in_app', 'status': 'queued', 'read': False, 'createdAt': now(),
        'message': {'study': 'Revisa tu planificación de estudio.', 'legal': 'Hay información nueva sobre una norma seguida.',
                    'collaboration': 'Tienes una invitación o un cambio de permisos.'}[category]}))


def release_optional_notices(session, user_id):
    from zoneinfo import ZoneInfo
    profile = session.get(Record, user_id + ':account-profile')
    if not profile:
        return
    settings = profile.data
    local = datetime.now(ZoneInfo('Europe/Madrid')).strftime('%H:%M')
    start, end = settings.get('quietStart', '22:00'), settings.get('quietEnd', '08:00')
    quiet = start <= local < end if start < end else (local >= start or local < end) if start != end else False
    if quiet:
        return
    cutoff = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat()
    available = list(session.scalars(select(Record).where(Record.kind == 'notification_delivery', Record.owner == user_id)))
    recent = sum(1 for row in available if row.data.get('category') and row.data.get('releasedAt', '') >= cutoff)
    for row in sorted(available, key=lambda r: r.created_at):
        if recent >= settings.get('noticeDailyLimit', 3):
            break
        category = row.data.get('category')
        preference = {'study': 'studyNotifications', 'legal': 'legalNotifications', 'collaboration': 'collaborationNotifications'}.get(category)
        if row.data.get('status') == 'queued' and preference and settings.get(preference):
            row.data = {**row.data, 'status': 'available', 'releasedAt': now()}; recent += 1
    session.commit()


def study_notices(session, user_id):
    """Generate daily in-app reminders only on an explicit inbox consultation."""
    from zoneinfo import ZoneInfo
    settings = session.get(Record, user_id + ':account-profile')
    workspace = session.get(Record, user_id + ':workspace')
    if not settings or not settings.data.get('studyNotifications') or not workspace:
        return
    profile = workspace.data.get('profile', {})
    local = datetime.now(ZoneInfo('Europe/Madrid'))
    day = local.date().isoformat()
    if local.isoweekday() in profile.get('restDays', []):
        return
    if any(v.get('start', '') <= day <= v.get('end', '') for v in profile.get('vacations', [])):
        return
    has_cards = session.scalar(select(Record.id).where(Record.kind == 'card', Record.owner == user_id).limit(1))
    try:goal = max(1, min(200, int(profile.get('dailyGoal', 20))))
    except (ValueError,TypeError,OverflowError):goal = 20
    completed = 0
    cutoff = (datetime.now(timezone.utc) - timedelta(days=2)).isoformat()
    for review in session.scalars(select(Record).where(Record.kind=='review_event',
            Record.owner==user_id, Record.created_at>=cutoff)):
        try:
            reviewed = datetime.fromisoformat(review.data['occurredAt'].replace('Z','+00:00'))
            if reviewed.astimezone(local.tzinfo).date()==local.date():completed += 1
        except (KeyError,TypeError,ValueError):
            continue
    if has_cards and completed < goal:
        optional_notice(session, user_id, 'study', 'study:' + day, user_id + ':workspace')
    exam = profile.get('examDate')
    try:
        days = (datetime.fromisoformat(exam.replace('Z', '+00:00')).date() - local.date()).days if exam else -1
    except (ValueError, TypeError):
        days = -1
    if 0 <= days <= 7:
        optional_notice(session, user_id, 'study', 'exam:' + day, user_id + ':workspace')
