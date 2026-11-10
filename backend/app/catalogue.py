"""Derived catalogue search. Source text is never normalized in storage."""
import unicodedata
from sqlalchemy import select, String, Text, or_
from itertools import islice
from sqlalchemy.orm import Mapped, mapped_column
from .db import Base, Record


def normalize(value):
    return ''.join(c for c in unicodedata.normalize('NFKD', value.casefold()) if not unicodedata.combining(c))


class NormIndex(Base):
    __tablename__ = 'norm_search'
    norm_id: Mapped[str] = mapped_column(String(128), primary_key=True)
    text: Mapped[str] = mapped_column(Text)
    jurisdiction: Mapped[str] = mapped_column(String(100), index=True)
    source: Mapped[str] = mapped_column(String(100), index=True)
    kind: Mapped[str] = mapped_column(String(160), index=True)
    review_state: Mapped[str] = mapped_column(String(40), index=True)


def index_norm(session, norm_id, data):
    row = session.get(NormIndex, norm_id)
    if row is None:
        row = NormIndex(norm_id=norm_id)
        session.add(row)
    row.text = normalize(' '.join(str(data.get(k) or '') for k in ('officialId', 'title', 'eliUri', 'authority', 'kind')))
    row.jurisdiction = data.get('jurisdiction') or 'unknown'
    row.source = data.get('source') or 'unknown'
    row.kind = data.get('kind') or 'unknown'
    row.review_state = data.get('reviewState') or 'pending'


def rebuild_index(session):
    """Reconcile derived search in bounded upserts, without N+1 SELECT/UPDATEs."""
    dialect = session.get_bind().dialect.name
    if dialect == 'postgresql':
        from sqlalchemy.dialects.postgresql import insert
    elif dialect == 'sqlite':
        from sqlalchemy.dialects.sqlite import insert
    else:
        for norm in session.scalars(select(Record).where(Record.kind == 'norm')):
            index_norm(session, norm.id, norm.data)
        session.commit()
        return
    rows = iter(session.execute(select(Record.id, Record.data)
        .where(Record.kind == 'norm').execution_options(yield_per=100)))
    table = NormIndex.__table__
    while batch := list(islice(rows, 100)):
        values = []
        for identifier, data in batch:
            values.append(dict(norm_id=identifier,
                text=normalize(' '.join(str(data.get(k) or '') for k in ('officialId', 'title', 'eliUri', 'authority', 'kind'))),
                jurisdiction=data.get('jurisdiction') or 'unknown', source=data.get('source') or 'unknown',
                kind=data.get('kind') or 'unknown', review_state=data.get('reviewState') or 'pending'))
        statement = insert(table).values(values)
        fields = ['text', 'jurisdiction', 'source', 'kind', 'review_state']
        session.execute(statement.on_conflict_do_update(index_elements=[table.c.norm_id],
            set_={key: statement.excluded[key] for key in fields},
            where=or_(*(table.c[key].is_distinct_from(statement.excluded[key]) for key in fields))))
    session.commit()
    # Existing ORM users must not keep stale derived metadata after a repair.
    for row in list(session.identity_map.values()):
        if isinstance(row, NormIndex):
            session.expire(row)
