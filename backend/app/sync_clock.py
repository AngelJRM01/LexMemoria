"""Cheap per-account educational change tokens and complete card history.

Hooks also run in ingestion/CLI processes. Neither a change token nor a shared
membership grants access: every content endpoint still checks ownership/ACL.
"""
import hashlib
from sqlalchemy import BigInteger,ForeignKey,event,select,inspect
from sqlalchemy.orm import Mapped,mapped_column
from .db import Base,Record,Account,now

PROGRESS_KINDS={'deck','card','card_revision','review_event','review_state'}

class AccountSyncClock(Base):
    __tablename__='account_sync_clocks'
    user_id: Mapped[str]=mapped_column(ForeignKey('accounts.id',ondelete='CASCADE'),primary_key=True)
    version: Mapped[int]=mapped_column(BigInteger,default=0)


def tick(mapper,connection,record):
    if record.kind not in PROGRESS_KINDS or not record.owner:return
    # Legacy orphan records must not break source ingestion or acquire a user.
    if not connection.execute(select(Account.id).where(Account.id==record.owner)).first():return
    table=AccountSyncClock.__table__
    if connection.dialect.name=='postgresql':
        from sqlalchemy.dialects.postgresql import insert
    elif connection.dialect.name=='sqlite':
        from sqlalchemy.dialects.sqlite import insert
    else:raise RuntimeError('Unsupported synchronization database')
    statement=insert(table).values(user_id=record.owner,version=1)
    connection.execute(statement.on_conflict_do_update(index_elements=[table.c.user_id],set_={'version':table.c.version+1}))


def archive_card_before_update(mapper,connection,record):
    if record.kind!='card':return
    table=Record.__table__
    previous=connection.execute(select(table.c.data,table.c.revision,table.c.owner).where(table.c.id==record.id)).first()
    if not previous or previous.data==record.data:return
    session=inspect(record).session
    if session and any(isinstance(item,Record) and item.kind=='card_revision'
                       and item.data.get('cardId')==record.id
                       and item.data.get('cardRevision')==previous.revision for item in session.new):return
    # Explicit editors already archive content. Cover changes made by source
    # monitors, moderation and future code paths without duplicating revisions.
    exists=connection.execute(select(table.c.id).where(table.c.kind=='card_revision',
        table.c.data['cardId'].as_string()==record.id,
        table.c.data['cardRevision'].as_integer()==previous.revision).limit(1)).first()
    if exists:return
    key='history:'+hashlib.sha256(f'{record.id}:{previous.revision}'.encode()).hexdigest()
    connection.execute(table.insert().values(id=key,kind='card_revision',owner=previous.owner,data={
        'cardId':record.id,'cardRevision':previous.revision,'content':previous.data,'archivedAt':now()}))

for operation in ('after_insert','after_update','after_delete'):
    event.listen(Record,operation,tick)
event.listen(Record,'before_update',archive_card_before_update)
