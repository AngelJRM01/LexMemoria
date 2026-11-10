"""Release preparation must never silently substitute preview credentials."""
import json
from pathlib import Path
import subprocess
import sys
import pytest

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'scripts'))
from build_play_bundle import NAMES, preflight
from firebase_config import google_configuration


def test_release_preflight_reports_missing_inputs_without_values(tmp_path):
    key=tmp_path/'owner.key';key.write_bytes(b'fixture-not-a-real-signing-key')
    env=dict(zip(NAMES,[str(key),'private-store-password','private-alias','private-key-password']))
    report=preflight(env,tmp_path/'absent.json')
    assert report['existingKeyOutsideRepository']
    assert not report['productionFirebaseConfigured'] and not report['readyForSignedBuild']
    assert not any(value in json.dumps(report) for value in env.values())
    assert preflight({},tmp_path/'absent.json')['missingSigningVariables']==list(NAMES)


def test_production_google_registration_rejects_preview_and_admin_credentials(tmp_path):
    admin=tmp_path/'admin.json';admin.write_text('{"type":"service_account","private_key":"never-accepted"}')
    with pytest.raises(ValueError,match='nunca una cuenta'):google_configuration(admin,'es.lexmemoria.app')
    preview=tmp_path/'preview.json';preview.write_text(json.dumps({'project_info':{'project_id':'lexmemoria-aa86a'},'client':[{'client_info':{'android_client_info':{'package_name':'es.lexmemoria.app.preview'}}}]}))
    with pytest.raises(ValueError,match='es.lexmemoria.app'):google_configuration(preview,'es.lexmemoria.app')


def test_default_bundle_command_refuses_missing_credentials_without_starting_flutter(monkeypatch):
    import build_play_bundle
    for name in NAMES:monkeypatch.delenv(name,raising=False)
    monkeypatch.setattr(sys,'argv',['build_play_bundle.py'])
    monkeypatch.setattr(subprocess,'call',lambda *a,**k:pytest.fail('Must not build without owner inputs'))
    with pytest.raises(SystemExit,match='pendientes'):build_play_bundle.main()
