#!/usr/bin/env python3
"""Prepare local, traceable EU structure candidates while downloads continue."""
import argparse
import gzip
import hashlib
import json
from pathlib import Path
import sqlite3
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'backend'))
from app.eu_structure import structure_document


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--processed', type=Path, default=Path('/workspace/lexmemoria-eu-processed'))
    p.add_argument('--output', type=Path, default=Path('/workspace/lexmemoria-eu-structured'))
    p.add_argument('--celex', nargs='+', default=['32016R0679', '32019L1152', '32021D0914'])
    args = p.parse_args()
    if args.output.resolve() == args.processed.resolve() or args.processed.resolve() in args.output.resolve().parents:
        p.error('Keep candidate output separate from paragraph extraction')
    args.output.mkdir(parents=True, exist_ok=True)
    reports = []
    with sqlite3.connect(args.processed.resolve().joinpath('processing.sqlite3').as_uri()+'?mode=ro', uri=True) as db:
        db.row_factory = sqlite3.Row
        for celex in args.celex:
            row = db.execute("SELECT * FROM processed WHERE celex=? AND state='extracted' ORDER BY url LIMIT 1", (celex,)).fetchone()
            if row is None:
                reports.append({'celex': celex, 'state': 'not_available'}); continue
            source = (args.processed / row['output_path']).resolve()
            if args.processed.resolve() not in source.parents:
                raise ValueError('Invalid source path')
            encoded = gzip.decompress(source.read_bytes())
            if hashlib.sha256(encoded).hexdigest() != row['output_hash']:
                raise ValueError('Paragraph object integrity mismatch')
            original = json.loads(encoded)
            result = structure_document(original, celex, row['url'])
            flattened = [v for unit in result['units'] for v in unit['paragraphs']]
            if flattened != original['paragraphs']:
                raise ValueError('Paragraph loss or reordering')
            target = args.output / (celex + '.json.gz')
            temporary = target.with_suffix('.tmp')
            temporary.write_bytes(gzip.compress(json.dumps(result,ensure_ascii=False).encode(),mtime=0))
            temporary.replace(target)
            reports.append({'celex': celex, 'paragraphs': len(flattened),
                            'articleCandidates': sum(u['kind']=='article_candidate' for u in result['units']),
                            'warnings': result['warnings'], 'paragraphConservation': True})
    (args.output/'report.json').write_text(json.dumps(reports,ensure_ascii=False,indent=2)+'\n')
    print(json.dumps(reports,ensure_ascii=False,indent=2))

if __name__ == '__main__': main()
