"""Derived catalogue search. Source text is never normalized in storage."""
import unicodedata
from sqlalchemy import select, String, Text
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
    for norm in session.scalars(select(Record).where(Record.kind == 'norm')):
        index_norm(session, norm.id, norm.data)
    session.commit()
