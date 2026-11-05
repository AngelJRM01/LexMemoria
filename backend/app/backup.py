"""Authenticated SQLite backups. Restore never overwrites an existing database.

The AES-256 key is supplied by path (32 raw bytes), never as a CLI value.
Production key retention and off-site storage remain deployment responsibilities.
"""
import argparse
import os
from pathlib import Path
import sqlite3
import tempfile
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

MAGIC = b'LEXMEMORIA-SQLITE-AES256GCM-1\n'

def key_at(path):
    key = Path(path).read_bytes()
    if len(key) != 32:
        raise ValueError('La clave debe contener exactamente 32 bytes')
    return key

def exclusive_write(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as stream:
        stream.write(data); stream.flush(); os.fsync(stream.fileno())

def backup(source, destination, key_file):
    source = Path(source).resolve(strict=True)
    key = key_at(key_file)
    with tempfile.TemporaryDirectory() as directory:
        snapshot = Path(directory) / 'snapshot.db'
        with sqlite3.connect(source.as_uri() + '?mode=ro', uri=True) as live, sqlite3.connect(snapshot) as target:
            live.backup(target)
            if target.execute('PRAGMA integrity_check').fetchone()[0] != 'ok':
                raise ValueError('No se ha validado la integridad de la copia')
        nonce = os.urandom(12)
        payload = AESGCM(key).encrypt(nonce, snapshot.read_bytes(), MAGIC)
        exclusive_write(destination, MAGIC + nonce + payload)

def restore(source, destination, key_file):
    data = Path(source).read_bytes()
    if not data.startswith(MAGIC) or len(data) <= len(MAGIC) + 28:
        raise ValueError('Formato de copia incompatible')
    offset = len(MAGIC)
    plaintext = AESGCM(key_at(key_file)).decrypt(data[offset:offset + 12], data[offset + 12:], MAGIC)
    # Validate in a private temporary file before exposing restored data.
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / 'verify.db'; path.write_bytes(plaintext)
        with sqlite3.connect(path) as db:
            if db.execute('PRAGMA integrity_check').fetchone()[0] != 'ok' or db.execute('PRAGMA foreign_key_check').fetchall():
                raise ValueError('La base restaurada no supera las comprobaciones de integridad')
    exclusive_write(destination, plaintext)

def main():
    parser = argparse.ArgumentParser(description='Copias SQLite cifradas de LexMemoria')
    parser.add_argument('operation', choices=['backup', 'restore'])
    parser.add_argument('source'); parser.add_argument('destination'); parser.add_argument('--key-file', required=True)
    args = parser.parse_args()
    (backup if args.operation == 'backup' else restore)(args.source, args.destination, args.key_file)
    print('Copia cifrada creada' if args.operation == 'backup' else 'Copia restaurada y validada')

if __name__ == '__main__': main()
