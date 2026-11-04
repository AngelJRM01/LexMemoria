import argparse
from datetime import datetime
from zoneinfo import ZoneInfo
from .db import connect, Record, now
from .boe import BoeClient, import_norm

p = argparse.ArgumentParser()
p.add_argument('command', choices=['import', 'watch'])
p.add_argument('value', nargs='?')
a = p.parse_args()
_, factory = connect()
with factory() as s:
    client = BoeClient()
    if a.command == 'import':
        print(import_norm(s, client, a.value))
    else:
        day = a.value or datetime.now(ZoneInfo('Europe/Madrid')).strftime('%Y%m%d')
        key = 'daily:' + day
        old = s.get(Record, key)
        if old and old.data.get('status') == 'complete':
            print('Ya ejecutado para este día civil de Madrid')
        else:
            raw = client.daily(day)
            r = old or Record(id=key, kind='daily_run')
            r.data = {'day': day, 'status': 'complete', 'rawXml': raw.decode(), 'finishedAt': now(),
                      'scope': 'Sumario descargado; clasificación de impacto pendiente'}
            s.add(r)
            s.commit()
            print(key)
