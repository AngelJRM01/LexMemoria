import os
from datetime import datetime, timezone
from uuid import uuid4
from sqlalchemy import create_engine, String, Text, JSON, UniqueConstraint, ForeignKey, Index, event, text
from sqlalchemy.engine import make_url
from sqlalchemy.schema import CreateIndex
from sqlalchemy.ext.compiler import compiles
from sqlalchemy.ext.hybrid import hybrid_property
from sqlalchemy.sql.functions import FunctionElement
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, sessionmaker


def now():
    return datetime.now(timezone.utc).isoformat()


def uid():
    return str(uuid4())


class Base(DeclarativeBase):
    pass


class ClientIdentifier(FunctionElement):
    """Constant JSON path, so both dialects can use its expression index."""
    type = String()
    inherit_cache = True


@compiles(ClientIdentifier, 'sqlite')
def sqlite_client_identifier(element, compiler, **kw):
    return "JSON_EXTRACT(%s, '$.\"clientId\"')" % compiler.process(list(element.clauses)[0], **kw)


@compiles(ClientIdentifier, 'postgresql')
def postgres_client_identifier(element, compiler, **kw):
    return "CAST(%s ->> 'clientId' AS VARCHAR)" % compiler.process(list(element.clauses)[0], **kw)


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

    @hybrid_property
    def client_id(self):
        return self.data.get('clientId')

    @client_id.expression
    def client_id(cls):
        return ClientIdentifier(cls.data)


RECORD_QUERY_INDEXES = (
    Index('ix_records_owner_kind_id', Record.owner, Record.kind, Record.id),
    Index('ix_records_owner_kind_client_id', Record.owner, Record.kind, Record.client_id),
)


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
    # Register additive clock schema and history hooks in API and CLI workers.
    from . import sync_clock
    configured = url if url is not None else os.getenv('DATABASE_URL')
    if os.getenv('LEXMEMORIA_ENV', 'development') in ('staging', 'production'):
        try:
            driver = make_url(configured).drivername if configured else ''
        except Exception:
            driver = ''
        if driver not in ('postgres', 'postgresql', 'postgresql+psycopg'):
            # Render's filesystem is ephemeral. Never silently create a local
            # SQLite database when production configuration is missing/wrong.
            raise RuntimeError('PostgreSQL DATABASE_URL is required in staging/production; local fallback is disabled.')
    url = configured or 'sqlite:///./lexmemoria.db'
    if url.startswith(('postgres://', 'postgresql://')):
        url = 'postgresql+psycopg://' + url.split('://', 1)[1]
    engine = create_engine(url, pool_pre_ping=True, connect_args={'check_same_thread': False} if url.startswith('sqlite') else {})
    if url.startswith('sqlite'):
        @event.listens_for(engine, 'connect')
        def fk(connection, _):
            connection.execute('PRAGMA foreign_keys=ON')
    with engine.begin() as connection:
        if engine.dialect.name == 'postgresql':
            # Serialize additive schema creation across starting API workers.
            # This does not replace versioned migrations for future ALTERs.
            connection.execute(text('SELECT pg_advisory_xact_lock(753309520061106)'))
        Base.metadata.create_all(connection)
        # create_all skips indexes on existing tables: upgrade old installs too.
        for index in RECORD_QUERY_INDEXES:
            connection.execute(CreateIndex(index, if_not_exists=True))
    return engine, sessionmaker(engine, expire_on_commit=False)
