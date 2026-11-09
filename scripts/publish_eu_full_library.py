#!/usr/bin/env python3
"""Publish a verified EU snapshot in bounded Git pushes; publish entry point last."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess

BRANCH='european-corpus-20261109'
REMOTE='https://github.com/AngelJRM01/LexMemoria.git'


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('source',type=Path);p.add_argument('--report',type=Path,required=True)
    p.add_argument('--checkout',type=Path,default=Path('/workspace/LexMemoria-europe-content'))
    args=p.parse_args();source=args.source.resolve();checkout=args.checkout.resolve()
    report=json.loads(args.report.read_text());manifest=json.loads((source/'catalogue-manifest.json').read_text())
    if report.get('integrity')!='passed' or any(report.get(k)!=manifest.get(k) for k in ('norms','records','sourceFiles')):
        raise ValueError('Complete successful validation report required')
    if not report.get('baseActRelationsVerified'):raise ValueError('Official consolidated base-act verification required')
    digest=hashlib.sha256((source/'catalogue-manifest.json').read_bytes()).hexdigest()
    if report.get('manifestSha256')!=digest:raise ValueError('Validation report belongs to another snapshot')
    checkout.mkdir(parents=True,exist_ok=True)
    def git(*args):
        return subprocess.run(['git','-C',str(checkout),*args],check=True,stdout=subprocess.PIPE,stderr=subprocess.PIPE).stdout.decode().strip()
    if not (checkout/'.git').exists():
        git('init','-b',BRANCH);git('remote','add','origin',REMOTE)
        git('config','user.name','LexMemoria');git('config','user.email','lexmemoria@users.noreply.github.com')
        git('config','gc.auto','0');git('config','pack.window','0');git('config','pack.threads','2')
    if git('branch','--show-current')!=BRANCH:raise ValueError('Wrong publication branch')
    batch=[];batch_bytes=0;published=0
    def flush():
        nonlocal batch,batch_bytes,published
        if not batch:return
        git('add','--',*batch)
        changed=subprocess.run(['git','-C',str(checkout),'diff','--cached','--quiet']).returncode
        if changed not in (0,1):raise RuntimeError('Cannot inspect staged files')
        if changed:
            git('commit','-m',f'Publish verified EU objects through batch {published+1}')
        # Also retries a previously committed but unsuccessful push.
        git('push','origin',f'HEAD:refs/heads/{BRANCH}')
        published+=1;print(json.dumps({'phase':'objects_published','batch':published,'files':len(batch),'bytes':batch_bytes}),flush=True)
        batch=[];batch_bytes=0
    for path in sorted((source/'objects').glob('*/*.gz')):
        if shutil.disk_usage(checkout).free<2*1024**3:raise RuntimeError('Insufficient publication space')
        relative=str(path.relative_to(source));target=checkout/relative
        if not target.exists():
            target.parent.mkdir(parents=True,exist_ok=True)
            try:os.link(path,target)
            except OSError:shutil.copyfile(path,target)
        elif hashlib.sha256(target.read_bytes()).digest()!=hashlib.sha256(path.read_bytes()).digest():raise ValueError('Conflicting published object')
        batch.append(relative);batch_bytes+=path.stat().st_size
        if batch_bytes>=150*1024**2 or len(batch)>=12000:flush()
    flush()
    shutil.copyfile(source/'catalogue-manifest.json',checkout/'catalogue-manifest.json')
    shutil.copyfile(args.report,checkout/'validation-report.json')
    (checkout/'README.md').write_text(
        '# LexMemoria — biblioteca europea completa\n\n'
        f"{manifest['records']:,} registros agrupados en {manifest['norms']:,} actos, con todas sus ediciones y {manifest['sourceFiles']:,} referencias de archivos originales.\n\n"
        'Fuente: Oficina de Publicaciones de la Unión Europea. Extracción automática, sin revisión jurídica manual. Las fichas sin texto recuperable conservan su fuente oficial.\n\n'
        'Cada objeto declara SHA-256 de bytes comprimidos, tamaño comprimido y expandido; páginas JSONL. El índice se publica después de todos sus objetos.\n')
    git('add','README.md','validation-report.json','catalogue-manifest.json')
    if subprocess.run(['git','-C',str(checkout),'diff','--cached','--quiet']).returncode:
        git('commit','-m','Activate independently verified complete European library')
    git('push','origin',f'HEAD:refs/heads/{BRANCH}')
    print(json.dumps({'phase':'published','commit':git('rev-parse','HEAD'),'manifestSha256':digest}),flush=True)

if __name__=='__main__':main()
