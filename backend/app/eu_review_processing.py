"""Incremental classification of the second, corrected HTML extraction."""
import json
import time
import sqlite3
import argparse
from pathlib import Path
from .eu_structure_processing import Processor
from .eu_review_structure import PARSER,ReviewCursor,structure_document


class ReviewProcessor(Processor):
    parser=PARSER
    structure=staticmethod(structure_document)
    cursor_class=ReviewCursor


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--processed',default='/workspace/lexmemoria-eu-leaf-processed')
    parser.add_argument('--output',default='/workspace/lexmemoria-eu-reviewed-structures')
    args=parser.parse_args()
    source=Path(args.processed).resolve()/'processing.sqlite3'
    while True:
        if source.exists():
            with sqlite3.connect(source.as_uri()+'?mode=ro',uri=True) as db:
                if db.execute("SELECT 1 FROM sqlite_master WHERE name='processed'").fetchone():break
        time.sleep(5)
    processor=ReviewProcessor(args.processed,args.output)
    try:
        while True:
            count=processor.batch(100);print(json.dumps(processor.status()),flush=True)
            time.sleep(1 if count else 30)
    finally:processor.close()

if __name__=='__main__':main()
