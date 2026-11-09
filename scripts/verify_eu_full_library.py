#!/usr/bin/env python3
"""Independently verify every exported EU edition and bounded reading page."""
import argparse
from collections import Counter
import gzip
import hashlib
import json
from pathlib import Path
import re


def verify(root):
    root=Path(root).resolve();seen={};counts=Counter();celexes=set()
    def load(ref):
        relative=ref['path']
        if not 0<ref['bytes']<=64000000 or not 0<ref['expandedBytes']<=256000000:raise ValueError('Object exceeds client limits')
        if ref['encoding'] not in ('json','jsonl') or (ref['encoding']=='jsonl' and ref['expandedBytes']>5000000):raise ValueError('Unsupported client page')
        if not re.fullmatch(r'objects/[0-9a-f]{2}/[0-9a-f]{64}\.gz',relative):raise ValueError('Invalid object path')
        if relative in seen:
            if seen[relative]!=ref['sha256']:raise ValueError('Conflicting reference')
        data=(root/relative).read_bytes()
        if len(data)!=ref['bytes'] or hashlib.sha256(data).hexdigest()!=ref['sha256']:raise ValueError('Compressed integrity mismatch: '+relative)
        raw=gzip.decompress(data)
        if len(raw)!=ref['expandedBytes']:raise ValueError('Expanded integrity mismatch: '+relative)
        seen[relative]=ref['sha256']
        return [json.loads(line) for line in raw.splitlines()] if ref['encoding']=='jsonl' else json.loads(raw)
    manifest=json.loads((root/'catalogue-manifest.json').read_text())
    index=load(manifest['index']);ids=set()
    for item in index['items']:
        if item['id'] in ids:raise ValueError('Duplicate norm')
        ids.add(item['id']);norm=load(item['manifest'])
        if norm['id']!=item['id'] or norm['id']!='EU-'+norm['celex']:raise ValueError('Norm mismatch')
        if len(norm['versions'])!=item['editions']:raise ValueError('Edition count mismatch')
        for edition in norm['versions']:
            if edition['celex'] in celexes:raise ValueError('Duplicate edition')
            celexes.add(edition['celex']);counts['records']+=1
            for resource in edition['resources']:
                if not resource['url'].startswith('https://') or not re.fullmatch('[0-9a-f]{64}',resource['sha256']):raise ValueError('Invalid source provenance')
                counts['sourceFiles']+=1
            for ref in edition['readingDocuments']:
                document=load(ref);counts['readingDocuments']+=1
                if document['celex']!=edition['celex']:raise ValueError('Document edition mismatch')
                units=document['units'];cursor=0;expected=[]
                for unit in units:
                    if unit['firstParagraph']!=cursor:raise ValueError('Unit gap')
                    cursor+=unit['paragraphCount'];expected.append((cursor,unit['id']))
                if cursor!=document['paragraphs']:raise ValueError('Unit coverage mismatch')
                cursor=0;unit_index=0
                for page in document['pages']:
                    if page['firstParagraph']!=cursor:raise ValueError('Page gap')
                    records=load(page)
                    if len(records)!=page['paragraphs']:raise ValueError('Page count mismatch')
                    for record in records:
                        while unit_index<len(expected) and cursor>=expected[unit_index][0]:unit_index+=1
                        if unit_index>=len(expected) or record['unitId']!=expected[unit_index][1]:raise ValueError('Paragraph unit mismatch')
                        p=record['paragraph']
                        if not isinstance(p.get('text'),str) or not p.get('id'):raise ValueError('Invalid paragraph')
                        cursor+=1
                if cursor!=document['paragraphs']:raise ValueError('Page coverage mismatch')
                counts['paragraphs']+=cursor
        counts['norms']+=1
        if counts['norms']%1000==0:print(json.dumps(dict(counts)),flush=True)
    for key in ('norms','records','sourceFiles'):
        if counts[key]!=manifest[key]:raise ValueError('Incomplete '+key)
    return {**dict(counts),'objects':len(seen),'integrity':'passed','legalReview':'not_performed','manifestSha256':hashlib.sha256((root/'catalogue-manifest.json').read_bytes()).hexdigest()}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('root',type=Path);parser.add_argument('--report',type=Path,required=True);args=parser.parse_args()
    report=verify(args.root);args.report.parent.mkdir(parents=True,exist_ok=True);args.report.write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report),flush=True)

if __name__=='__main__':main()
