#!/usr/bin/env python3
"""Build the es.lexmemoria.app Play bundle without creating or exposing a key.

Default mode requires existing owner-controlled signing credentials in secure
environment variables and the production Android Firebase public config.
--unsigned-validation builds a clearly incomplete validation artifact only.
"""
import argparse, hashlib, json, os, re, shutil, subprocess, zipfile
from pathlib import Path
from urllib.parse import urlparse
from firebase_config import google_configuration, public_api_url

ROOT=Path(__file__).resolve().parents[1]
NAMES=('LEXMEMORIA_UPLOAD_STORE_FILE','LEXMEMORIA_UPLOAD_STORE_PASSWORD',
       'LEXMEMORIA_UPLOAD_KEY_ALIAS','LEXMEMORIA_UPLOAD_KEY_PASSWORD')


def preflight(env,config):
    missing=[name for name in NAMES if not env.get(name)]
    firebase=False
    if config.is_file():
        try:google_configuration(config,'es.lexmemoria.app');firebase=True
        except ValueError:pass
    key_path=Path(env[NAMES[0]]).resolve() if env.get(NAMES[0]) else None
    outside=bool(key_path and key_path.is_file() and not key_path.is_relative_to(ROOT))
    return {'package':'es.lexmemoria.app','missingSigningVariables':missing,
            'existingKeyOutsideRepository':outside,'productionFirebaseConfigured':firebase,
            'readyForSignedBuild':not missing and outside and firebase}


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preflight',action='store_true')
    parser.add_argument('--unsigned-validation',action='store_true')
    parser.add_argument('--api-url',default='https://lexmemoria-api.onrender.com')
    args=parser.parse_args();env=os.environ.copy();config=ROOT/'mobile/android/app/google-services.json'
    state=preflight(env,config)
    if args.preflight:print(json.dumps(state,indent=2));return
    if not args.unsigned_validation and not state['readyForSignedBuild']:
        raise SystemExit('Firma/registro Firebase de producción pendientes. Ejecuta --preflight; no envíes claves ni contraseñas al chat.')
    env.pop('LEXMEMORIA_PREVIEW_SIGNING',None)
    env.pop('LEXMEMORIA_ANDROID_VALIDATION_ONLY',None)
    if args.unsigned_validation:
        for name in NAMES:env.pop(name,None)
        env['LEXMEMORIA_ANDROID_VALIDATION_ONLY']='1'
    if not env.get('JAVA_HOME'):
        bundled=sorted(Path('/workspace/tools/jdk').glob('*/bin/javac'))
        javac=bundled[-1] if bundled else Path(shutil.which('javac') or '')
        if not javac.is_file():raise SystemExit('Configura un JDK completo mediante JAVA_HOME')
        env['JAVA_HOME']=str(javac.resolve().parent.parent)
    env.setdefault('ANDROID_HOME','/workspace/tools/android-sdk');env['ANDROID_SDK_ROOT']=env['ANDROID_HOME']
    env.setdefault('GRADLE_USER_HOME','/workspace/tools/gradle')
    proxy=urlparse(env.get('HTTPS_PROXY',''))
    if proxy.hostname:
        if proxy.username or proxy.password:raise SystemExit('Usa el proxy de plataforma sin credenciales en opciones Java.')
        env['JAVA_TOOL_OPTIONS']=env.get('JAVA_TOOL_OPTIONS','')+' '+ ' '.join([
            f'-Dhttp.proxyHost={proxy.hostname}',f'-Dhttp.proxyPort={proxy.port or 80}',
            f'-Dhttps.proxyHost={proxy.hostname}',f'-Dhttps.proxyPort={proxy.port or 80}',
            '-Djavax.net.ssl.trustStore=/etc/ssl/certs/java/cacerts'])
    command=[env.get('FLUTTER_BIN','/workspace/tools/flutter/bin/flutter'),'build','appbundle','--release',
             '--dart-define=LEXMEMORIA_API_URL='+public_api_url(args.api_url)]
    if not args.unsigned_validation:
        command+=['--dart-define=LEXMEMORIA_GOOGLE_ENABLED=true','--dart-define=LEXMEMORIA_FIREBASE_PROJECT_ID=lexmemoria-aa86a']
    result=subprocess.call(command,cwd=ROOT/'mobile',env=env)
    if result:raise SystemExit(result)
    bundle=ROOT/'mobile/build/app/outputs/bundle/release/app-release.aab'
    with zipfile.ZipFile(bundle) as archive:
        assert archive.testzip() is None
        assert 'base/manifest/AndroidManifest.xml' in archive.namelist()
        signed=any(name.startswith('META-INF/') and name.endswith(('.RSA','.EC','.DSA')) for name in archive.namelist())
    if signed==args.unsigned_validation:raise SystemExit('El estado de firma no corresponde al modo solicitado')
    certificate_sha1=None
    if signed:
        checked=subprocess.run([str(Path(env['JAVA_HOME'])/'bin/jarsigner'),'-verify',str(bundle)],env=env,capture_output=True,text=True)
        if checked.returncode or 'jar verified' not in checked.stdout.lower():raise SystemExit('No se pudo verificar la firma del AAB')
        certificate=subprocess.run([str(Path(env['JAVA_HOME'])/'bin/keytool'),'-J-Duser.language=en','-printcert','-jarfile',str(bundle)],env=env,capture_output=True,text=True)
        matches=re.findall(r'SHA1:\s*([0-9A-Fa-f:]{40,59})',certificate.stdout)
        if certificate.returncode or len(set(matches))!=1:raise SystemExit('Certificado de subida ambiguo o no verificable')
        certificate_sha1=matches[0].replace(':','').lower()
        if certificate_sha1=='967643569eddb573c9153ce97b4b789671c29008' or 'CN=Android Debug' in certificate.stdout:
            raise SystemExit('La firma de pruebas no se acepta como firma de subida de producción')
    out=ROOT/'artifacts/play';out.mkdir(parents=True,exist_ok=True)
    name='LexMemoria-1.0.0-'+('UNSIGNED-validation' if args.unsigned_validation else 'upload-signed')+'.aab'
    target=out/name;shutil.copyfile(bundle,target)
    report={**state,'artifact':name,'signed':signed,'validationOnly':args.unsigned_validation,
            'uploadCertificateSha1':certificate_sha1,'googleEnabledInArtifact':not args.unsigned_validation,'readyForPlaySubmission':False,
            'bytes':target.stat().st_size,'sha256':hashlib.sha256(target.read_bytes()).hexdigest(),
            'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
            'playConsoleAcceptance':'pending','physicalAcceptance':'pending'}
    evidence=ROOT/'docs/release-1.0/evidence';evidence.mkdir(parents=True,exist_ok=True)
    (evidence/'play-bundle.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))

if __name__=='__main__':main()
