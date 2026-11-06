"""Validate public Android Firebase config without exposing keys or accepting admin credentials."""
import json
from pathlib import Path
import re
from urllib.parse import urlsplit

PROJECT='lexmemoria-aa86a'


def google_configuration(path,package,expected_project=PROJECT):
    try: data=json.loads(Path(path).read_text())
    except (ValueError,OSError) as error:
        raise ValueError('No se pudo leer la configuración Android de Firebase.') from error
    if not isinstance(data,dict) or data.get('type')=='service_account' or 'private_key' in data:
        raise ValueError('Se necesita google-services.json de la app Android; nunca una cuenta de servicio o clave privada.')
    project=data.get('project_info',{}).get('project_id')
    if project!=expected_project:
        raise ValueError('La configuración corresponde a otro proyecto Firebase.')
    clients=data.get('client',[])
    matches=[c for c in clients if c.get('client_info',{}).get('android_client_info',{}).get('package_name')==package]
    if len(matches)!=1:
        raise ValueError(f'La configuración debe incluir exactamente una app Android {package}.')
    client=matches[0]
    if not client.get('client_info',{}).get('mobilesdk_app_id'):
        raise ValueError('Falta el identificador de la app Firebase.')
    if not any(isinstance(k.get('current_key'),str) and len(k['current_key'])>10 for k in client.get('api_key',[])):
        raise ValueError('Falta la configuración de API pública de Firebase.')
    web=[o.get('client_id') for o in client.get('oauth_client',[]) if o.get('client_type')==3]
    if not any(isinstance(v,str) and v.endswith('.apps.googleusercontent.com') for v in web):
        raise ValueError('Activa Google en Authentication, añade SHA-1 y vuelve a descargar google-services.json.')
    sha1s=set()
    for oauth in client.get('oauth_client',[]):
        android=oauth.get('android_info',{})
        if oauth.get('client_type')!=1 or android.get('package_name')!=package:continue
        value=android.get('certificate_hash','').replace(':','').lower()
        if re.fullmatch('[0-9a-f]{40}',value):sha1s.add(value)
    if not sha1s:
        raise ValueError('Añade la SHA-1 del APK a Firebase y vuelve a descargar la configuración.')
    return {'projectId':project,'package':package,'sha1s':sorted(sha1s)}


def public_api_url(value):
    parts=urlsplit(value)
    if (parts.scheme!='https' or not parts.hostname or parts.username is not None or
        parts.password is not None or parts.query or parts.fragment):
        raise ValueError('La API debe ser una URL HTTPS pública, sin credenciales, consulta ni fragmento.')
    if parts.path.rstrip('/').endswith('/health'):
        raise ValueError('Usa la URL base de la API, sin /health.')
    return value.rstrip('/')
