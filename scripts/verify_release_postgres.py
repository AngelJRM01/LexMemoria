#!/usr/bin/env python3
"""Release integrity exercise on a disposable local PG18 container only.

Requires container lexmemoria-v1-validation with trust auth bound exclusively to
127.0.0.1:55434. Creates fresh fixture databases; never drops/overwrites a DB.
No production URL is accepted. Reports contain counts/hashes, not user content.
"""
import argparse, hashlib, json, os, sys, tempfile
from datetime import datetime, timezone
from pathlib import Path
import psycopg
from psycopg import sql
from cryptography.exceptions import InvalidTag
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, text

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'backend'))
from app.main import create_app
from app.postgres_backup import backup, restore

BASE='postgresql+psycopg://postgres@127.0.0.1:55434/'
CONTAINER='lexmemoria-v1-validation'


def inventory(url):
    engine=create_engine(url)
    try:
        with engine.connect() as connection:
            tables=connection.execute(text("SELECT tablename FROM pg_tables WHERE schemaname='public' ORDER BY tablename")).scalars().all()
            result={}
            for table in tables:
                # Names originate only from pg_tables, quoted by the dialect.
                quoted=engine.dialect.identifier_preparer.quote(table)
                rows=connection.execute(text(f'SELECT row_to_json(t) FROM {quoted} t')).scalars().all()
                encoded=sorted(json.dumps(row,sort_keys=True,ensure_ascii=False,default=str) for row in rows)
                result[table]={'rows':len(rows),'sha256':hashlib.sha256('\n'.join(encoded).encode()).hexdigest()}
            return result
    finally:engine.dispose()


def exported(client, headers):
    result=client.get('/v1/account/export',headers=headers).json()
    result.pop('exportedAt',None)  # Request timestamp is not persisted domain data.
    result['records']=sorted(result['records'],key=lambda row:row['id'])
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--report',type=Path,required=True);args=parser.parse_args()
    # Refuse existing names rather than replacing a previous fixture.
    prefix='lexmemoria_v1_'+os.urandom(4).hex()
    names=[prefix+suffix for suffix in ('_source','_restored','_empty')]
    with psycopg.connect('host=127.0.0.1 port=55434 user=postgres dbname=postgres',autocommit=True) as admin:
        for name in names:admin.execute(sql.SQL('CREATE DATABASE {}').format(sql.Identifier(name)))
    source,target,empty=[BASE+name for name in names]
    app=create_app(source);client=TestClient(app)
    sessions=[client.post('/v1/auth/guest').json() for _ in range(2)]
    a,b=[{'Authorization':'Bearer '+s['accessToken']} for s in sessions]
    deck=client.post('/v1/decks',headers=a,json={'title':'Fixture de recuperación'}).json()
    card=client.post('/v1/cards',headers=a,json={'deckId':deck['id'],'clientId':'fixture-stable-id','front':'Pregunta ñ𝑥','back':'Respuesta','citations':[]}).json()
    assert client.get('/v1/cards/by-client/fixture-stable-id',headers=b).status_code==404
    review={'cardId':card['id'],'cardRevision':1,'rating':3,'occurredAt':datetime.now(timezone.utc).isoformat(),'idempotencyKey':'release-integrity-review'}
    first=client.post('/v1/reviews',headers=a,json=review);second=client.post('/v1/reviews',headers=a,json=review)
    assert first.status_code==201 and second.status_code in (200,201) and first.json()==second.json()
    assert client.put('/v1/workspace',headers={**a,'If-Match':'0'},json={'notes':{'fixture':'Nota ñ𝑥'}}).status_code==200
    assert client.put('/v1/workspace',headers={**a,'If-Match':'0'},json={'notes':{'fixture':'No sobrescribir'}}).status_code==409
    expected=exported(client,a)
    assert sessions[0]['accessToken'] not in json.dumps(expected)
    restarted=TestClient(create_app(source))
    assert exported(restarted,a)==expected
    before=inventory(source)
    with tempfile.TemporaryDirectory(prefix='lexmemoria-v1-pg-') as directory:
        directory=Path(directory);key=directory/'key';archive=directory/'backup.lexbackup'
        key.write_bytes(os.urandom(32));key.chmod(0o600)
        backup(source,archive,key,CONTAINER)
        assert b'Pregunta' not in archive.read_bytes()
        assert inventory(source)==before
        restore(archive,target,key,source,CONTAINER)
        assert inventory(target)==before
        for destination in (source,target):
            try:restore(archive,destination,key,source,CONTAINER)
            except ValueError:pass
            else:raise AssertionError('Existing/source database was accepted')
        assert inventory(source)==before and inventory(target)==before
        corrupt=directory/'corrupt.lexbackup';blob=bytearray(archive.read_bytes());blob[-1]^=1;corrupt.write_bytes(blob)
        try:restore(corrupt,empty,key,source,CONTAINER)
        except InvalidTag:pass
        else:raise AssertionError('Tampered backup was accepted')
        assert inventory(empty)=={}
        restored_client=TestClient(create_app(target))
        assert exported(restored_client,a)==expected
        assert restored_client.get('/v1/cards/by-client/fixture-stable-id',headers=b).status_code==404
        report={'environment':'PostgreSQL 18 disposable local container; not Render',
                'ownerIsolation':True,'reviewIdempotency':True,'workspaceConflictPreserved':True,
                'restartPreservedExport':True,'encryptedBackup':True,'restoredAllTablesEqual':True,
                'refusedSourceAndNonemptyTargets':True,'tamperedBackupRejectedBeforeWrite':True,
                'restoredApiExportEqual':True,'tableInventory':before,'renderVerified':False}
        args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2)+'\n')
        print(json.dumps({k:v for k,v in report.items() if k!='tableInventory'}))

if __name__=='__main__':main()
