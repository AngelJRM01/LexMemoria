#!/usr/bin/env python3
"""Prepare public Firebase client settings in CI; never process a service-account key."""
import argparse,base64,json,os,plistlib,re
from pathlib import Path


def prepare(raw, info_path, defines_path):
    config=plistlib.loads(raw)
    if config.get('BUNDLE_ID')!='es.lexmemoria.app' or config.get('PROJECT_ID')!='lexmemoria-aa86a':
        raise ValueError('La configuración Firebase iOS no corresponde a LexMemoria')
    required=['API_KEY','GOOGLE_APP_ID','GCM_SENDER_ID','CLIENT_ID','REVERSED_CLIENT_ID']
    if any(not isinstance(config.get(k),str) or not config[k] for k in required):
        raise ValueError('Faltan datos de Firebase/Google en el plist iOS')
    if not config['CLIENT_ID'].endswith('.apps.googleusercontent.com') or not re.fullmatch(r'com\.googleusercontent\.apps\.[A-Za-z0-9.-]+',config['REVERSED_CLIENT_ID']):
        raise ValueError('Identificadores de retorno OAuth iOS no válidos')
    info=plistlib.loads(info_path.read_bytes())
    urls=info.get('CFBundleURLTypes',[])
    urls=[v for v in urls if v.get('CFBundleURLName')!='LexMemoria Google OAuth']
    urls.append({'CFBundleURLName':'LexMemoria Google OAuth','CFBundleTypeRole':'Editor','CFBundleURLSchemes':[config['REVERSED_CLIENT_ID']]})
    info['CFBundleURLTypes']=urls
    defines={'LEXMEMORIA_GOOGLE_ENABLED':True,'LEXMEMORIA_IOS_IDENTITY_ENABLED':True,
             'LEXMEMORIA_FIREBASE_PROJECT_ID':config['PROJECT_ID'],
             'LEXMEMORIA_IOS_FIREBASE_API_KEY':config['API_KEY'],
             'LEXMEMORIA_IOS_FIREBASE_APP_ID':config['GOOGLE_APP_ID'],
             'LEXMEMORIA_IOS_FIREBASE_SENDER_ID':config['GCM_SENDER_ID'],
             'LEXMEMORIA_IOS_GOOGLE_CLIENT_ID':config['CLIENT_ID'],
             'LEXMEMORIA_API_URL':'https://lexmemoria-api.onrender.com'}
    defines_path.write_text(json.dumps(defines))
    os.chmod(defines_path,0o600)
    info_path.write_bytes(plistlib.dumps(info,sort_keys=False))
    return config['REVERSED_CLIENT_ID']


def main():
    p=argparse.ArgumentParser();p.add_argument('--info',type=Path,required=True);p.add_argument('--defines',type=Path,required=True);p.add_argument('--plist',type=Path)
    a=p.parse_args()
    raw=a.plist.read_bytes() if a.plist else base64.b64decode(os.environ['IOS_FIREBASE_CONFIG_BASE64'],validate=True)
    prepare(raw,a.info,a.defines)
    print('Configuración iOS validada; retorno OAuth y opciones temporales preparados sin mostrar valores.')

if __name__=='__main__':main()
