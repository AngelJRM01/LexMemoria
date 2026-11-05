"""Check shipped educational answers against the archived official source text."""
import gzip
import hashlib
import json
from pathlib import Path
import re


def test_every_prepared_answer_is_literal_and_cited_without_missing_articles():
    mobile=Path(__file__).resolve().parents[2]/'mobile'
    ready=json.loads((mobile/'assets/ready/index.json').read_text())
    legal={n['id']:n for n in json.loads((mobile/'assets/legal-catalogue.json').read_text())['items']}
    all_ids=set()
    for deck in ready['items']:
        data=(mobile/deck['asset']).read_bytes()
        assert hashlib.sha256(data).hexdigest()==deck['hash']
        cards=json.loads(gzip.decompress(data))['cards']
        assert len(cards)==deck['count'] and cards
        source=legal[deck['id']]
        packed=(mobile/source['bundledAsset']).read_bytes()
        assert hashlib.sha256(packed).hexdigest()==source['bundledHash']
        units=json.loads(gzip.decompress(packed))['items']
        by_id={u['id']:u for u in units}
        covered=set()
        for card in cards:
            assert card['id'] not in all_ids
            all_ids.add(card['id']);covered.add(card['unitId'])
            version=by_id[card['unitId']]['versions'][-1]
            assert card['normId']==deck['id'] and card['versionId']==source['latestVersion']
            assert card['unitVersionHash']==version['hash']
            assert ' '.join(card['back'].split()) in ' '.join(version['text'].split())
            assert 0<len(card['back'])<=1200 and card['editorialState']=='source_literal'
        for unit in units:
            if not re.match(r'^(?:Art[íi]culo|Art\.?)\s',unit['title'],re.I) or not unit['versions']:continue
            text=unit['versions'][-1]['text'].strip()
            lines=[line.strip() for line in text.splitlines() if line.strip()]
            if lines and lines[0]==unit['title'].strip():lines.pop(0)
            if lines and text.lower() not in ('(derogado)','(derogada)','derogado.','derogada.'):
                assert unit['id'] in covered
    assert len(ready['items'])==20 and len(all_ids)>10000
    assert next(d['count'] for d in ready['items'] if d['id']=='BOE-A-1889-4763')>1000
