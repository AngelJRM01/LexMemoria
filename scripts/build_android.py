#!/usr/bin/env python3
"""Build through the inherited HTTPS proxy, without weakening TLS verification."""
import argparse
import os
import re
import shutil
from pathlib import Path
import subprocess
from urllib.parse import urlparse
from firebase_config import google_configuration, public_api_url

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--preview-release', action='store_true', help='Optimized separate preview app, signed for testing only; not for stores')
parser.add_argument('--no-pub', action='store_true', help='Reuse resolved dependencies; release still regenerates Flutter native plugin metadata')
parser.add_argument('--google-config', type=Path, help='Public Android google-services.json; never a service-account key')
parser.add_argument('--api-url', help='HTTPS API base URL confirmed by the owner')
args = parser.parse_args()
root = Path(__file__).resolve().parents[1]
environment = os.environ.copy()
if not environment.get('JAVA_HOME'):
    bundled_javac = sorted(Path('/workspace/tools/jdk').glob('*/bin/javac'))
    if bundled_javac:
        environment['JAVA_HOME'] = str(bundled_javac[-1].parent.parent)
sdk = environment.get('ANDROID_HOME', '/workspace/tools/android-sdk')
environment['ANDROID_HOME'] = sdk
environment['ANDROID_SDK_ROOT'] = sdk
environment.setdefault('GRADLE_USER_HOME', '/workspace/tools/gradle')
proxy = urlparse(environment.get('HTTPS_PROXY', ''))
options = []
if proxy.hostname:
    if proxy.username or proxy.password:
        raise SystemExit('Usa un proxy autenticado por la plataforma, no credenciales en JAVA_TOOL_OPTIONS.')
    options = [f'-Dhttp.proxyHost={proxy.hostname}', f'-Dhttp.proxyPort={proxy.port or 80}',
               f'-Dhttps.proxyHost={proxy.hostname}', f'-Dhttps.proxyPort={proxy.port or 80}']
    trust = Path('/etc/ssl/certs/java/cacerts')
    if trust.is_file(): options.append('-Djavax.net.ssl.trustStore=' + str(trust))
    environment['JAVA_TOOL_OPTIONS'] = environment.get('JAVA_TOOL_OPTIONS', '') + ' ' + ' '.join(options)
flutter = environment.get('FLUTTER_BIN', '/workspace/tools/flutter/bin/flutter')
# JAVA_HOME, if set, must point to a complete JDK including javac.
if environment.get('JAVA_HOME') and not (Path(environment['JAVA_HOME'])/'bin/javac').is_file():
    raise SystemExit('JAVA_HOME no contiene javac; instala un JDK completo.')
mode = '--release' if args.preview_release else '--debug'
if args.preview_release:
    environment['LEXMEMORIA_PREVIEW_SIGNING'] = '1'
config_target = root/'mobile/android/app/google-services.json'
config_source = args.google_config or config_target
configuration = None
flutter_options = []
if config_source.exists():
    package = 'es.lexmemoria.app.preview' if args.preview_release else 'es.lexmemoria.app'
    try:
        configuration = google_configuration(config_source, package)
    except ValueError as error:
        raise SystemExit(str(error)) from None
    if config_source.resolve() != config_target.resolve():
        shutil.copyfile(config_source, config_target)
    flutter_options += ['--dart-define=LEXMEMORIA_GOOGLE_ENABLED=true',
                        '--dart-define=LEXMEMORIA_FIREBASE_PROJECT_ID='+configuration['projectId']]
elif args.google_config:
    raise SystemExit('No existe el archivo de configuración Android indicado.')
if args.api_url:
    try: api_url=public_api_url(args.api_url)
    except ValueError as error:raise SystemExit(str(error)) from None
    flutter_options.append('--dart-define=LEXMEMORIA_API_URL='+api_url)
# Flutter 3.47 skips release plugin regeneration with --no-pub. After tests,
# that leaves integration_test in GeneratedPluginRegistrant even though Gradle
# excludes it from release. Let the supported release build refresh metadata;
# pub get reuses the lockfile. Never hand-edit the generated Java registrant.
result = subprocess.call([flutter, 'build', 'apk', mode,
    *(['--no-pub'] if args.no_pub and not args.preview_release else []), *flutter_options],
    cwd=root/'mobile', env=environment)
if result:raise SystemExit(result)
if configuration:
    signers=sorted((Path(sdk)/'build-tools').glob('*/apksigner'))
    if not signers:raise SystemExit('No se puede comprobar la firma del APK con Firebase.')
    apk=root/'mobile/build/app/outputs/flutter-apk'/('app-release.apk' if args.preview_release else 'app-debug.apk')
    verified=subprocess.run([str(signers[-1]),'verify','--print-certs',str(apk)],env=environment,
        text=True,capture_output=True)
    fingerprints=re.findall(r'certificate SHA-1 digest: ([0-9a-fA-F]+)',verified.stdout)
    if verified.returncode or not any(v.lower() in configuration['sha1s'] for v in fingerprints):
        raise SystemExit('La firma del APK no está registrada en la configuración Google. Añade su SHA-1 y descarga el archivo de nuevo.')
    print('Configuración y firma Android de Google comprobadas; falta aceptación real con el proveedor.')
raise SystemExit(0)
