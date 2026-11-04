"""Render the checked-out official Flutter templates when flutter create cannot run.
Once Flutter/Dart are available, use scripts/setup.sh to regenerate/validate tool metadata.
This only creates missing files; it never overwrites application sources.
"""
from pathlib import Path
import re
import shutil
import sys
import chevron

sdk = Path(sys.argv[1] if len(sys.argv) > 1 else '/workspace/tools/flutter')
root = Path(__file__).resolve().parents[1] / 'mobile'
templates = sdk / 'packages/flutter_tools/templates/app'
gradle = (sdk / 'packages/flutter_tools/lib/src/android/gradle_utils.dart').read_text()
def version(name):
    return re.search(r"const " + name + r" = '([^']+)';", gradle)[1]
ctx = dict(projectName='lexmemoria', titleCaseProjectName='LexMemoria',
           androidIdentifier='es.lexmemoria.app', iosIdentifier='es.lexmemoria.app',
           organization='es.lexmemoria', description='Estudio jurídico con fuentes verificables',
           agpVersion=version('templateAndroidGradlePluginVersion'),
           kotlinVersion=version('templateKotlinGradlePluginVersion'),
           gradleVersion=version('templateDefaultGradleVersion'),
           withSwiftPackageManager=False, withPlatformChannelPluginHook=False,
           hasIosDevelopmentTeam=False, iosDevelopmentTeam='', year=2026)
for src, dest in [('android.tmpl', 'android'), ('android-kotlin.tmpl', 'android'), ('ios.tmpl', 'ios'), ('web', 'web')]:
    for p in (templates / src).rglob('*'):
        if not p.is_file(): continue
        name = str(p.relative_to(templates / src)).replace('androidIdentifier', 'es/lexmemoria/app').replace('projectName', 'lexmemoria')
        if name.endswith('.img.tmpl') or name.endswith('.copy.tmpl'):
            # Platform icons are populated separately from official Android assets.
            continue
        templated = name.endswith('.tmpl')
        if templated: name = name[:-5]
        target = root / dest / name
        if target.exists(): continue
        target.parent.mkdir(parents=True, exist_ok=True)
        if templated:
            rendered = chevron.render(p.read_text(), ctx)
            if '{{' in rendered: raise ValueError('Unrendered template: ' + str(p))
            target.write_text(rendered)
        else: shutil.copyfile(p, target)
print('Android, iOS and web template files created. Native compilation remains unverified.')
