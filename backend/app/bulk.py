"""Resumable archival download of the complete observed BOE consolidated catalogue.

Raw official responses are immutable, gzip-compressed SHA-256 objects outside Git.
An archived source is never labelled as legally reviewed or as educational content.
"""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import date, datetime, timezone
import fcntl
import gzip
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import threading
import time
import tempfile
import zlib
from zoneinfo import ZoneInfo
from urllib.parse import urlencode

from defusedxml import ElementTree as ET
from defusedxml.common import DefusedXmlException
import httpx

BASE = 'https://www.boe.es/datosabiertos/api'
OFFICIAL_ID = re.compile(r'^[A-Z][A-Z0-9]{1,11}-[A-Za-z]-\d{4}-\d+$')
LICENCE = 'https://www.boe.es/informacion/aviso_legal/index.php#reutilizacion'


def madrid_today():
    return datetime.now(ZoneInfo('Europe/Madrid')).date().isoformat()


def utc():
    return datetime.now(timezone.utc).isoformat()


class DownloadError(Exception):
    def __init__(self, code, *, retryable=False, retry_after=0, payload=None):
        super().__init__(code)
        self.code, self.retryable, self.retry_after = code, retryable, retry_after
        self.payload = payload


class RateLimiter:
    def __init__(self, interval=.5):
        self.interval = interval
        self.next_at = 0.0
        self.lock = threading.Lock()

    def acquire(self):
        with self.lock:
            delay = self.next_at - time.monotonic()
            if delay > 0:
                time.sleep(delay)
            self.next_at = time.monotonic() + self.interval

    def defer(self, seconds):
        with self.lock:
            self.next_at = max(self.next_at, time.monotonic() + seconds)


class OfficialClient:
    def __init__(self, interval=.5, client=None):
        self.rate = RateLimiter(interval)
        self.client = client or httpx.Client(
            timeout=httpx.Timeout(120, connect=20), follow_redirects=False,
            limits=httpx.Limits(max_connections=4, max_keepalive_connections=4),
            headers={'Accept': 'application/xml',
                     'User-Agent': 'LexMemoria/0.1 legal-source-archive (resumable; max 2 requests/second)'})

    def fetch(self, path):
        self.rate.acquire()
        try:
            with self.client.stream('GET', BASE + path) as response:
                error_payload = None
                if response.status_code != 200:
                    error_chunks, error_size = [], 0
                    for chunk in response.iter_bytes():
                        error_size += len(chunk)
                        if error_size > 1024 * 1024: break
                        error_chunks.append(chunk)
                    error_payload = b''.join(error_chunks)
                    retry_after = response.headers.get('Retry-After', '')
                    seconds = min(int(retry_after), 3600) if retry_after.isdigit() else 60
                    if response.status_code == 429 or response.status_code >= 500:
                        self.rate.defer(seconds)
                    raise DownloadError('http_' + str(response.status_code),
                        retryable=response.status_code in (408, 429) or response.status_code >= 500,
                        retry_after=seconds, payload=error_payload)
                chunks, size = [], 0
                for chunk in response.iter_bytes():
                    size += len(chunk)
                    if size > 128 * 1024 * 1024:
                        raise DownloadError('response_size_limit')
                    chunks.append(chunk)
                return b''.join(chunks), {k: response.headers[k] for k in (
                    'content-type', 'etag', 'last-modified') if k in response.headers}
        except httpx.HTTPError as exc:
            self.rate.defer(30)
            raise DownloadError('network_' + type(exc).__name__, retryable=True) from exc


def xml_root(raw):
    try:
        root = ET.fromstring(raw)
    except (ET.ParseError, DefusedXmlException, ValueError) as exc:
        raise DownloadError('unsafe_or_invalid_xml') from exc
    code = root.findtext('./status/code')
    if code != '200':
        raise DownloadError('xml_status_' + str(code), retryable=code == '429' or bool(code and code.startswith('5')))
    return root


class Archive:
    def __init__(self, root):
        self.root = Path(root).resolve()
        self.root.mkdir(parents=True, exist_ok=True)
        (self.root / 'objects').mkdir(exist_ok=True)
        with self.db() as db:
            db.executescript('''
            CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY,value TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS objects(hash TEXT PRIMARY KEY, bytes INTEGER NOT NULL,
                compressed_bytes INTEGER NOT NULL,path TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS pages(id INTEGER PRIMARY KEY,pass INTEGER NOT NULL,offset INTEGER NOT NULL,
                count INTEGER NOT NULL,hash TEXT NOT NULL,source_url TEXT NOT NULL,fetched_at TEXT NOT NULL,
                UNIQUE(pass,offset));
            CREATE TABLE IF NOT EXISTS inventory(id TEXT PRIMARY KEY,metadata TEXT NOT NULL,
                source_updated TEXT,status TEXT NOT NULL DEFAULT 'pending',attempts INTEGER NOT NULL DEFAULT 0,
                next_attempt REAL NOT NULL DEFAULT 0,lease_until REAL NOT NULL DEFAULT 0,
                hash TEXT,error TEXT,first_seen TEXT NOT NULL,last_seen TEXT NOT NULL,finished_at TEXT);
            CREATE INDEX IF NOT EXISTS inventory_work ON inventory(status,next_attempt,id);
            CREATE TABLE IF NOT EXISTS snapshots(id TEXT NOT NULL,hash TEXT NOT NULL,
                source_url TEXT NOT NULL,fetched_at TEXT NOT NULL,blocks INTEGER NOT NULL,
                versions INTEGER NOT NULL,has_analysis INTEGER NOT NULL,has_eli INTEGER NOT NULL,
                headers TEXT NOT NULL,PRIMARY KEY(id,hash));
            CREATE TABLE IF NOT EXISTS incidents(id INTEGER PRIMARY KEY,stage TEXT NOT NULL,
                resource TEXT NOT NULL,code TEXT NOT NULL,hash TEXT,at TEXT NOT NULL);
            ''')

    def db(self):
        db = sqlite3.connect(self.root / 'archive.sqlite3', timeout=30)
        db.row_factory = sqlite3.Row
        db.execute('PRAGMA journal_mode=WAL')
        db.execute('PRAGMA busy_timeout=30000')
        return db

    def setting(self, key, default=None):
        with self.db() as db:
            row = db.execute('SELECT value FROM settings WHERE key=?', (key,)).fetchone()
        return json.loads(row['value']) if row else default

    def set(self, key, value):
        with self.db() as db:
            db.execute('INSERT OR REPLACE INTO settings VALUES (?,?)', (key, json.dumps(value)))

    def store(self, raw):
        digest = hashlib.sha256(raw).hexdigest()
        relative = Path('objects') / digest[:2] / (digest + '.xml.gz')
        path = self.root / relative
        path.parent.mkdir(exist_ok=True)
        if path.exists():
            try:
                if hashlib.sha256(gzip.decompress(path.read_bytes())).hexdigest() != digest:
                    raise ValueError('digest')
            except (OSError, ValueError, EOFError, zlib.error):
                raise DownloadError('existing_object_integrity')
        else:
            compressed = gzip.compress(raw, mtime=0)
            with tempfile.NamedTemporaryFile(dir=path.parent, prefix=path.name+'.', suffix='.tmp', delete=False) as file:
                temporary = Path(file.name)
                file.write(compressed); file.flush(); os.fsync(file.fileno())
            os.replace(temporary, path)
            directory = os.open(path.parent, os.O_RDONLY)
            try: os.fsync(directory)
            finally: os.close(directory)
        with self.db() as db:
            db.execute('INSERT OR IGNORE INTO objects VALUES (?,?,?,?)',
                       (digest, len(raw), path.stat().st_size, str(relative)))
        return digest

    def add_page(self, raw, offset, pass_number, source_url):
        digest = self.store(raw)
        root = xml_root(raw)
        data = root.find('./data')
        if data is None:
            raise DownloadError('catalogue_shape')
        records = []
        for item in data.findall('./item'):
            identifier = item.findtext('identificador')
            if not identifier or not OFFICIAL_ID.fullmatch(identifier):
                raise DownloadError('catalogue_unknown_identifier')
            fields = {n.tag: ''.join(n.itertext()).strip() for n in item}
            records.append((identifier, fields))
        with self.db() as db:
            old = db.execute('SELECT hash FROM pages WHERE pass=? AND offset=?', (pass_number, offset)).fetchone()
            if old and old['hash'] != digest:
                raise DownloadError('catalogue_page_changed')
            for identifier, fields in records:
                db.execute('''INSERT INTO inventory(id,metadata,source_updated,first_seen,last_seen)
                    VALUES (?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET metadata=excluded.metadata,
                    source_updated=CASE WHEN COALESCE(excluded.source_updated,'')>COALESCE(inventory.source_updated,'')
                        THEN excluded.source_updated ELSE inventory.source_updated END,
                    status=CASE WHEN COALESCE(excluded.source_updated,'')>COALESCE(inventory.source_updated,'')
                        AND inventory.status IN ('complete','metadata_only') THEN 'pending' ELSE inventory.status END,
                    attempts=CASE WHEN COALESCE(excluded.source_updated,'')>COALESCE(inventory.source_updated,'')
                        AND inventory.status IN ('complete','metadata_only') THEN 0 ELSE inventory.attempts END,
                    last_seen=excluded.last_seen''',
                    (identifier, json.dumps(fields, ensure_ascii=False), fields.get('fecha_actualizacion'), utc(), utc()))
            db.execute('INSERT OR IGNORE INTO pages(pass,offset,count,hash,source_url,fetched_at) VALUES (?,?,?,?,?,?)',
                       (pass_number, offset, len(records), digest, source_url, utc()))
        return len(records)

    def discover(self, client, *, day=None, pass_number=1, page_size=1000):
        day = day or madrid_today()
        date.fromisoformat(day)
        cutoff = self.setting('catalogue_day')
        if cutoff is not None and cutoff != day:
            raise ValueError('Use a new archive for a different inventory cutoff')
        self.set('catalogue_day', day)
        self.set('licence_url', LICENCE)
        key = 'discovery_' + str(pass_number)
        progress = self.setting(key, {'offset': 0, 'complete': False})
        if progress['complete']:
            return progress
        while True:
            offset = progress['offset']
            path = '/legislacion-consolidada?' + urlencode({'offset': offset, 'limit': page_size, 'to': day.replace('-', '')})
            raw, _ = client.fetch(path)
            count = self.add_page(raw, offset, pass_number, BASE + path)
            progress = {'offset': offset + count, 'complete': count < page_size,
                        'finished_at': utc(), 'last_page_count': count}
            self.set(key, progress)
            if progress['complete']:
                return progress

    def claim(self):
        now = time.time()
        with self.db() as db:
            db.execute('BEGIN IMMEDIATE')
            row = db.execute('''SELECT * FROM inventory WHERE
                (status IN ('pending','retry') AND next_attempt<=?) OR (status='running' AND lease_until<?)
                ORDER BY attempts,id LIMIT 1''', (now, now)).fetchone()
            if row is None:
                return None
            db.execute("UPDATE inventory SET status='running',attempts=attempts+1,lease_until=? WHERE id=?", (now+600, row['id']))
            return dict(row)

    def fetch_one(self, client):
        row = self.claim()
        if row is None:
            return False
        identifier = row['id']; raw = digest = None
        path = '/legislacion-consolidada/id/' + identifier
        try:
            raw, headers = client.fetch(path)
            digest = self.store(raw)
            root = xml_root(raw)
            if root.findtext('./data/metadatos/identificador') != identifier:
                raise DownloadError('document_identifier_mismatch')
            blocks = root.findall('./data/texto//bloque')
            versions = sum(len(b.findall('./version')) for b in blocks)
            if len({b.get('id') for b in blocks}) != len(blocks) or any(not b.get('id') or not b.findall('./version') for b in blocks):
                raise DownloadError('document_incomplete_blocks')
            status = 'complete' if blocks else 'metadata_only'
            actual_update = root.findtext('./data/metadatos/fecha_actualizacion')
            headers['_source_updated'] = actual_update
            with self.db() as db:
                expected = db.execute('SELECT source_updated FROM inventory WHERE id=?',(identifier,)).fetchone()['source_updated']
                if expected and actual_update and actual_update < expected:
                    raise DownloadError('source_changed_during_download',retryable=True)
                db.execute('INSERT OR IGNORE INTO snapshots VALUES (?,?,?,?,?,?,?,?,?)', (
                    identifier,digest,BASE+path,utc(),len(blocks),versions,
                    int(root.find('./data/analisis') is not None),int(root.find('./data/metadata-eli') is not None),json.dumps(headers)))
                db.execute('''UPDATE inventory SET status=?,hash=?,error=NULL,finished_at=?,lease_until=0 WHERE id=?''',
                           (status, digest, utc(), identifier))
        except DownloadError as exc:
            if digest is None and exc.payload:
                digest = self.store(exc.payload)
            if exc.code in ('http_401','http_403'):
                self.set('worker_blocker',exc.code)
            attempts = row['attempts'] + 1
            retry = exc.retryable and attempts < 8
            status = 'retry' if retry else 'failed' if exc.retryable else 'quarantined'
            with self.db() as db:
                db.execute('UPDATE inventory SET status=?,error=?,hash=?,next_attempt=?,lease_until=0 WHERE id=?',
                    (status,exc.code,digest,time.time()+max(exc.retry_after,min(3600,30*2**(attempts-1))),identifier))
                db.execute('INSERT INTO incidents(stage,resource,code,hash,at) VALUES (?,?,?,?,?)',
                           ('document',identifier,exc.code,digest,utc()))
        return True

    def summary(self):
        with self.db() as db:
            counts = {r['status']: r['n'] for r in db.execute('SELECT status,count(*) n FROM inventory GROUP BY status')}
            total = sum(counts.values())
            stats = db.execute('SELECT count(*) n,coalesce(sum(blocks),0) blocks,coalesce(sum(versions),0) versions FROM snapshots').fetchone()
            size = db.execute('SELECT coalesce(sum(bytes),0) raw,coalesce(sum(compressed_bytes),0) compressed FROM objects').fetchone()
        discovery = self.setting('discovery_1', {})
        started = self.setting('worker_started', {})
        stopped = self.setting('worker_stopped', {})
        return {'source': 'BOE consolidated catalogue', 'catalogue_day': self.setting('catalogue_day'),
                'inventory_complete': discovery.get('complete', False),
                'worker_started': started, 'worker_stopped': stopped, 'blocker': self.setting('worker_blocker'), 'identified': total, 'states': counts,
                'archived_snapshots': stats['n'], 'blocks': stats['blocks'], 'block_versions': stats['versions'],
                'raw_bytes': size['raw'], 'compressed_bytes': size['compressed'], 'observed_at': utc(),
                'all_available_sources_archived': bool(total) and discovery.get('complete',False) and counts.get('complete',0)+counts.get('metadata_only',0)==total,
                'all_downloads_successful': bool(total) and discovery.get('complete', False) and counts.get('complete',0)==total,
                'legal_review': 'not_performed', 'licence_url':LICENCE,
                'attribution':'Fuente de los datos: Agencia Estatal Boletín Oficial del Estado', 'scope': 'Only documents exposed by the BOE consolidated legislation API'}

    def write_status(self):
        status = self.summary()
        temporary = self.root / ('status.json.' + str(os.getpid()) + '.' + str(threading.get_ident()) + '.tmp')
        temporary.write_text(json.dumps(status,ensure_ascii=False,indent=2)+'\n')
        os.replace(temporary,self.root/'status.json')
        return status

    def verify(self):
        """Verify registered files and cross-check every published snapshot."""
        errors = []
        with self.db() as db:
            db.execute('BEGIN')
            objects = list(db.execute('SELECT * FROM objects'))
            snapshots = list(db.execute('SELECT * FROM snapshots'))
            missing = list(db.execute("""SELECT id FROM inventory i WHERE status IN ('complete','metadata_only')
                AND NOT EXISTS(SELECT 1 FROM snapshots s WHERE s.id=i.id AND s.hash=i.hash)"""))
        valid = {}
        for row in objects:
            try:
                path = (self.root / row['path']).resolve()
                path.relative_to(self.root / 'objects')
                raw = gzip.decompress(path.read_bytes())
                if len(raw) != row['bytes'] or hashlib.sha256(raw).hexdigest() != row['hash']:
                    raise ValueError('digest')
                valid[row['hash']] = True
            except (OSError, EOFError, ValueError, zlib.error):
                errors.append({'hash':row['hash'],'code':'object_integrity'})
        for row in snapshots:
            if row['hash'] not in valid:
                continue
            with self.db() as db:
                object_ = db.execute('SELECT path FROM objects WHERE hash=?',(row['hash'],)).fetchone()
            try:
                root = xml_root(gzip.decompress((self.root/object_['path']).read_bytes()))
                blocks = root.findall('./data/texto//bloque')
                if root.findtext('./data/metadatos/identificador') != row['id'] or len(blocks) != row['blocks'] or sum(len(b.findall('./version')) for b in blocks) != row['versions']:
                    raise ValueError('snapshot')
            except (ValueError, DownloadError):
                errors.append({'id':row['id'],'code':'snapshot_integrity'})
        errors.extend({'id':row['id'],'code':'missing_snapshot'} for row in missing)
        result={'verified_at':utc(),'objects_checked':len(objects),'snapshots_checked':len(snapshots),'errors':errors,
                'verification_passed':not errors,'download_complete':self.summary()['all_downloads_successful']}
        (self.root/'verification.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
        return result

    def run(self, client, *, workers=2, min_free_gb=2, max_jobs=None):
        if max_jobs is not None and max_jobs < 1:
            raise ValueError('max_jobs must be positive')
        if not 1 <= workers <= 2:
            raise ValueError('One or two workers; keep requests bounded')
        with (self.root/'worker.lock').open('a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            if self.setting('worker_blocker'):
                raise RuntimeError('Resolve the recorded worker blocker before resuming')
            self.set('worker_started', {'pid':os.getpid(),'at':utc()})
            done = 0
            with ThreadPoolExecutor(max_workers=workers) as pool:
                while max_jobs is None or done < max_jobs:
                    if shutil.disk_usage(self.root).free < min_free_gb * 1024**3:
                        self.set('worker_blocker','insufficient_disk'); break
                    count = workers if max_jobs is None else min(workers,max_jobs-done)
                    futures = [pool.submit(self.fetch_one,client) for _ in range(count)]
                    processed = sum(int(f.result()) for f in as_completed(futures))
                    done += processed
                    self.write_status()
                    if self.setting('worker_blocker'):
                        break
                    if not processed:
                        with self.db() as db:
                            row=db.execute("SELECT min(CASE WHEN status='running' THEN lease_until ELSE next_attempt END) next FROM inventory WHERE status IN ('retry','running','pending')").fetchone()
                        if row['next'] is None:
                            break
                        time.sleep(min(30,max(.5,row['next']-time.time())))
            self.set('worker_stopped', {'at':utc(),'jobs_this_run':done})
            return self.write_status()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',default='/workspace/lexmemoria-corpus')
    sub=parser.add_subparsers(dest='command',required=True)
    scan=sub.add_parser('discover');scan.add_argument('--day',default=madrid_today());scan.add_argument('--pass-number',type=int,default=1)
    seed=sub.add_parser('seed');seed.add_argument('file');seed.add_argument('--offset',type=int,default=0);seed.add_argument('--day',required=True)
    run=sub.add_parser('run');run.add_argument('--workers',type=int,default=2);run.add_argument('--max-jobs',type=int)
    sub.add_parser('status')
    sub.add_parser('verify')
    args=parser.parse_args();archive=Archive(args.root)
    if args.command=='discover':
        result=archive.discover(OfficialClient(),day=args.day,pass_number=args.pass_number)
        archive.write_status()
    elif args.command=='seed':
        progress=archive.setting('discovery_1',{'offset':0})
        with archive.db() as db:
            existing=db.execute('SELECT 1 FROM pages WHERE pass=1 AND offset=?',(args.offset,)).fetchone()
        if args.offset!=progress['offset'] and not existing:
            raise ValueError('Seed pages must be contiguous; refusing to skip inventory')
        raw=Path(args.file).read_bytes();count=archive.add_page(raw,args.offset,1,BASE+'/legislacion-consolidada?'+urlencode({'offset':args.offset,'limit':-1 if args.offset==0 else 1000,'to':args.day.replace('-','')}))
        archive.set('catalogue_day',args.day);archive.set('discovery_1',{'offset':args.offset+count,'complete':False});archive.set('licence_url',LICENCE)
        result=archive.write_status()
    elif args.command=='run':result=archive.run(OfficialClient(),workers=args.workers,max_jobs=args.max_jobs)
    elif args.command=='verify':result=archive.verify()
    else:result=archive.summary()
    print(json.dumps(result,ensure_ascii=False),flush=True)
    if args.command=='verify' and not result['verification_passed']:
        raise SystemExit(2)
    if args.command=='run' and args.max_jobs is None and not result['all_available_sources_archived']:
        raise SystemExit(2)

if __name__=='__main__':main()
