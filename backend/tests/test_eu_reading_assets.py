import gzip
import hashlib
import json
from pathlib import Path
from app.prepared import study_units


def test_european_reading_packs_preserve_source_and_block_generation():
    mobile=Path(__file__).resolve().parents[2]/'mobile'
    index=json.loads((mobile/'assets/europe/index.json').read_text())
    expected={'32016R0679':99,'32019L1152':26,'32021D0914':4}
    assert {n['celex'] for n in index['items']}==set(expected)
    for norm in index['items']:
        encoded=(mobile/norm['bundledAsset']).read_bytes()
        assert hashlib.sha256(encoded).hexdigest()==norm['bundledHash']
        pack=json.loads(gzip.decompress(encoded));units=pack['items']
        assert pack['norm']['latestVersion']==norm['latestVersion']
        assert sum(u['type']=='precepto' for u in units)==expected[norm['celex']]
        assert study_units(units)==[]
        paragraphs=[p for u in units for p in u['sourceParagraphs']]
        assert len({p['id'] for p in paragraphs})==len(paragraphs)
        for unit in units:
            v=unit['versions'][0]
            assert v['text']=='\n'.join(p['text'] for p in unit['sourceParagraphs'])
            assert hashlib.sha256(v['text'].encode()).hexdigest()==v['hash']
            assert v['sourceHash']==pack['sourceHash'] and v['effectiveFrom'] is None
        assert norm['editionKind']=='original' and norm['automaticStudyEligible'] is False
