#!/usr/bin/env python3
"""Inspect a real macOS-built .app; no certificates or provider acceptance inferred."""
import argparse,hashlib,json,os,plistlib,subprocess,zipfile
from pathlib import Path


def inspect(app,kind,archive):
    info=plistlib.loads((app/'Info.plist').read_bytes())
    assert info['CFBundleIdentifier']=='es.lexmemoria.app'
    assert info['CFBundleShortVersionString']=='1.0.0' and str(info['CFBundleVersion'])=='20'
    expected='iPhoneOS' if kind=='device' else 'iPhoneSimulator'
    assert expected in info['CFBundleSupportedPlatforms']
    executable=app/info['CFBundleExecutable'];assert executable.is_file()
    with zipfile.ZipFile(archive) as zipped:
        assert zipped.testzip() is None
        assert 'Runner.app/Info.plist' in zipped.namelist()
    binary=subprocess.check_output(['file','-b',str(executable)],text=True).strip()
    assert 'Mach-O' in binary
    return {'platform':kind,'bundleIdentifier':info['CFBundleIdentifier'],
            'version':info['CFBundleShortVersionString'],'build':str(info['CFBundleVersion']),
            'minimumOS':info.get('MinimumOSVersion'),'sdk':info.get('DTSDKName'),
            'binary':binary,
            'sourceCommit':os.getenv('GITHUB_SHA'),'archive':archive.name,
            'bytes':archive.stat().st_size,'sha256':hashlib.sha256(archive.read_bytes()).hexdigest(),
            'distributionSigned':False,'installableOnPhysicalIPhoneWithoutSigning':False,
            'testFlightReady':False,'googleIosConfigured':False,'appleSignInConfigured':False,
            'physicalIPhoneTests':'not_run','nativeIosPersistenceTests':'not_run'}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('app',type=Path)
    parser.add_argument('--kind',choices=['device','simulator'],required=True)
    parser.add_argument('--archive',type=Path,required=True);parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args();report=inspect(args.app,args.kind,args.archive)
    args.output.parent.mkdir(parents=True,exist_ok=True);args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(report,indent=2))

if __name__=='__main__':main()
