"""The release may remove media picker APIs only while all app callers use documents."""
from pathlib import Path
import re
import yaml

ROOT=Path(__file__).resolve().parents[2]


def test_every_picker_caller_uses_document_mode():
    calls=[]
    for path in (ROOT/'mobile/lib').glob('*.dart'):
        source=path.read_text()
        calls.extend(re.findall(r'FilePicker\.platform\.pickFiles\((.*?)\);',source,re.S))
    assert calls,'Expected actual file-import coverage'
    assert all('type: FileType.custom' in call for call in calls)
    assert all('allowedExtensions:' in call for call in calls)


def test_signed_pipeline_rejects_media_dependencies_before_upload():
    w=yaml.load((ROOT/'.github/workflows/apple-signed-build.yml').read_text(),Loader=yaml.BaseLoader)
    steps=w['jobs']['signed-ipa']['steps']
    names=[s.get('name') for s in steps]
    config=next(s for s in steps if s.get('name')=='Use CocoaPods configuration for document-only picker')
    assert '--no-enable-swift-package-manager' in config['run']
    verify=next(s for s in steps if s.get('name')=='Verify signature and package IPA')
    assert "assert info['CFBundleVersion']=='20'" in verify['run']
    assert 'DKImagePickerController' in verify['run'] and 'not in lock' in verify['run']
    assert names.index('Verify signature and package IPA') < names.index('Upload corrected build to Apple without submission for review')
    assert steps[-1]['if']=='${{ always() }}'
    assert 'lexmemoria-asc' in steps[-1]['run']
