"""Encrypted PostgreSQL dumps; restores only into an explicitly separate empty DB.

Requires PostgreSQL client tools matching the server major version. The optional
container selector is for an isolated local PostgreSQL test container. Secrets
come from environment/key files and are never command arguments or log output.
"""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url
from .backup import key_at

MAGIC=b'LEXMEMORIA-PG-AES256GCM-1\n'
CHUNK=1024*1024


def encrypt_dump(source,destination,key_file):
    nonce=os.urandom(12)
    encryptor=Cipher(algorithms.AES(key_at(key_file)),modes.GCM(nonce)).encryptor()
    encryptor.authenticate_additional_data(MAGIC)
    fd=os.open(destination,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    try:
        with os.fdopen(fd,'wb') as target,open(source,'rb') as raw:
            target.write(MAGIC+nonce)
            while chunk:=raw.read(CHUNK):target.write(encryptor.update(chunk))
            target.write(encryptor.finalize());target.write(encryptor.tag)
            target.flush();os.fsync(target.fileno())
    except BaseException:
        Path(destination).unlink(missing_ok=True);raise


def decrypt_dump(source,destination,key_file):
    with open(source,'rb') as raw:
        if raw.read(len(MAGIC))!=MAGIC:raise ValueError('Formato incompatible')
        nonce=raw.read(12);raw.seek(-16,2);tag=raw.read(16)
        size=raw.tell()-len(MAGIC)-12-16
        if len(nonce)!=12 or size<1:raise ValueError('Copia incompleta')
        decryptor=Cipher(algorithms.AES(key_at(key_file)),modes.GCM(nonce,tag)).decryptor()
        decryptor.authenticate_additional_data(MAGIC)
        raw.seek(len(MAGIC)+12)
        fd=os.open(destination,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
        try:
            with os.fdopen(fd,'wb') as target:
                while size:
                    chunk=raw.read(min(CHUNK,size))
                    if not chunk:raise ValueError('Copia incompleta')
                    target.write(decryptor.update(chunk));size-=len(chunk)
                target.write(decryptor.finalize());target.flush();os.fsync(target.fileno())
        except BaseException:
            Path(destination).unlink(missing_ok=True);raise


def pg_command(binary,args,url,container=None,input_file=None,output_file=None):
    parsed=make_url(url)
    env=os.environ.copy()
    env.update(PGHOST=parsed.host or 'localhost',PGPORT=str(parsed.port or 5432),
               PGUSER=parsed.username or '',PGPASSWORD=parsed.password or '',PGDATABASE=parsed.database or '')
    for key,value in parsed.query.items():
        if key in ('sslmode','sslrootcert','sslcert','sslkey'):env['PG'+key.upper()]=str(value)
    command=[binary,*args]
    if container:
        for name in ('DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH'):
            env.pop(name,None)
        env.update(PGHOST='127.0.0.1',PGPORT='5432')
        command=['docker','--host=unix:///var/run/docker.sock','exec','-i']
        for name in ('PGHOST','PGPORT','PGUSER','PGPASSWORD','PGDATABASE'):
            command+=['-e',name]
        command += [container,binary,*args]
    with open(input_file,'rb') if input_file else open(os.devnull,'rb') as source:
        with open(output_file,'wb') if output_file else open(os.devnull,'wb') as target:
            try:
                subprocess.run(command,env=env,stdin=source,stdout=target,stderr=subprocess.PIPE,check=True)
            except (subprocess.CalledProcessError,OSError):
                raise RuntimeError('La herramienta PostgreSQL no completó la operación; no se muestran mensajes que puedan contener credenciales') from None


def assert_empty_target(url,source_url):
    if url==source_url:raise ValueError('Restaura en una base distinta de la de origen')
    parsed=make_url(url)
    engine=create_engine(parsed.set(drivername='postgresql+psycopg'))
    try:
        with engine.connect() as connection:
            existing=connection.execute(text("SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace WHERE n.nspname NOT IN ('pg_catalog','information_schema') AND n.nspname NOT LIKE 'pg_toast%' AND c.relkind IN ('r','S','m') LIMIT 1")).first()
            if existing:raise ValueError('La base de restauración debe estar vacía; no se sobrescribe contenido')
    finally:engine.dispose()


def backup(url,destination,key_file,container=None):
    if Path(destination).exists():raise FileExistsError('La copia ya existe')
    with tempfile.TemporaryDirectory() as directory:
        dump=Path(directory)/'snapshot.dump'
        pg_command('pg_dump',['--format=custom','--no-owner','--no-privileges'],url,container,output_file=dump)
        encrypt_dump(dump,destination,key_file)


def restore(source,target_url,key_file,source_url,container=None):
    with tempfile.TemporaryDirectory() as directory:
        dump=Path(directory)/'verified.dump'
        decrypt_dump(source,dump,key_file)
        pg_command('pg_restore',['--list'],target_url,container,input_file=dump)
        assert_empty_target(target_url,source_url)
        pg_command('pg_restore',['--dbname',make_url(target_url).database,'--single-transaction','--exit-on-error','--no-owner','--no-privileges'],target_url,container,input_file=dump)


def main():
    p=argparse.ArgumentParser(description='Copias PostgreSQL cifradas sin sobrescribir bases existentes')
    p.add_argument('operation',choices=['backup','restore']);p.add_argument('file',type=Path)
    p.add_argument('--key-file',type=Path,required=True);p.add_argument('--container',help='Solo prueba local: contenedor PostgreSQL aislado')
    args=p.parse_args();source=os.environ.get('DATABASE_URL')
    if not source:raise SystemExit('Configura DATABASE_URL de forma segura')
    if args.operation=='backup':backup(source,args.file,args.key_file,args.container)
    else:
        target=os.environ.get('LEXMEMORIA_RESTORE_DATABASE_URL')
        if not target:raise SystemExit('Configura LEXMEMORIA_RESTORE_DATABASE_URL para una base nueva y vacía')
        restore(args.file,target,args.key_file,source,args.container)
    print('Operación PostgreSQL completada. Custodia la clave y la copia en ubicaciones separadas.')

if __name__=='__main__':main()
