"""Resumable Spanish EU legal corpus via the Publications Office's public CDM API.

Sectors 0 (consolidated texts) and 3 (legislation), all dated works exposed with
a Spanish expression. A primary textual manifestation is archived with all of
its items; metadata-only records and missing formats never count as full text.
"""
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone
import fcntl
import gzip
import hashlib
import io
import json
import os
from pathlib import Path
import shutil
import threading
import time
import tempfile
import zipfile
import zlib
from urllib.parse import urljoin, urlsplit, urlunsplit

import httpx
from .bulk import Archive, DownloadError, RateLimiter, utc

ROOT = '/workspace/lexmemoria-eu-corpus'
ENDPOINT = 'https://publications.europa.eu/webapi/rdf/sparql'
PREFIX = 'PREFIX cdm:<http://publications.europa.eu/ontology/cdm#> '
SCOPE = '''?w cdm:resource_legal_id_celex ?celex .
 FILTER(STRSTARTS(STR(?celex),"3") || STRSTARTS(STR(?celex),"0"))
 ?e cdm:expression_belongs_to_work ?w ; cdm:expression_uses_language
 <http://publications.europa.eu/resource/authority/language/SPA> .'''


class EuropeanArchive(Archive):
    def __init__(self, root=ROOT):
        super().__init__(root)
        with self.db() as db:
            db.executescript('''
            CREATE TABLE IF NOT EXISTS eu_works(work TEXT PRIMARY KEY,celex TEXT NOT NULL,
              items TEXT NOT NULL,status TEXT NOT NULL DEFAULT 'pending',attempts INTEGER NOT NULL DEFAULT 0,
              next_attempt REAL NOT NULL DEFAULT 0,error TEXT,finished_at TEXT);
            CREATE TABLE IF NOT EXISTS eu_documents(url TEXT PRIMARY KEY,work TEXT NOT NULL,
              hash TEXT NOT NULL,content_type TEXT NOT NULL,fetched_at TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS eu_pages(cursor TEXT PRIMARY KEY,hash TEXT NOT NULL,count INTEGER NOT NULL,fetched_at TEXT NOT NULL);
            CREATE INDEX IF NOT EXISTS eu_work_states ON eu_works(status);
            CREATE INDEX IF NOT EXISTS eu_due_work ON eu_works(attempts,work)
              WHERE status IN ('pending','retry');
            ''')
        self.rate = RateLimiter(.6)
        self.client = httpx.Client(timeout=httpx.Timeout(180, connect=20), follow_redirects=False,
                                  headers={'User-Agent':'LexMemoria/0.2 legal-source-archive (resumable)'})
        self.stop = threading.Event()
        self.rate.defer(max(0,self.setting('eu_source_resume_after',0)-time.time()))

    def defer_source(self, seconds):
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            row=db.execute("SELECT value FROM settings WHERE key='eu_source_resume_after'").fetchone()
            until=max(json.loads(row[0]) if row else 0,time.time()+seconds)
            db.execute('INSERT OR REPLACE INTO settings VALUES (?,?)',('eu_source_resume_after',json.dumps(until)))
        self.rate.defer(seconds)

    def fetch(self, url, params=None):
        for _ in range(6):
            parsed = urlsplit(url)
            if parsed.hostname not in ('publications.europa.eu','op.europa.eu'):
                raise DownloadError('redirect_domain_not_allowed')
            url = urlunsplit(('https',parsed.netloc,parsed.path,parsed.query,''))
            self.rate.acquire()
            try:
                with self.client.stream('GET',url,params=params) as response:
                    if response.is_redirect:
                        url = urljoin(str(response.url),response.headers['location']);params=None;continue
                    chunks=[];size=0
                    for chunk in response.iter_bytes():
                        size+=len(chunk)
                        if size>128*1024*1024:raise DownloadError('response_size_limit')
                        chunks.append(chunk)
                    raw=b''.join(chunks)
                    if response.status_code!=200 or not raw:
                        if raw:self.store(raw)
                        retry=response.status_code in (202,408,429) or response.status_code>=500
                        delay=response.headers.get('Retry-After','60')
                        pause=min(3600,int(delay)) if delay.isdigit() else 60
                        if retry:self.defer_source(pause)
                        raise DownloadError('http_'+str(response.status_code),retryable=retry,retry_after=pause)
                    return raw,response.headers.get('content-type','')
            except httpx.HTTPError as exc:
                self.defer_source(30)
                raise DownloadError('network_'+type(exc).__name__,retryable=True) from exc
        raise DownloadError('redirect_limit')

    def query(self, query):
        for attempt in range(6):
            try:
                raw,_=self.fetch(ENDPOINT,{'query':PREFIX+query,'format':'application/sparql-results+json'})
                break
            except DownloadError as exc:
                if not exc.retryable or attempt==5:raise
                if self.stop.wait(max(30,exc.retry_after)):raise
        digest=self.store(raw)
        try:
            rows=json.loads(raw)['results']['bindings']
            if not isinstance(rows,list):raise ValueError()
        except (ValueError,KeyError,TypeError) as exc:raise DownloadError('invalid_sparql_result') from exc
        return rows,digest

    def stream_blob(self, url, format_):
        """Archive oversized official documents without holding them in RAM."""
        for _ in range(6):
            parsed=urlsplit(url)
            if parsed.hostname not in ('publications.europa.eu','op.europa.eu'):
                raise DownloadError('redirect_domain_not_allowed')
            url=urlunsplit(('https',parsed.netloc,parsed.path,parsed.query,''))
            self.rate.acquire()
            try:
                with self.client.stream('GET',url) as response:
                    if response.is_redirect:
                        url=urljoin(url,response.headers['location']);continue
                    if response.status_code!=200:
                        retry=response.status_code in (202,408,429) or response.status_code>=500
                        if retry:self.defer_source(60)
                        raise DownloadError('http_'+str(response.status_code),retryable=retry,retry_after=60)
                    type_=response.headers.get('content-type','')
                    with tempfile.TemporaryFile(dir=self.root) as source:
                        digest=hashlib.sha256();size=0;prefix=b''
                        for chunk in response.iter_bytes(chunk_size=1024*1024):
                            if shutil.disk_usage(self.root).free<2*1024**3:
                                self.set('eu_blocker','insufficient_disk');self.stop.set()
                                raise DownloadError('insufficient_disk')
                            source.write(chunk);digest.update(chunk);size+=len(chunk)
                            if len(prefix)<1024:prefix=(prefix+chunk)[:1024]
                        source.seek(0)
                        is_zip=zipfile.is_zipfile(source)
                        if not valid_document(prefix,type_,format_) and not (is_zip and 'zip' in type_.lower()):
                            raise DownloadError('unexpected_document_format')
                        hash_=digest.hexdigest();folder=self.root/'objects'/hash_[:2];folder.mkdir(exist_ok=True)
                        target=folder/(hash_+'.xml.gz')
                        source.seek(0)
                        temporary=None
                        try:
                            with tempfile.NamedTemporaryFile(dir=folder,suffix='.tmp',delete=False) as output:
                                temporary=Path(output.name)
                                with gzip.GzipFile(filename='',mode='wb',fileobj=output,mtime=0) as compressed:
                                    while chunk:=source.read(1024*1024):
                                        if shutil.disk_usage(self.root).free<2*1024**3:
                                            self.set('eu_blocker','insufficient_disk');self.stop.set()
                                            raise DownloadError('insufficient_disk')
                                        compressed.write(chunk)
                                output.flush();os.fsync(output.fileno())
                            if target.exists():
                                with gzip.open(target,'rb') as existing:
                                    if hashlib.file_digest(existing,'sha256').hexdigest()!=hash_:
                                        raise DownloadError('existing_object_integrity')
                            else:
                                os.replace(temporary,target)
                                directory=os.open(folder,os.O_RDONLY)
                                try:os.fsync(directory)
                                finally:os.close(directory)
                        finally:
                            if temporary is not None:temporary.unlink(missing_ok=True)
                        with self.db() as db:db.execute('INSERT OR IGNORE INTO objects VALUES (?,?,?,?)',
                            (hash_,size,target.stat().st_size,str(target.relative_to(self.root))))
                        return hash_,type_
            except httpx.HTTPError as exc:
                self.defer_source(30)
                raise DownloadError('network_'+type(exc).__name__,retryable=True) from exc
        raise DownloadError('redirect_limit')

    def discovery(self, refresh=False):
        with (self.root/'eu-inventory.lock').open('a') as lock:
            while True:
                try:
                    fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
                    break
                except BlockingIOError:
                    if self.stop.wait(.5):return
            if self.stop.is_set():return
            if refresh:self.request_inventory_refresh()
            return self._discovery()

    def _discovery(self):
        if self.setting('eu_discovery_complete'):return
        if self.setting('eu_expected_works') is None:
            rows,_=self.query('SELECT (COUNT(DISTINCT ?w) AS ?count) WHERE {'+SCOPE+'}')
            self.set('eu_expected_works',int(rows[0]['count']['value']))
        cursor=self.setting('eu_cursor','')
        while not self.stop.is_set():
            after=' FILTER(STR(?w)>'+json.dumps(cursor)+') ' if cursor else ''
            query='SELECT DISTINCT ?w ?celex WHERE {'+SCOPE+after+'} ORDER BY ?w ?celex LIMIT 200'
            rows,digest=self.query(query)
            works={row['w']['value']:row['celex']['value'] for row in rows}
            with self.db() as db:
                known={r[0] for r in db.execute('SELECT work FROM eu_works WHERE work IN ('+
                    ','.join('?' for _ in works)+") AND status NOT IN ('metadata_only','unsupported_format')",list(works))} if works else set()
            # A reconciliation pass enumerates every ID but only retrieves
            # manifestations for new or previously unavailable works. Existing
            # archived files stay intact, even if a translation appears later.
            new_works={w:c for w,c in works.items() if w not in known}
            entries={work:[] for work in new_works}
            ordered=list(new_works)
            # Avoid GROUP_CONCAT: the provider fails on long annex lists. Retrieve
            # individual item rows in bounded batches, including every page.
            for start in range(0,len(ordered),50):
                batch=ordered[start:start+50]
                for work in batch:
                    if not work.startswith('http://publications.europa.eu/resource/cellar/') or any(c in work for c in '<>"\n\r'):
                        raise DownloadError('unknown_work_identifier')
                offset=0
                while True:
                    files_query='SELECT DISTINCT ?w ?type ?i WHERE { VALUES ?w {'+' '.join('<'+w+'>' for w in batch)+                      '} ?e cdm:expression_belongs_to_work ?w ; cdm:expression_uses_language <http://publications.europa.eu/resource/authority/language/SPA> . '+                      '?m cdm:manifestation_manifests_expression ?e ; cdm:manifestation_type ?type . ?i cdm:item_belongs_to_manifestation ?m . } ORDER BY ?w ?type ?i LIMIT 1000 OFFSET '+str(offset)
                    file_rows,_=self.query(files_query)
                    for row in file_rows:
                        work=row['w']['value']
                        if work not in entries:raise DownloadError('manifestation_work_mismatch')
                        entries[work].append({'type':row['type']['value'],'url':row['i']['value']})
                    if len(file_rows)<1000:break
                    offset+=len(file_rows)
            with self.db() as db:
                for work,celex in new_works.items():
                    selected=select_manifestation(entries[work])
                    state='pending' if selected else 'unsupported_format' if entries[work] else 'metadata_only'
                    db.execute("""INSERT INTO eu_works(work,celex,items,status) VALUES (?,?,?,?)
                        ON CONFLICT(work) DO UPDATE SET celex=excluded.celex,items=excluded.items,
                        status=excluded.status,error=NULL,next_attempt=0
                        WHERE eu_works.status IN ('metadata_only','unsupported_format')""",
                               (work,celex,json.dumps(selected or entries[work]),state))
                db.execute('INSERT OR REPLACE INTO eu_pages VALUES (?,?,?,?)',(cursor,digest,len(works),utc()))
            if not rows:
                self.set('eu_discovery_finished_at',utc())
                self.set('eu_discovery_complete',True);break
            next_cursor=rows[-1]['w']['value']
            if next_cursor<=cursor:raise DownloadError('non_advancing_catalogue')
            cursor=next_cursor;self.set('eu_cursor',cursor);self.status()

    def download_one(self, work=None):
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            # The status index otherwise makes SQLite sort the whole pending
            # queue for every file. The partial ordered index skips completed
            # works and directly selects the next eligible queued work.
            table='eu_works INDEXED BY eu_due_work' if work is None else 'eu_works'
            query="SELECT * FROM "+table+" WHERE status IN ('pending','retry') AND next_attempt<=?"
            values=[time.time()]
            if work is not None:query+=' AND work=?';values.append(work)
            row=db.execute(query+' ORDER BY attempts,work LIMIT 1',values).fetchone()
            if row is None:return False
            db.execute("UPDATE eu_works SET status='running',attempts=attempts+1 WHERE work=?",(row['work'],))
        try:
            for item in json.loads(row['items']):
                url=item['url']
                with self.db() as db:
                    if db.execute('SELECT 1 FROM eu_documents WHERE url=?',(url,)).fetchone():continue
                try:
                    raw,type_=self.fetch(url)
                except DownloadError as exc:
                    if exc.code!='response_size_limit':raise
                    digest,type_=self.stream_blob(url,item['type'])
                else:
                    digest=self.store(raw)
                    if not valid_document(raw,type_,item['type']):raise DownloadError('unexpected_document_format',payload=raw)
                with self.db() as db:db.execute('INSERT OR IGNORE INTO eu_documents VALUES (?,?,?,?,?)',(url,row['work'],digest,type_,utc()))
            if not self.has_primary_text(row['work']):
                raise DownloadError('manifestation_without_primary_text')
            with self.db() as db:
                db.execute("UPDATE eu_works SET status='complete',error=NULL,finished_at=? WHERE work=?",(utc(),row['work']))
        except DownloadError as exc:
            retry=exc.retryable and row['attempts']<7
            digest=self.store(exc.payload) if exc.payload else None
            with self.db() as db:
                db.execute('UPDATE eu_works SET status=?,error=?,next_attempt=? WHERE work=?',
                           ('retry' if retry else 'failed',exc.code,time.time()+max(exc.retry_after,30*2**row['attempts']),row['work']))
                db.execute('INSERT INTO incidents(stage,resource,code,hash,at) VALUES (?,?,?,?,?)',('eu_document',row['work'],exc.code,digest,utc()))
            if exc.code in ('http_401','http_403','redirect_domain_not_allowed'):
                self.set('eu_blocker',exc.code);self.stop.set()
        return True

    def has_primary_text(self, work):
        with self.db() as db:
            documents=list(db.execute('SELECT d.content_type,o.path FROM eu_documents d JOIN objects o ON o.hash=d.hash WHERE d.work=?',(work,)))
        if any(any(t in d['content_type'].lower() for t in ('html','xml','pdf','msword')) for d in documents):return True
        for document in documents:
            if 'zip' not in document['content_type'].lower():continue
            try:
                with gzip.open(self.root/document['path'],'rb') as source,zipfile.ZipFile(source) as package:
                    for name in package.namelist():
                        suffix=Path(name).suffix.lower()
                        if suffix not in ('.xml','.html','.xhtml','.htm','.pdf'):continue
                        with package.open(name) as member:prefix=member.read(1024).lstrip()
                        if (suffix=='.pdf' and prefix.startswith(b'%PDF-')) or (suffix!='.pdf' and prefix.startswith(b'<')):
                            return True
            except (OSError,ValueError,EOFError,zlib.error,zipfile.BadZipFile):continue
        return False

    def requeue_supported(self):
        """Retry only unsupported records whose preserved format is now supported."""
        changed=0
        with self.db() as db:
            for row in db.execute("SELECT work,items FROM eu_works WHERE status='unsupported_format'").fetchall():
                selected=select_manifestation(json.loads(row['items']))
                if selected:
                    db.execute("UPDATE eu_works SET items=?,status='pending',error=NULL,next_attempt=0 WHERE work=? AND status='unsupported_format'",
                               (json.dumps(selected),row['work']))
                    changed+=1
        return changed

    def reconcile_inventory(self):
        rows,digest=self.query('SELECT (COUNT(DISTINCT ?w) AS ?count) WHERE {'+SCOPE+'}')
        if len(rows)!=1:raise DownloadError('invalid_inventory_count')
        count=int(rows[0]['count']['value'])
        if count<0:raise DownloadError('invalid_inventory_count')
        with self.db() as db:local=db.execute('SELECT count(*) FROM eu_works').fetchone()[0]
        initial=self.setting('eu_initial_expected_works',self.setting('eu_expected_works'))
        self.set('eu_initial_expected_works',initial)
        result={'initial_source_count':initial,'current_source_count':count,'local_count':local,
                'consistent':self.setting('eu_discovery_complete') is True and count==local,
                'response_hash':digest,'observed_at':utc()}
        self.set('eu_inventory_reconciliation',result)
        if result['consistent']:self.set('eu_expected_works',count)
        return result

    def request_inventory_refresh(self):
        # Only the supervisor with no active worker calls this. No source rows
        # or objects are removed; the next discovery reuses known work IDs.
        self.set('eu_cursor','')
        self.set('eu_discovery_complete',False)

    def requeue_transient_failures(self, at=None):
        at=time.time() if at is None else at
        changed=0
        with self.db() as db:
            for row in db.execute("SELECT work,error,attempts FROM eu_works WHERE status='failed' AND next_attempt<=?",(at,)).fetchall():
                if not transient_error(row['error']):continue
                db.execute("UPDATE eu_works SET status='retry',attempts=0,next_attempt=? WHERE work=? AND status='failed'",(at+300,row['work']))
                db.execute('INSERT INTO incidents(stage,resource,code,hash,at) VALUES (?,?,?,?,?)',
                    ('eu_retry_round',row['work'],str(row['error'])+':after_'+str(row['attempts']),None,utc()))
                changed+=1
        return changed

    def status(self):
        with self.db() as db:
            states={r['status']:r['n'] for r in db.execute('SELECT status,count(*) n FROM eu_works GROUP BY status')}
            documents=db.execute('SELECT count(*) FROM eu_documents').fetchone()[0]
        expected=self.setting('eu_expected_works')
        reconciliation=self.setting('eu_inventory_reconciliation')
        consistent=reconciliation is None or reconciliation.get('consistent') is True
        result={'source':'Publications Office CDM','scope':'CELEX sectors 0 and 3 with a Spanish expression; primary textual manifestation',
                'expected_works':expected,'identified':sum(states.values()),'states':states,'documents':documents,
                'inventory_complete':bool(self.setting('eu_discovery_complete')),
                'all_available_records_archived':consistent and bool(expected) and self.setting('eu_discovery_complete') is True and states.get('complete',0)+states.get('metadata_only',0)==expected and sum(states.values())==expected,
                'all_texts_archived':consistent and bool(expected) and self.setting('eu_discovery_complete') is True and states.get('complete',0)==expected and sum(states.values())==expected,
                'blocker':self.setting('eu_blocker'),'observed_at':utc(),'legal_review':'not_performed',
                'inventory_reconciliation':reconciliation,
                'attribution':'Fuente: Oficina de Publicaciones de la Unión Europea',
                'licence_url':'https://op.europa.eu/en/web/about-us/legal-notices/publications-office-reuse-policy'}
        temporary=self.root/('status.'+str(threading.get_ident())+'.tmp')
        temporary.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n');temporary.replace(self.root/'status.json')
        return result

    def verify(self):
        errors=[]
        with self.db() as db:
            db.execute('BEGIN')
            objects=list(db.execute('SELECT * FROM objects'))
            documents=list(db.execute('SELECT d.*,o.path FROM eu_documents d LEFT JOIN objects o ON o.hash=d.hash'))
            works=list(db.execute('SELECT * FROM eu_works'))
        for object_ in objects:
            try:
                path=(self.root/object_['path']).resolve();path.relative_to(self.root/'objects')
                digest=hashlib.sha256();size=0
                with gzip.open(path,'rb') as source:
                    while chunk:=source.read(1024*1024):digest.update(chunk);size+=len(chunk)
                if digest.hexdigest()!=object_['hash'] or size!=object_['bytes']:raise ValueError('digest')
            except (OSError,ValueError,EOFError,zlib.error):errors.append({'hash':object_['hash'],'code':'object_integrity'})
        result={'verified_at':utc(),'objects_checked':len(objects),'errors':errors}
        by_work={}
        for document in documents:
            by_work.setdefault(document['work'],set()).add(document['url'])
            if document['path'] is None:
                result['errors'].append({'url':document['url'],'code':'missing_eu_object'})
        for work in works:
            if work['status']=='complete':
                wanted={i['url'] for i in json.loads(work['items'])}
                if not wanted or not wanted.issubset(by_work.get(work['work'],set())):
                    result['errors'].append({'work':work['work'],'code':'missing_eu_item'})
        result.update(verification_passed=not result['errors'],eu_documents_checked=len(documents),
                      eu_works_checked=len(works),eu_status=self.status())
        result['download_complete']=bool(result['eu_status']['all_texts_archived']) and len(works)==result['eu_status']['expected_works'] and all(w['status']=='complete' for w in works)
        (self.root/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
        return result

    def run(self):
        import signal
        for signum in (signal.SIGINT,signal.SIGTERM):
            signal.signal(signum,lambda *_:self.stop.set())
        with (self.root/'eu-worker.lock').open('a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            if self.setting('eu_blocker'):raise RuntimeError('Resolve the recorded EU blocker before resuming')
            self.set('eu_started',{'pid':__import__('os').getpid(),'at':utc()})
            with self.db() as db:db.execute("UPDATE eu_works SET status='pending' WHERE status='running'")
            with ThreadPoolExecutor(max_workers=3) as pool:
                discovery=pool.submit(self.discovery)
                def worker():
                    while not self.stop.is_set():
                        if shutil.disk_usage(self.root).free<2*1024**3:
                            self.set('eu_blocker','insufficient_disk');self.stop.set();break
                        if not self.download_one():
                            with self.db() as db:
                                unfinished=db.execute("SELECT count(*) FROM eu_works WHERE status IN ('pending','retry','running')").fetchone()[0]
                            if discovery.done() and unfinished==0:break
                            if discovery.done() and discovery.exception():break
                            self.stop.wait(2)
                        self.status()
                def supervised_worker():
                    try:worker()
                    except Exception as exc:
                        self.set('eu_blocker','worker_'+type(exc).__name__);self.stop.set();raise
                workers=[pool.submit(supervised_worker) for _ in range(2)]
                try:discovery.result()
                except Exception as exc:
                    if not self.stop.is_set():self.set('eu_blocker','discovery_'+type(exc).__name__+':'+str(exc))
                    self.stop.set()
                for future in workers:future.result()
            self.set('eu_stopped',utc());print(json.dumps(self.status(),ensure_ascii=False),flush=True)


def select_manifestation(items):
    for format_ in ('xhtml','html','fmx4','pdfa1a','pdfa1b','pdfa2a','pdfa2b','pdf','doc'):
        selected={i['url']:i for i in items if i['type'].lower()==format_}
        if selected:return list(selected.values())
    return []


def transient_error(code):
    if not isinstance(code,str):return False
    if code.startswith('http_'):
        value=code[5:]
        return value.isdigit() and (int(value) in (408,425,429) or 500<=int(value)<=599)
    return code in {'network_'+name for name in ('ConnectError','ReadError','WriteError',
        'ConnectTimeout','ReadTimeout','WriteTimeout','PoolTimeout','ProxyError','RemoteProtocolError')}


def valid_document(raw, content_type, format_):
    start=raw.lstrip()[:1000].lower()
    mime=content_type.split(';')[0].lower().strip()
    # The provider's HTML/Formex manifestations include images and stylesheets.
    if mime=='image/jpeg':return raw.startswith(b'\xff\xd8\xff')
    if mime=='image/png':return raw.startswith(b'\x89PNG\r\n\x1a\n')
    if mime=='image/gif':return raw.startswith((b'GIF87a',b'GIF89a'))
    if mime=='image/svg+xml':return b'<svg' in start
    if mime=='text/css':return b'<html' not in start and bool(raw.strip())
    if mime in ('application/zip','application/x-zip-compressed'):return zipfile.is_zipfile(io.BytesIO(raw))
    if format_=='doc':return mime=='application/msword' and raw.startswith(b'\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1')
    if format_.startswith('pdf'):return raw.startswith(b'%PDF-')
    if format_ in ('xhtml','html'):return ('html' in content_type.lower()) and (b'<html' in start or b'<!doctype html' in start)
    if format_=='fmx4':return ('xml' in content_type.lower()) and start.startswith(b'<')
    return False


if __name__=='__main__':
    import argparse
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('command',choices=('run','status','verify','requeue-supported','reconcile-inventory','refresh-inventory'));p.add_argument('--root',default=ROOT)
    args=p.parse_args();archive=EuropeanArchive(args.root)
    if args.command=='run':
        archive.run()
        if not archive.status()['all_available_records_archived']:raise SystemExit(2)
    elif args.command=='verify':
        result=archive.verify();print(json.dumps(result,ensure_ascii=False))
        if not result['verification_passed']:raise SystemExit(2)
    elif args.command=='requeue-supported':print(json.dumps({'requeued':archive.requeue_supported()}))
    elif args.command=='reconcile-inventory':print(json.dumps(archive.reconcile_inventory()))
    elif args.command=='refresh-inventory':
        archive.discovery(refresh=True)
        print(json.dumps(archive.reconcile_inventory()))
    else:print(json.dumps(archive.status(),ensure_ascii=False))
