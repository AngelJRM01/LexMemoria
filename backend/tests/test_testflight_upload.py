import base64
import importlib.util
from pathlib import Path
import stat
import subprocess
import pytest
import yaml
ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('testflight_key',ROOT/'scripts/prepare_testflight_key.py')
key=importlib.util.module_from_spec(spec);spec.loader.exec_module(key)


def env(tmp_path):
    return {'ASC_KEY_ID':'AB12CD34EF','ASC_ISSUER_ID':'11111111-2222-4333-8444-555555555555',
            'ASC_PRIVATE_KEY_BASE64':base64.b64encode(b'-----BEGIN PRIVATE KEY-----\nsynthetic fixture\n-----END PRIVATE KEY-----\n').decode(),
            'RUNNER_TEMP':str(tmp_path)}


def test_key_is_private_and_outside_checkout(tmp_path):
    data=env(tmp_path);path=key.prepare(data)
    assert path.parent==tmp_path/'lexmemoria-asc/private_keys'
    assert stat.S_IMODE(path.stat().st_mode)==0o600
    assert path.read_bytes()==base64.b64decode(data['ASC_PRIVATE_KEY_BASE64'])
    with pytest.raises(FileExistsError):key.prepare(data)


@pytest.mark.parametrize('field,value', [('ASC_KEY_ID','../bad'),('ASC_ISSUER_ID','not-a-uuid'),('ASC_PRIVATE_KEY_BASE64','%bad%'),('ASC_PRIVATE_KEY_BASE64',base64.b64encode(b'certificate not private key').decode())])
def test_reject_invalid_secrets_without_writing_key(tmp_path,field,value):
    data=env(tmp_path);data[field]=value
    with pytest.raises(ValueError):key.prepare(data)
    assert not list(tmp_path.rglob('*.p8'))


def test_upload_uses_exact_artifact_and_always_cleans_up():
    w=yaml.load((ROOT/'.github/workflows/apple-testflight-upload.yml').read_text(),Loader=yaml.BaseLoader)
    assert w['permissions']=={'contents':'read','actions':'read'}
    steps=w['jobs']['upload-testflight']['steps']
    download=next(s for s in steps if s.get('uses')=='actions/download-artifact@v4')
    assert download['with']['run-id']=='43105880193'
    assert download['with']['name']=='LexMemoria-1.0.0-SIGNED-IPA-3'
    assert steps[-1]['if']=='${{ always() }}'
    text='\n'.join(s.get('run','') for s in steps)
    assert '--upload-app' in text
    assert 'submit_for_review' not in text and 'distribute_external' not in text
    assert not any('upload-artifact' in s.get('uses','') for s in steps)
    for s in steps:
        if 'run' in s:subprocess.run(['bash','-n'],input=s['run'],text=True,check=True)
