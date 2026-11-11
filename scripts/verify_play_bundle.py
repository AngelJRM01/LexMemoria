#!/usr/bin/env python3
"""Validate bundle structure and Android metadata, without publishing it."""
import argparse,hashlib,json,os,struct,subprocess,zipfile
from pathlib import Path
import xml.etree.ElementTree as ET


def load_alignments(data):
    if data[:4]!=b'\x7fELF' or data[4]!=2:return []
    byte_order='<' if data[5]==1 else '>'
    offset=struct.unpack_from(byte_order+'Q',data,32)[0]
    size,count=struct.unpack_from(byte_order+'HH',data,54)
    result=[]
    for index in range(count):
        row=struct.unpack_from(byte_order+'IIQQQQQQ',data,offset+size*index)
        if row[0]==1:result.append(row[-1])
    return result


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('bundle',type=Path);parser.add_argument('--bundletool',type=Path,required=True)
    parser.add_argument('--report',type=Path,required=True);args=parser.parse_args()
    env=os.environ.copy();java=str(Path(env.get('JAVA_HOME','/workspace/tools/jdk/jdk-21.0.13+9'))/'bin/java')
    prefix=[java,'-jar',str(args.bundletool)]
    subprocess.run([*prefix,'validate','--bundle='+str(args.bundle)],check=True,capture_output=True)
    manifest=subprocess.check_output([*prefix,'dump','manifest','--bundle='+str(args.bundle),'--module=base'],text=True)
    xml=ET.fromstring(manifest);android='{http://schemas.android.com/apk/res/android}'
    application=xml.find('application');sdk=xml.find('uses-sdk')
    assert xml.attrib['package']=='es.lexmemoria.app'
    assert xml.attrib[android+'versionCode']=='18' and xml.attrib[android+'versionName']=='1.0.0'
    assert application.get(android+'debuggable','false')=='false'
    assert application.get(android+'allowBackup')=='false'
    libraries={}
    with zipfile.ZipFile(args.bundle) as archive:
        for name in archive.namelist():
            if name.endswith('.so') and ('/arm64-v8a/' in name or '/x86_64/' in name):
                alignments=load_alignments(archive.read(name))
                assert alignments and all(value>=16384 for value in alignments),name+' lacks static 16 KiB load alignment'
                libraries[name]={'loadSegmentAlignments':alignments,'static16KiBAlignment':True}
    report={'package':xml.attrib['package'],'versionName':xml.attrib[android+'versionName'],
            'versionCode':int(xml.attrib[android+'versionCode']),'debuggable':False,'allowBackup':False,
            'minSdk':int(sdk.get(android+'minSdkVersion')),'targetSdk':int(sdk.get(android+'targetSdkVersion')),
            'bundletoolValidation':'passed','native64BitLibraries':libraries,
            'static16KiBChecksOnly':True,'runtime16KiBDeviceAcceptance':'pending',
            'permissions':[p.get(android+'name') for p in xml.findall('uses-permission')],
            'sha256':hashlib.sha256(args.bundle.read_bytes()).hexdigest(),
            'googlePlaySubmission':'not_performed','physicalDeviceAcceptance':'pending'}
    args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:v for k,v in report.items() if k!='native64BitLibraries'}))

if __name__=='__main__':main()
