"""Keep one resumable EU worker active; never clear access or storage blockers."""
import argparse
import fcntl
import json
import os
from pathlib import Path
import signal
import sqlite3
import subprocess
import sys
import threading
import time

from .eu_bulk import EuropeanArchive, ROOT, transient_error
from .bulk import DownloadError, utc


def worker_active(root):
    with (Path(root)/'eu-worker.lock').open('a') as lock:
        try:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            return False
        except BlockingIOError:
            return True


def recoverable_blocker(value):
    prefix='discovery_DownloadError:'
    return isinstance(value,str) and value.startswith(prefix) and transient_error(value[len(prefix):])


class Supervisor:
    def __init__(self, root=ROOT, interval=10, refresh_seconds=86400):
        self.archive=EuropeanArchive(root)
        self.root=Path(root)
        self.interval=interval
        self.refresh_seconds=refresh_seconds
        self.stop=threading.Event()
        self.child=None

    def publish(self, state, **details):
        result={'supervisor_pid':os.getpid(),'state':state,'observed_at':utc(),**details}
        target=self.root/'supervisor.json'
        temporary=target.with_suffix('.tmp')
        temporary.write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
        temporary.replace(target)
        return result

    def tick(self):
        a=self.archive
        active=worker_active(self.root)
        now=time.time()
        if self.child is not None and self.child.poll() is not None:
            a.set('eu_last_worker_exit',{'code':self.child.returncode,'at':utc()})
            if self.child.returncode not in (0,2):
                failures=a.setting('eu_worker_start_failures',0)+1
                a.set('eu_worker_start_failures',failures)
                a.set('eu_worker_restart_after',now+min(3600,30*2**min(failures-1,7)))
            self.child=None
        blocker=a.setting('eu_blocker')
        if blocker:
            if not recoverable_blocker(blocker):
                return self.publish('needs_attention',blocker=blocker,worker_active=active)
            recovery=a.setting('eu_supervisor_recovery',{})
            if recovery.get('blocker')!=blocker:
                recovery={'blocker':blocker,'after':max(now+300,a.setting('eu_source_resume_after',0))}
                a.set('eu_supervisor_recovery',recovery)
            if active or now<recovery['after']:
                return self.publish('retry_scheduled',blocker=blocker,resume_after=recovery['after'],worker_active=active)
            # Only a classified temporary discovery failure is cleared, with
            # an audit event and after the provider's persisted backoff.
            with a.db() as db:
                db.execute('INSERT INTO incidents(stage,resource,code,hash,at) VALUES (?,?,?,?,?)',
                    ('eu_supervisor','discovery',blocker,None,utc()))
            a.set('eu_blocker',None)
            a.set('eu_supervisor_recovery',{})
        if now>=a.setting('eu_supervisor_next_retry_check',0):
            a.requeue_transient_failures(now)
            a.set('eu_supervisor_next_retry_check',now+300)
        status=a.status()
        if active:
            a.set('eu_worker_start_failures',0)
            return self.publish('running',worker_active=True,worker=a.setting('eu_started'),
                identified=status['identified'],documents=status['documents'],states=status['states'])
        if self.child is not None:
            return self.publish('starting_worker',worker_pid=self.child.pid,worker_active=False)
        resume=a.setting('eu_source_resume_after',0)
        if now<resume:
            return self.publish('retry_scheduled',resume_after=resume,worker_active=False)
        queued=sum(status['states'].get(k,0) for k in ('pending','retry','running'))
        if not queued and status['inventory_complete']:
            unavailable=status['states'].get('failed',0)+status['states'].get('unsupported_format',0)
            if unavailable:
                return self.publish('needs_attention',worker_active=False,states=status['states'])
            with a.db() as db:
                last_download=db.execute("SELECT max(finished_at) FROM eu_works WHERE status='complete'").fetchone()[0]
            checked=a.setting('eu_discovery_finished_at')
            next_refresh=a.setting('eu_next_inventory_refresh',0)
            verified_download=a.setting('eu_verified_last_download')
            if next_refresh>now and verified_download==last_download:
                return self.publish('watching_source',worker_active=False,
                    next_inventory_refresh=next_refresh,all_texts_archived=status['all_texts_archived'])
            if next_refresh and next_refresh<=now:
                a.set('eu_next_inventory_refresh',0)
                a.request_inventory_refresh()
            # Recheck unavailable translations and newly added records after
            # the last download, not merely the original catalogue count.
            elif checked is None or (last_download is not None and checked<last_download):
                a.request_inventory_refresh()
            else:
                return self.finish_inventory()
        restart=a.setting('eu_worker_restart_after',0)
        if now<restart:
            return self.publish('retry_scheduled',resume_after=restart,worker_active=False)
        log=(self.root/'worker.log').open('a')
        try:
            self.child=subprocess.Popen([sys.executable,'-u','-m','app.eu_bulk','run','--root',str(self.root)],
                stdin=subprocess.DEVNULL,stdout=log,stderr=subprocess.STDOUT,
                cwd=Path(__file__).resolve().parents[1],start_new_session=True)
        finally:
            log.close()
        return self.publish('starting_worker',worker_pid=self.child.pid,worker_active=False)

    def finish_inventory(self):
        a=self.archive
        try:
            reconciliation=a.reconcile_inventory()
        except DownloadError as exc:
            if not transient_error(exc.code):
                a.set('eu_blocker','inventory_'+exc.code)
                return self.publish('needs_attention',blocker='inventory_'+exc.code,worker_active=False)
            return self.publish('inventory_check_retry',code=exc.code,worker_active=False)
        if reconciliation['consistent']:
            self.publish('verifying',worker_active=False)
            report=a.verify()
            complete=report['verification_passed'] and a.status()['all_available_records_archived']
            if not report['verification_passed']:a.set('eu_blocker','integrity_verification_failed')
            if complete:
                with a.db() as db:last=db.execute("SELECT max(finished_at) FROM eu_works WHERE status='complete'").fetchone()[0]
                a.set('eu_verified_last_download',last)
                a.set('eu_next_inventory_refresh',time.time()+self.refresh_seconds)
            return self.publish('watching_source' if complete else 'needs_attention',
                worker_active=False,verification_passed=report['verification_passed'],
                all_texts_archived=report['download_complete'],states=a.status()['states'])
        a.request_inventory_refresh()
        return self.publish('refreshing_inventory',worker_active=False)

    def run(self):
        for signum in (signal.SIGINT,signal.SIGTERM):
            signal.signal(signum,lambda *_:self.stop.set())
        with (self.root/'eu-supervisor.lock').open('a') as lock:
            fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
            try:
                while not self.stop.is_set():
                    try:
                        result=self.tick()
                    except (OSError,sqlite3.Error,ValueError) as exc:
                        self.publish('needs_attention',supervisor_error=type(exc).__name__)
                        self.stop.wait(60)
                        continue
                    self.stop.wait(self.interval)
            finally:
                if self.child is not None and self.child.poll() is None:
                    self.child.terminate()
                self.archive.client.close()
                if self.stop.is_set():self.publish('stopped')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root',default=ROOT)
    parser.add_argument('--interval',type=float,default=10)
    parser.add_argument('--refresh-seconds',type=float,default=86400)
    args=parser.parse_args()
    if args.interval<5:parser.error('--interval must be at least 5 seconds')
    if args.refresh_seconds<3600:parser.error('--refresh-seconds must be at least 3600 seconds')
    Supervisor(args.root,args.interval,args.refresh_seconds).run()


if __name__=='__main__':main()
