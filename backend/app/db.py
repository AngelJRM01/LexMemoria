import os
from datetime import datetime, timezone
from uuid import uuid4
from sqlalchemy import create_engine, String, Text, JSON, UniqueConstraint, ForeignKey, event
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker


def now():
    return datetime.now(timezone.utc).isoformat()


def uid():
    return str(uuid4())


class Base(DeclarativeBase):
    pass


class Record(Base):
    """Versioned domain aggregate. Owner is always enforced by the API."""
    __tablename__ = 'records'
    id: Mapped[str] = mapped_column(String(128), primary_key=True, default=uid)
    kind: Mapped[str] = mapped_column(String(40), index=True)
    owner: Mapped[str | None] = mapped_column(String(128), index=True, nullable=True)
    revision: Mapped[int] = mapped_column(default=1)
    data: Mapped[dict] = mapped_column(JSON, default=dict)
    created_at: Mapped[str] = mapped_column(default=now)
    __mapper_args__ = {'version_id_col': revision}


class Account(Base):
    __tablename__ = 'accounts'
    id: Mapped[str] = mapped_column(primary_key=True, default=uid)
    role: Mapped[str] = mapped_column(default='user')
    created_at: Mapped[str] = mapped_column(default=now)


class Token(Base):
    __tablename__ = 'tokens'
    digest: Mapped[str] = mapped_column(primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('accounts.id'), index=True)
    expires_at: Mapped[str]
    kind: Mapped[str] = mapped_column(default='access')


class RecoveryCode(Base):
    __tablename__ = 'recovery_codes'
    digest: Mapped[str] = mapped_column(primary_key=True)
    user_id: Mapped[str] = mapped_column(ForeignKey('accounts.id'), unique=True, index=True)
    created_at: Mapped[str] = mapped_column(default=now)


class Mutation(Base):
    __tablename__ = 'mutations'
    __table_args__ = (UniqueConstraint('user_id', 'key'),)
    id: Mapped[str] = mapped_column(primary_key=True, default=uid)
    user_id: Mapped[str] = mapped_column(ForeignKey('accounts.id'), index=True)
    key: Mapped[str] = mapped_column(String(128))
    payload_hash: Mapped[str]
    result: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[str] = mapped_column(default=now)


class Audit(Base):
    __tablename__ = 'audit'
    id: Mapped[str] = mapped_column(primary_key=True, default=uid)
    actor: Mapped[str] = mapped_column(index=True)
    entity: Mapped[str] = mapped_column(index=True)
    action: Mapped[str]
    data: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[str] = mapped_column(default=now)


def connect(url=None):
    url = url or os.getenv('DATABASE_URL', 'sqlite:///./lexmemoria.db')
    engine = create_engine(url, connect_args={'check_same_thread': False} if url.startswith('sqlite') else {})
    if url.startswith('sqlite'):
        @event.listens_for(engine, 'connect')
        def fk(connection, _):
            connection.execute('PRAGMA foreign_keys=ON')
    Base.metadata.create_all(engine)
    return engine, sessionmaker(engine, expire_on_commit=False)
