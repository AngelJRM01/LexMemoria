#!/usr/bin/env python3
"""Materialize a team API key only in the ephemeral runner, never in artifacts."""
import base64
import os
from pathlib import Path
import re
import uuid


def prepare(environment):
    key_id=environment.get('ASC_KEY_ID','').strip()
    issuer=environment.get('ASC_ISSUER_ID','').strip()
    encoded=environment.get('ASC_PRIVATE_KEY_BASE64','').strip()
    if not re.fullmatch(r'[A-Z0-9]{10}',key_id):
        raise ValueError('APP_STORE_CONNECT_KEY_ID ausente o no válido')
    try:
        uuid.UUID(issuer)
    except ValueError:
        raise ValueError('APP_STORE_CONNECT_ISSUER_ID ausente o no válido') from None
    try:
        raw=base64.b64decode(encoded,validate=True)
    except ValueError:
        raise ValueError('APP_STORE_CONNECT_PRIVATE_KEY_BASE64 no es Base64 válido') from None
    if not raw.startswith(b'-----BEGIN PRIVATE KEY-----') or b'-----END PRIVATE KEY-----' not in raw:
        raise ValueError('Se necesita la clave privada .p8 de App Store Connect')
    target=Path(environment['RUNNER_TEMP'])/'lexmemoria-asc'/'private_keys'
    target.mkdir(parents=True,mode=0o700,exist_ok=True)
    path=target/('AuthKey_'+key_id+'.p8')
    with path.open('xb') as output:
        os.chmod(path,0o600)
        output.write(raw)
    return path


if __name__=='__main__':
    try:
        prepare(os.environ)
    except (ValueError,KeyError):
        raise SystemExit('Configuración App Store Connect inválida: revisa los nombres y formatos de los tres secretos, sin copiarlos al log.')
    print('Clave App Store Connect preparada temporalmente; contenido no mostrado.')
