import argparse
import json
from pathlib import Path
from .db import connect
from .boe import BoeClient, import_norm
from .jobs import enqueue, batch_status, run_worker, retry_quarantined
from .monitor import watch_day, madrid_day, backfill, daily_cycle, watch_consolidations


def main():
    p = argparse.ArgumentParser(description='LexMemoria · importación y vigilancia BOE')
    sub = p.add_subparsers(dest='command', required=True)
    cmd = sub.add_parser('daily'); cmd.add_argument('day', nargs='?')
    cmd = sub.add_parser('consolidations'); cmd.add_argument('day')
    cmd = sub.add_parser('import'); cmd.add_argument('id')
    cmd = sub.add_parser('watch'); cmd.add_argument('day', nargs='?')
    cmd = sub.add_parser('enqueue'); cmd.add_argument('file'); cmd.add_argument('--key')
    cmd = sub.add_parser('worker'); cmd.add_argument('--batch'); cmd.add_argument('--limit', type=int, default=20)
    cmd = sub.add_parser('batch'); cmd.add_argument('id')
    cmd = sub.add_parser('retry'); cmd.add_argument('id')
    cmd = sub.add_parser('backfill'); cmd.add_argument('start'); cmd.add_argument('end')
    args = p.parse_args()
    _, factory = connect()
    client = BoeClient()
    with factory() as s:
        if args.command == 'daily':
            from datetime import date
            result = daily_cycle(s, client, date.fromisoformat(args.day) if args.day else None)
        elif args.command == 'consolidations': result = watch_consolidations(s, client, args.day)
        elif args.command == 'import': result = import_norm(s, client, args.id)
        elif args.command == 'watch': result = watch_day(s, client, args.day or madrid_day())
        elif args.command == 'enqueue':
            ids = [line.strip() for line in Path(args.file).read_text().splitlines() if line.strip() and not line.startswith('#')]
            result = enqueue(s, ids, args.key)
        elif args.command == 'worker': result = run_worker(factory, client, args.limit, args.batch)
        elif args.command == 'batch': result = batch_status(s, args.id)
        elif args.command == 'retry': retry_quarantined(s, args.id); result = {'requeued': args.id}
        else: result = backfill(s, client, args.start, args.end)
    # Raw XML and private data stay in the database, not in operation logs.
    if isinstance(result, dict) and 'rawXml' in result: result = {k: v for k, v in result.items() if k != 'rawXml'}
    print(json.dumps(result, ensure_ascii=False))


if __name__ == '__main__': main()
