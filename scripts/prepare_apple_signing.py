#!/usr/bin/env python3
"""Validate an App Store profile and configure only Runner in the ephemeral CI checkout."""
import argparse
import datetime as dt
import hashlib
import plistlib
from pathlib import Path
import re

BUNDLE = 'es.lexmemoria.app'
TEAM = 'ZR9YWRMKC8'


def validate(profile, identities, now=None):
    now = now or dt.datetime.now(dt.timezone.utc)
    expiry = profile['ExpirationDate']
    if expiry.tzinfo is None:
        expiry = expiry.replace(tzinfo=dt.timezone.utc)
    ent = profile['Entitlements']
    if expiry <= now:
        raise ValueError('El perfil ha caducado')
    if profile.get('TeamIdentifier') != [TEAM]:
        raise ValueError('El perfil no corresponde al equipo esperado')
    if ent.get('application-identifier') != TEAM + '.' + BUNDLE:
        raise ValueError('El perfil no corresponde al identificador de LexMemoria')
    if ent.get('get-task-allow') is not False or profile.get('ProvisionedDevices') or profile.get('ProvisionsAllDevices'):
        raise ValueError('Se necesita un perfil App Store Connect, no desarrollo/ad hoc/enterprise')
    uuid = profile['UUID']
    if not re.fullmatch(r'[A-Fa-f0-9-]{36}', uuid):
        raise ValueError('UUID de perfil no válido')
    permitted = {hashlib.sha1(cert).hexdigest().upper() for cert in profile['DeveloperCertificates']}
    valid = set(re.findall(r'\b([A-F0-9]{40})\b', identities))
    matching = permitted & valid
    if len(matching) != 1:
        raise ValueError('El certificado privado importado no coincide con el perfil o no es válido')
    return uuid, matching.pop()


def configure_project(text, uuid, fingerprint):
    count = 0
    def replace(match):
        nonlocal count
        block = match[0]
        if 'PRODUCT_BUNDLE_IDENTIFIER = ' + BUNDLE + ';' not in block:
            return block
        count += 1
        additions = {'CODE_SIGN_STYLE':'Manual','DEVELOPMENT_TEAM':TEAM,
                     'PROVISIONING_PROFILE_SPECIFIER':uuid,'CODE_SIGN_IDENTITY':fingerprint}
        for key, value in additions.items():
            block = re.sub(r'(?m)^[ \t]*' + key + r' = [^;]+;\n', '', block)
        return block.replace('buildSettings = {\n','buildSettings = {\n' + ''.join(f'\t\t\t\t{k} = "{v}";\n' for k,v in additions.items()),1)
    result = re.sub(r'buildSettings = \{.*?\n\s*\};',replace,text,flags=re.S)
    if count != 3:
        raise ValueError('No se encontraron las tres configuraciones Runner esperadas')
    return result


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--profile',type=Path,required=True)
    parser.add_argument('--identities',type=Path,required=True)
    parser.add_argument('--project',type=Path,required=True)
    parser.add_argument('--export-options',type=Path,required=True)
    args=parser.parse_args()
    uuid, fingerprint=validate(plistlib.loads(args.profile.read_bytes()),args.identities.read_text())
    project=configure_project(args.project.read_text(),uuid,fingerprint)
    options={'method':'app-store-connect','destination':'export','teamID':TEAM,
             'signingStyle':'manual','signingCertificate':fingerprint,
             'provisioningProfiles':{BUNDLE:uuid},'manageAppVersionAndBuildNumber':False,
             'uploadSymbols':True}
    args.export_options.write_bytes(plistlib.dumps(options))
    args.project.write_text(project)
    print('Perfil App Store y certificado compatibles; firma manual configurada para Runner.')

if __name__=='__main__':
    main()
