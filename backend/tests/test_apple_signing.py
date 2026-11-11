"""Distribution preflight rejects incorrect identity/profile before an archive is built."""
import datetime as dt
import hashlib
import importlib.util
from pathlib import Path
import pytest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('apple_signing',ROOT/'scripts/prepare_apple_signing.py')
signing=importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)
NOW=dt.datetime(2026,11,11,tzinfo=dt.timezone.utc)
CERT=b'synthetic-public-certificate'
FINGERPRINT=hashlib.sha1(CERT).hexdigest().upper()


def profile():
    return {'ExpirationDate':dt.datetime(2027,11,11),'TeamIdentifier':[signing.TEAM],
            'Entitlements':{'application-identifier':signing.TEAM+'.'+signing.BUNDLE,'get-task-allow':False},
            'UUID':'11111111-2222-3333-4444-555555555555','DeveloperCertificates':[CERT]}


def test_matching_profile_and_imported_private_identity():
    p=profile()
    assert signing.validate(p,'1) '+FINGERPRINT+' "Apple Distribution"',NOW)==(p['UUID'],FINGERPRINT)


@pytest.mark.parametrize('change',[
    lambda p:p.update(ExpirationDate=dt.datetime(2025,1,1)),
    lambda p:p.update(TeamIdentifier=['WRONGTEAM']),
    lambda p:p['Entitlements'].update({'application-identifier':signing.TEAM+'.another.app'}),
    lambda p:p['Entitlements'].update({'get-task-allow':True}),
    lambda p:p.update(ProvisionedDevices=['device']),
    lambda p:p.update(ProvisionsAllDevices=True),
    lambda p:p.update(UUID='../invalid'),
    lambda p:p.update(DeveloperCertificates=[b'other-cert']),
])
def test_reject_unsafe_or_mismatched_profile(change):
    p=profile();change(p)
    with pytest.raises(ValueError):signing.validate(p,FINGERPRINT,NOW)


def test_project_changes_only_runner_and_leaves_test_bundle_automatic():
    source=(ROOT/'mobile/ios/Runner.xcodeproj/project.pbxproj').read_text()
    configured=signing.configure_project(source,profile()['UUID'],FINGERPRINT)
    assert configured.count('PROVISIONING_PROFILE_SPECIFIER =')==3
    assert configured.count('CODE_SIGN_STYLE = Automatic;')==source.count('CODE_SIGN_STYLE = Automatic;')
    assert signing.configure_project(configured,profile()['UUID'],FINGERPRINT)==configured
    assert 'ITSAppUsesNonExemptEncryption' not in configured
