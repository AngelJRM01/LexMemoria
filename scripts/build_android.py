#!/usr/bin/env python3
"""Build through the inherited HTTPS proxy, without weakening TLS verification."""
import argparse
import os
from pathlib import Path
import subprocess
from urllib.parse import urlparse

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--preview-release', action='store_true', help='Optimized separate preview app, signed for testing only; not for stores')
parser.add_argument('--no-pub', action='store_true', help='Use dependencies already resolved with flutter pub get')
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
raise SystemExit(subprocess.call([flutter, 'build', 'apk', mode, *(['--no-pub'] if args.no_pub else [])], cwd=root/'mobile', env=environment))
