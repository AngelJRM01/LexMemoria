#!/usr/bin/env python3
"""Build through the inherited HTTPS proxy, without weakening TLS verification."""
import os
from pathlib import Path
import subprocess
from urllib.parse import urlparse

root = Path(__file__).resolve().parents[1]
environment = os.environ.copy()
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
raise SystemExit(subprocess.call([flutter, 'build', 'apk', '--debug'], cwd=root/'mobile', env=environment))
