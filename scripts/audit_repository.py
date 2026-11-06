#!/usr/bin/env python3
"""Offline inventory and bounded secret-pattern scan; not a vulnerability audit."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess
import yaml

ROOT=Path(__file__).resolve().parents[1]

def audit():
    requirements=ROOT/'backend/requirements.lock'
    flutter=ROOT/'mobile/pubspec.lock'
    components=[]
    for line in requirements.read_text().splitlines():
        if '==' in line and not line.startswith('#'):
            name,version=line.strip().split('==',1)
            components.append({'type':'library','name':name,'version':version,
                'purl':f'pkg:pypi/{name.lower()}@{version}'})
    for name,package in yaml.safe_load(flutter.read_text())['packages'].items():
        component={'type':'library','name':name,'properties':[
            {'name':'lexmemoria:source','value':str(package['source'])}]}
        if package['source']=='hosted':
            component.update({'version':str(package['version']),
                'purl':f"pkg:pub/{name}@{package['version']}"})
        else:
            component['properties'].append({'name':'lexmemoria:lockfileVersion',
                'value':str(package['version'])})
        components.append(component)
    paths=subprocess.check_output(['git','ls-files','--cached','--others','--exclude-standard','-z'],cwd=ROOT).decode().split('\0')
    patterns={
        'private_key_header':re.compile(rb'^-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----',re.M),
        'github_token':re.compile(rb'\bgh[pousr]_[A-Za-z0-9]{36,255}\b'),
        'aws_access_key_id':re.compile(rb'\bAKIA[A-Z0-9]{16}\b'),
    }
    code_hash=hashlib.sha256()
    code_count=0
    for relative in sorted(filter(None,paths)):
        path=ROOT/relative
        if (path.is_file() and relative.startswith(('backend/','mobile/','scripts/','.github/'))
            and path.suffix in ('.py','.dart','.yaml','.yml','.lock','.xml','.kt','.kts','.swift','.plist','.gradle','.properties')):
            code_hash.update(relative.encode()+b'\0'+hashlib.sha256(path.read_bytes()).digest())
            code_count+=1
    findings=[]
    for relative in filter(None,paths):
        path=ROOT/relative
        if not path.is_file() or path.stat().st_size>2_000_000:continue
        raw=path.read_bytes()
        if b'\x00' in raw:continue
        for kind,pattern in patterns.items():
            for match in pattern.finditer(raw):
                findings.append({'file':relative,'line':raw[:match.start()].count(b'\n')+1,
                    'kind':kind,'value':'REDACTED'})
    return {
        'sourceCommit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
        'workingTreeCodeSha256':code_hash.hexdigest(),'codeFilesFingerprinted':code_count,
        'lockfiles':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
                     for p in (requirements,flutter)},
        'sbom':{'bomFormat':'CycloneDX','specVersion':'1.6','version':1,'components':components},
        'secretPatternScan':{'scope':'tracked and unignored working-tree text files <= 2 MB; three patterns; no history or external secrets',
                             'findings':findings},
        'vulnerabilityDatabaseScan':{'status':'NOT_RUN',
            'limitation':'Offline inventory and pip check do not prove absence of vulnerable dependencies.'},
        'supplyChainRisks':['CI actions use version tags rather than immutable commit SHAs.',
            'Native Android/iOS transitive dependencies are not fully enumerated by these two lockfiles.'],
    }

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    result=audit();args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps({'components':len(result['sbom']['components']),
        'secretPatternFindings':len(result['secretPatternScan']['findings']),
        'vulnerabilityDatabaseScan':'NOT_RUN'}))
