#!/usr/bin/env python3
"""Export every archived EU record as grouped editions and bounded reading pages."""
import argparse
from collections import defaultdict
from datetime import date,datetime,timezone
import gzip
import hashlib
import json
from pathlib import Path
import re
import shutil
import sqlite3
import sys
import time
import unicodedata
from urllib.parse import quote

BASE=Path('/workspace')
PIPELINE_REVISION='eu-full-reviewed-4'
BRANCH='european-corpus-20261109'
PUBLIC=f'https://raw.githubusercontent.com/AngelJRM01/LexMemoria/{BRANCH}/'
KINDS={'R':'Reglamento','L':'Directiva','D':'Decisión','H':'Recomendación','A':'Dictamen',
       'B':'Presupuesto','M':'Concentraciones','Y':'Otros actos','G':'Resolución'}


def group_celex(celex,parents=None):
    code=celex;edition='original';asof=None
    if code.startswith('0'):
        edition='consolidated'
        match=re.fullmatch(r'0(.+)-(\d{8})',code)
        if match:
            candidates=(parents or {}).get(celex,[])
            if len(candidates)==1:code=candidates[0]
            value=match[2]
            try:asof=date(int(value[:4]),int(value[4:6]),int(value[6:])).isoformat()
            except ValueError:asof=None
    correction=re.search(r'R\(\d+\)$',code)
    if correction:
        code=code[:correction.start()]
        if edition!='consolidated':edition='correction'
    return code,edition,asof


def kind_for_celex(code):
    if re.fullmatch(r'[CL]/\d{4}/\d+',code):return 'Anuncio'
    if code.startswith('0'):return 'Consolidación'
    if code.startswith('1'):return 'Tratado'
    if code.startswith('2'):return 'Acuerdo internacional'
    if code.startswith('4'):return 'Legislación complementaria'
    if code.startswith('5'):return 'Documento institucional'
    return KINDS.get(code[5:6],'Otros actos')



def year_for_celex(code):
    if code[1:5].isdigit():return code[1:5]
    match=re.match(r'[CL]/(\d{4})/',code)
    return match[1] if match else ''


def study_title_allowed(kind,title):
    if kind not in ('Reglamento','Directiva','Decisión','Tratado','Acuerdo internacional'):return False
    title=''.join(c for c in unicodedata.normalize('NFD',title.lower()) if unicodedata.category(c)!='Mn')
    change=re.search(r'por (?:el|la) que se (?:modifica|deroga|rectifica|corrige)',title)
    return change is None or bool(re.search(r'relativ[oa]|se establece',title[:change.start()]))


def encoded(value):return json.dumps(value,ensure_ascii=False,sort_keys=True,separators=(',',':')).encode()


class Exporter:
    def __init__(self,output,build_id=None):
        self.output=Path(output);self.output.mkdir(parents=True,exist_ok=True)
        self.db=sqlite3.connect(self.output/'build.sqlite3')
        self.db.execute('CREATE TABLE IF NOT EXISTS completed(base TEXT PRIMARY KEY,summary TEXT,manifest TEXT)')
        self.db.execute('CREATE TABLE IF NOT EXISTS build_settings(key TEXT PRIMARY KEY,value TEXT NOT NULL)')
        if build_id is not None:
            previous=self.db.execute("SELECT value FROM build_settings WHERE key='input_fingerprint'").fetchone()
            if previous is None or previous[0]!=build_id:
                # Preserve superseded derived indexes without resuming stale source output.
                with self.db:
                    if self.db.execute('SELECT COUNT(*) FROM completed').fetchone()[0]:
                        self.db.execute('ALTER TABLE completed RENAME TO completed_superseded_'+str(time.time_ns()))
                        self.db.execute('CREATE TABLE completed(base TEXT PRIMARY KEY,summary TEXT,manifest TEXT)')
                    self.db.execute("INSERT OR REPLACE INTO build_settings VALUES ('input_fingerprint',?)",(build_id,))


    def put(self,value,lines=False):
        raw=value if isinstance(value,bytes) else encoded(value)
        compressed=gzip.compress(raw,mtime=0);digest=hashlib.sha256(compressed).hexdigest()
        relative=f'objects/{digest[:2]}/{digest}.gz';target=self.output/relative;target.parent.mkdir(parents=True,exist_ok=True)
        if not target.exists():
            temp=target.with_suffix('.tmp');temp.write_bytes(compressed);temp.replace(target)
        if hashlib.sha256(target.read_bytes()).hexdigest()!=digest:raise ValueError('Export integrity mismatch')
        return {'path':relative,'sha256':digest,'bytes':len(compressed),'expandedBytes':len(raw),'encoding':'jsonl' if lines else 'json'}

    def copy_page(self,path,expected):
        # Preserve verified gzip pages rather than recompressing huge annexes.
        compressed=path.read_bytes();raw=gzip.decompress(compressed)
        if hashlib.sha256(raw).hexdigest()!=expected:raise ValueError('Source page integrity mismatch')
        digest=hashlib.sha256(compressed).hexdigest()
        relative=f'objects/{digest[:2]}/{digest}.gz';target=self.output/relative;target.parent.mkdir(parents=True,exist_ok=True)
        if not target.exists():
            temporary=target.with_suffix('.tmp');temporary.write_bytes(compressed);temporary.replace(target)
        if hashlib.sha256(target.read_bytes()).hexdigest()!=digest:raise ValueError('Export integrity mismatch')
        return {'path':relative,'sha256':digest,'bytes':len(compressed),'expandedBytes':len(raw),'encoding':'jsonl'}

    def reading(self,root,row):
        path=(root/row['path']).resolve()
        if root.resolve() not in path.parents:raise ValueError('Invalid structure path')
        raw=gzip.decompress(path.read_bytes())
        if hashlib.sha256(raw).hexdigest()!=path.name.split('.')[0]:raise ValueError('Structure integrity mismatch')
        doc=json.loads(raw);units=[];pages=[];pending=[];size=0;total=0
        if doc.get('storageLayout')=='paged-paragraphs':
            units=doc['units']
            for page in doc['pages']:
                ref=self.copy_page(root/page['path'],page['sha256'])
                pages.append({**ref,'firstParagraph':total,'paragraphs':page['paragraphs']});total+=page['paragraphs']
        else:
            def flush():
                nonlocal pending,size
                if pending:
                    pages.append({**self.put(b'\n'.join(pending)+b'\n',lines=True),'firstParagraph':total-len(pending),'paragraphs':len(pending)})
                    pending=[];size=0
            for unit in doc['units']:
                units.append({k:v for k,v in unit.items() if k!='paragraphs'} | {'firstParagraph':total,'paragraphCount':len(unit['paragraphs'])})
                for paragraph in unit['paragraphs']:
                    line=encoded({'unitId':unit['id'],'paragraph':paragraph})
                    if len(line)>4*1024**2:raise ValueError('Export paragraph exceeds supported size')
                    if pending and size+len(line)+1>512*1024:flush()
                    pending.append(line);size+=len(line)+1;total+=1
            flush()
        result={'schemaVersion':1,'celex':row['celex'],'sourceUrl':doc['sourceUrl'],
                'sourceHash':doc['rawSha256'],'units':units,'pages':pages,'paragraphs':total,
                'warnings':list(dict.fromkeys(doc.get('warnings',[])+doc.get('sourceQualityWarnings',[]))),'legalReview':'not_performed',
                'sourceCleaning':doc.get('sourceCleaning',{}),'sourceParser':doc.get('paragraphParser',''),
                'automaticStudyEligible':False}
        ref=self.put(result)
        ref['literalStudyAvailable']=doc.get('paragraphParser')=='eu-html-leaf-paragraphs-2' and not doc.get('warnings') and any(u['kind']=='article_candidate' for u in units)
        return ref


def previous_versions(output,source_fingerprint):
    """Reuse verified reading objects only when every source fingerprint matches."""
    path=Path(output)/'derived-history/v3-manifest.json'
    if not path.exists():return {}
    header=json.loads(path.read_text())
    if header.get('inputFingerprint')!=source_fingerprint:return {}
    report=json.loads((path.parent/'v3-validation.json').read_text())
    if report.get('integrity')!='passed' or report.get('manifestSha256')!=hashlib.sha256(path.read_bytes()).hexdigest():raise ValueError('Invalid prior reading validation')
    def load(ref):
        relative=ref['path']
        if not re.fullmatch(r'objects/[0-9a-f]{2}/[0-9a-f]{64}\.gz',relative):raise ValueError('Invalid prior object path')
        data=(Path(output)/relative).read_bytes()
        if len(data)!=ref['bytes'] or hashlib.sha256(data).hexdigest()!=ref['sha256']:raise ValueError('Prior object integrity mismatch')
        raw=gzip.decompress(data)
        if len(raw)!=ref['expandedBytes']:raise ValueError('Prior expanded length mismatch')
        return json.loads(raw)
    result={};items=load(header['index'])['items']
    for count,item in enumerate(items,1):
        for version in load(item['manifest'])['versions']:
            if version['celex'] in result:raise ValueError('Duplicate prior edition')
            result[version['celex']]=version
        if count%10000==0:print(json.dumps({'phase':'reuse_verified_readings','norms':count}),flush=True)
    if len(result)!=header['records']:raise ValueError('Prior edition coverage incomplete')
    return result


def ready(source_count):
    paths=['lexmemoria-eu-leaf-processed/processing.sqlite3','lexmemoria-eu-other-processed/processing.sqlite3',
           'lexmemoria-eu-reviewed-structures/structure.sqlite3','lexmemoria-eu-other-structures/structure.sqlite3']
    progress={}
    for name in paths:
        p=BASE/name
        if not p.exists():progress[name]=0;continue
        with sqlite3.connect(p.as_uri()+'?mode=ro',uri=True) as db:
            table='results' if name.endswith('structure.sqlite3') else 'processed'
            progress[name]=db.execute('SELECT COUNT(*) FROM '+table).fetchone()[0]
    matched=True
    for src,dest in [('lexmemoria-eu-leaf-processed','lexmemoria-eu-reviewed-structures'),('lexmemoria-eu-other-processed','lexmemoria-eu-other-structures')]:
        try:
            with sqlite3.connect((BASE/src/'processing.sqlite3').as_uri()+'?mode=ro',uri=True) as db:
                extracted=db.execute("SELECT COUNT(*) FROM processed WHERE state='extracted'").fetchone()[0]
                failed=db.execute("SELECT COUNT(*) FROM processed WHERE state='failed'").fetchone()[0]
            with sqlite3.connect((BASE/dest/'structure.sqlite3').as_uri()+'?mode=ro',uri=True) as db:
                candidates=db.execute("SELECT COUNT(*) FROM results WHERE state='candidate'").fetchone()[0]
                broken=db.execute("SELECT COUNT(*) FROM results WHERE state='failed'").fetchone()[0]
            progress[src+'_readable']=extracted;progress[dest+'_readable']=candidates
            with sqlite3.connect((BASE/src/'processing.sqlite3').as_uri()+'?mode=ro',uri=True) as db:
                checkpoint=db.execute('SELECT value FROM checkpoint WHERE id=1').fetchone()
                progress[src+'_checkpoint']=checkpoint[0] if checkpoint else 0
                db.execute('ATTACH DATABASE ? AS derived',((BASE/dest/'structure.sqlite3').as_uri()+'?mode=ro',))
                stale=db.execute("SELECT COUNT(*) FROM processed p LEFT JOIN derived.results r ON r.url=p.url WHERE p.state='extracted' AND (r.source_row IS NULL OR r.state!='candidate' OR r.source_output_hash IS NOT p.output_hash)").fetchone()[0]
                progress[dest+'_stale']=stale
            matched=matched and extracted==candidates and failed==0 and broken==0 and stale==0 and progress[src+'_checkpoint']>=source_count
        except sqlite3.OperationalError:matched=False
    try:
        with sqlite3.connect((BASE/'lexmemoria-eu-other-processed/processing.sqlite3').as_uri()+'?mode=ro',uri=True) as db:
            pending=db.execute("SELECT COUNT(*) FROM processed p LEFT JOIN recovery_attempts r ON r.url=p.url AND r.raw_hash=p.raw_hash WHERE p.state='deferred' AND p.error IN ('pdf_requires_ocr','pdf_conversion_failed','format_requires_converter','xml_size_limit','zip_text_size_limit','zip_requires_specific_parser') AND r.url IS NULL").fetchone()[0]
            progress['pending_format_recovery']=pending;matched=matched and pending==0
    except sqlite3.OperationalError:matched=False
    return all(progress[name]>=source_count for name in paths) and matched,progress


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,default=BASE/'lexmemoria-eu-full-distribution')
    parser.add_argument('--wait',action='store_true');args=parser.parse_args()
    with sqlite3.connect((BASE/'lexmemoria-eu-corpus/archive.sqlite3').as_uri()+'?mode=ro',uri=True) as source:
        source.row_factory=sqlite3.Row
        works=[dict(r) for r in source.execute('SELECT work,celex,status FROM eu_works ORDER BY celex')]
        documents=[dict(r) for r in source.execute('SELECT d.*,o.bytes FROM eu_documents d JOIN objects o ON o.hash=d.hash')]
    with sqlite3.connect((BASE/'lexmemoria-eu-titles/titles.sqlite3').as_uri()+'?mode=ro',uri=True) as db:
        titles={r[0]:json.loads(r[1]) for r in db.execute('SELECT work,title FROM titles')}
    if len(titles)!=len(works):raise ValueError('Official title coverage incomplete')
    while True:
        complete,progress=ready(len(documents))
        print(json.dumps({'phase':'waiting_inputs' if not complete else 'building','progress':progress}),flush=True)
        if complete:break
        if not args.wait:raise SystemExit(2)
        time.sleep(30)
    with sqlite3.connect((BASE/'lexmemoria-eu-parents/parents.sqlite3').as_uri()+'?mode=ro',uri=True) as db:
        parent_rows=db.execute('SELECT celex,parents,query_hash FROM parents').fetchall()
    parents={r[0]:json.loads(r[1]) for r in parent_rows}
    parent_evidence={r[0]:r[2] for r in parent_rows}
    if set(parents)!={w['celex'] for w in works if w['celex'].startswith('0')}:raise ValueError('Official base-act relation coverage incomplete')
    grouped=defaultdict(list);files=defaultdict(list)
    for work in works:
        base,edition,asof=group_celex(work['celex'],parents);grouped[base].append({**work,'editionKind':edition,'editionDate':asof})
    for document in documents:files[document['work']].append(document)
    structure_rows={}
    for folder in ['lexmemoria-eu-reviewed-structures','lexmemoria-eu-other-structures']:
        root=BASE/folder
        with sqlite3.connect((root/'structure.sqlite3').as_uri()+'?mode=ro',uri=True) as db:
            db.row_factory=sqlite3.Row
            for row in db.execute("SELECT * FROM results WHERE state='candidate'"):
                if row['url'] in structure_rows:raise ValueError('Duplicate derived source URL')
                structure_rows[row['url']]=(root,dict(row))
    def source_fingerprint(revision):
        digest=hashlib.sha256(encoded({'pipeline':revision,'works':works,'titles':titles}))
        for url,(root,row) in sorted(structure_rows.items()):
            digest.update(encoded([url,str(root),row['path'],row['source_output_hash']]))
        return digest
    fingerprint=source_fingerprint(PIPELINE_REVISION)
    fingerprint.update(encoded(parent_rows))
    cached_versions=previous_versions(args.output,source_fingerprint('eu-full-reviewed-3').hexdigest())
    export=Exporter(args.output,build_id=fingerprint.hexdigest())
    for base,editions in sorted(grouped.items()):
        if export.db.execute('SELECT 1 FROM completed WHERE base=?',(base,)).fetchone():continue
        if shutil.disk_usage(args.output).free<2*1024**3:raise RuntimeError('insufficient_disk')
        versions=[];variants=[]
        for edition in sorted(editions,key=lambda e:(e['editionDate'] or '',e['celex'])):
            official=titles[edition['work']];title=official[0] if official else edition['celex']
            variants.extend(official)
            cached=cached_versions.get(edition['celex'])
            refs=[];resources=[]
            for document in sorted(files[edition['work']],key=lambda d:tuple((0,int(p)) if p.isdigit() else (1,p) for p in re.split(r'(\d+)',d['url']))):
                resources.append({'url':document['url'].replace('http://','https://',1),'mime':document['content_type'],'sha256':document['hash'],'bytes':document['bytes']})
                structured=structure_rows.get(document['url'])
                if structured and cached is None:refs.append(export.reading(*structured))
            if cached is not None:refs=cached['readingDocuments']
            version={'celex':edition['celex'],'title':title,'kind':edition['editionKind'],'date':edition['editionDate'],
                     'sourceUrl':'https://eur-lex.europa.eu/legal-content/ES/TXT/?uri=CELEX:'+quote(edition['celex'],safe=''),
                     'readingDocuments':refs,'resources':resources,'archiveState':edition['status'],'legalReview':'not_performed'}
            if edition['celex'].startswith('0'):
                version.update(baseActCelex=base if not base.startswith('0') else None,
                    baseActCandidates=parents.get(edition['celex'],[]),
                    baseRelationQueryHash=parent_evidence.get(edition['celex']))
            versions.append(version)
        primary=next((e for e in editions if e['celex']==base),editions[0])
        official=titles[primary['work']];title=official[0] if official else base
        norm={'schemaVersion':1,'id':'EU-'+base,'celex':base,'title':title,'versions':versions,
              'kind':kind_for_celex(base),'legalReview':'not_performed','titleVariants':sorted(set(variants)),
              'attribution':'Fuente: Oficina de Publicaciones de la Unión Europea',
              'licenceUrl':'https://op.europa.eu/en/web/about-us/legal-notices/publications-office-reuse-policy'}
        ref=export.put(norm)
        summary={'id':norm['id'],'celex':base,'title':title,'kind':norm['kind'],
                 'editions':len(versions),'readableEditions':sum(bool(v['readingDocuments']) for v in versions),
                 'year':year_for_celex(base), 'manifest':ref,
                 'literalStudyEditions':sum(study_title_allowed(norm['kind'],title) and v['kind']!='correction' and any(d.get('literalStudyAvailable') for d in v['readingDocuments']) for v in versions)}
        with export.db:export.db.execute('INSERT INTO completed VALUES (?,?,?)',(base,json.dumps(summary,ensure_ascii=False),json.dumps(ref)))
        count=export.db.execute('SELECT COUNT(*) FROM completed').fetchone()[0]
        if count%500==0:print(json.dumps({'phase':'building','norms':count,'totalNorms':len(grouped)}),flush=True)
    items=[json.loads(r[0]) for r in export.db.execute('SELECT summary FROM completed ORDER BY base')]
    if len(items)!=len(grouped) or sum(n['editions'] for n in items)!=len(works):raise ValueError('Incomplete record coverage')
    index=export.put({'schemaVersion':1,'items':items})
    manifest={'schemaVersion':1,'pipelineRevision':PIPELINE_REVISION,'inputFingerprint':fingerprint.hexdigest(),'snapshot':'2026-11-09','baseUrl':PUBLIC,'index':index,'norms':len(items),
              'records':len(works),'sourceFiles':len(documents),'builtAt':datetime.now(timezone.utc).isoformat(),
              'legalReview':'not_performed','attribution':'Fuente: Oficina de Publicaciones de la Unión Europea'}
    temporary=args.output/'catalogue-manifest.tmp';temporary.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n');temporary.replace(args.output/'catalogue-manifest.json')
    print(json.dumps({'phase':'export_complete','norms':len(items),'records':len(works),'index':index}),flush=True)
    export.db.close()

if __name__=='__main__':main()
