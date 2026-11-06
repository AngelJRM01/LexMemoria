"""Fail closed before touching an ephemeral filesystem or logging a secret URL."""
import pytest
from unittest.mock import Mock
from app import db

@pytest.mark.parametrize('environment',['staging','production'])
@pytest.mark.parametrize('url',[None,'','sqlite:///./danger.db','not-a-valid-database-url'])
def test_production_never_falls_back_to_local_storage(monkeypatch,environment,url,tmp_path):
    monkeypatch.setenv('LEXMEMORIA_ENV',environment)
    monkeypatch.chdir(tmp_path)
    if url is None:monkeypatch.delenv('DATABASE_URL',raising=False)
    else:monkeypatch.setenv('DATABASE_URL',url)
    with pytest.raises(RuntimeError,match='PostgreSQL DATABASE_URL is required'):
        db.connect()
    assert list(tmp_path.iterdir())==[]

def test_bad_url_error_never_contains_password(monkeypatch):
    monkeypatch.setenv('LEXMEMORIA_ENV','production')
    with pytest.raises(RuntimeError) as error:
        db.connect('wrong://user:private-password@server/db')
    assert 'private-password' not in str(error.value)

@pytest.mark.parametrize('scheme',['postgres','postgresql','postgresql+psycopg'])
def test_postgres_configuration_uses_expected_driver_without_contacting_provider(monkeypatch,scheme):
    monkeypatch.setenv('LEXMEMORIA_ENV','production')
    engine=Mock();received={}
    def factory(url,**options):received.update(url=url,options=options);return engine
    monkeypatch.setattr(db,'create_engine',factory)
    monkeypatch.setattr(db.Base.metadata,'create_all',lambda _:None)
    db.connect(f'{scheme}://user:password@server/database')
    assert received['url'].startswith('postgresql+psycopg://')
    assert received['options']['pool_pre_ping'] is True
