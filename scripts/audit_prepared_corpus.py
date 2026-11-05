#!/usr/bin/env python3
"""Audit all prepared exercises in independent local processes, then verify coverage."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('distribution', type=Path)
    parser.add_argument('--jobs', type=int, default=4)
    parser.add_argument('--dart', default='/workspace/tools/flutter/bin/cache/dart-sdk/bin/dart')
    args = parser.parse_args()
    if not 1 <= args.jobs <= 8:
        parser.error('--jobs must be between 1 and 8')
    root = args.distribution.resolve()
    catalogue_bytes = (root / 'catalogue.json.gz').read_bytes()
    catalogue = json.loads(gzip.decompress(catalogue_bytes))
    items = catalogue['items']
    expected = {item['id'] for item in items}
    if len(expected) != len(items) or len(items) != catalogue['norms']:
        raise ValueError('Incomplete or duplicated catalogue')
    started = time.monotonic()
    processes = []
    with tempfile.TemporaryDirectory(prefix='lexmemoria-exercise-audit-') as work:
        try:
            for index in range(args.jobs):
                folder = Path(work) / str(index)
                folder.mkdir()
                selection = items[index::args.jobs]
                subset = {**catalogue, 'items': selection, 'norms': len(selection)}
                (folder / 'catalogue.json.gz').write_bytes(gzip.compress(json.dumps(subset).encode()))
                (folder / 'boe').symlink_to(root / 'boe', target_is_directory=True)
                log = (folder / 'audit.log').open('w')
                process = subprocess.Popen([args.dart, '--packages=.dart_tool/package_config.json',
                    'tool/audit_prepared_corpus.dart', str(folder)], cwd=ROOT / 'mobile', stdout=log, stderr=subprocess.STDOUT)
                processes.append((process, folder, selection, log))
            seen = set()
            totals = {'qa': 0, 'cloze': 0, 'test': 0, 'reference': 0}
            for process, folder, selection, log in processes:
                while process.poll() is None:
                    for other, other_folder, _, _ in processes:
                        if other.poll() not in (None, 0):
                            raise RuntimeError((other_folder / 'audit.log').read_text()[-8000:])
                    time.sleep(0.5)
                log.close()
                if process.returncode != 0:
                    raise RuntimeError((folder / 'audit.log').read_text()[-8000:])
                result = json.loads((folder / 'exercises-verification.json').read_text())
                selected = {item['id'] for item in selection}
                if not result['validationPassed'] or not result['allNormsChecked'] or result['normsChecked'] != len(selected) or seen & selected:
                    raise ValueError('Incomplete or overlapping audit results')
                seen.update(selected)
                for key in totals:
                    totals[key] += result['exercises'][key]
                print(json.dumps({'validatedNorms': len(seen), 'exercises': totals}), flush=True)
            if seen != expected or totals['qa'] != catalogue['literalCards']:
                raise ValueError('The combined audit does not cover the complete catalogue')
            report = {'normsChecked': len(seen), 'allNormsChecked': True, 'exercises': totals,
                'validationPassed': True, 'legalReview': 'not_performed',
                'catalogueSha256': hashlib.sha256(catalogue_bytes).hexdigest(),
                'independentProcesses': args.jobs, 'elapsedSeconds': round(time.monotonic() - started, 2)}
            target = root / 'exercises-verification.json'
            temporary = target.with_suffix('.tmp')
            temporary.write_text(json.dumps(report, indent=2) + '\n')
            temporary.replace(target)
            print(json.dumps(report), flush=True)
        finally:
            for process, _, _, log in processes:
                if process.poll() is None:
                    process.terminate()
            for process, _, _, log in processes:
                process.wait()
                log.close()


if __name__ == '__main__':
    main()
