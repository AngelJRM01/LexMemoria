import base64,importlib.util,json,plistlib,stat
from pathlib import Path
import pytest
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('ios_identity',ROOT/'scripts/prepare_ios_identity.py')
config=importlib.util.module_from_spec(spec);spec.loader.exec_module(config)


def fixture():
    return {'BUNDLE_ID':'es.lexmemoria.app','PROJECT_ID':'lexmemoria-aa86a','API_KEY':'synthetic-client-api-key','GOOGLE_APP_ID':'1:123:ios:fixture','GCM_SENDER_ID':'123','CLIENT_ID':'123-fixture.apps.googleusercontent.com','REVERSED_CLIENT_ID':'com.googleusercontent.apps.123-fixture'}


def test_ios_config_preserves_other_url_handlers_and_enables_both_providers(tmp_path):
    info=tmp_path/'Info.plist';info.write_bytes(plistlib.dumps({'CFBundleURLTypes':[{'CFBundleURLName':'Other','CFBundleURLSchemes':['other']}],'CFBundleIdentifier':'es.lexmemoria.app'}))
    defines=tmp_path/'defines.json'
    for _ in range(2):config.prepare(plistlib.dumps(fixture()),info,defines)
    urls=plistlib.loads(info.read_bytes())['CFBundleURLTypes']
    assert len(urls)==2 and urls[0]['CFBundleURLSchemes']==['other']
    assert urls[1]['CFBundleURLSchemes']==[fixture()['REVERSED_CLIENT_ID']]
    options=json.loads(defines.read_text())
    assert options['LEXMEMORIA_IOS_IDENTITY_ENABLED'] is True
    assert options['LEXMEMORIA_GOOGLE_ENABLED'] is True
    assert stat.S_IMODE(defines.stat().st_mode)==0o600


@pytest.mark.parametrize('field,value',[('BUNDLE_ID','es.lexmemoria.ap'),('PROJECT_ID','another-project'),('CLIENT_ID','bad'),('REVERSED_CLIENT_ID','invalid'),('API_KEY','')])
def test_reject_mismatched_or_incomplete_firebase_config_before_modifying_files(tmp_path,field,value):
    info=tmp_path/'Info.plist';raw=plistlib.dumps({'CFBundleIdentifier':'es.lexmemoria.app'});info.write_bytes(raw)
    c=fixture();c[field]=value
    with pytest.raises(ValueError):config.prepare(plistlib.dumps(c),info,tmp_path/'defines.json')
    assert info.read_bytes()==raw
    assert not (tmp_path/'defines.json').exists()


def test_entitlement_requested_only_on_app_configs():
    project=(ROOT/'mobile/ios/Runner.xcodeproj/project.pbxproj').read_text()
    assert project.count('CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements;')==3
    ent=plistlib.loads((ROOT/'mobile/ios/Runner/Runner.entitlements').read_bytes())
    assert ent['com.apple.developer.applesignin']==['Default']
