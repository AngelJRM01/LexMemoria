"""Import verified public study packs, preserving account data and old versions."""
import gzip
import hashlib
import json
import re
from defusedxml import ElementTree as ET
from sqlalchemy import select
from .db import Record, now
from .catalogue import index_norm
from .bulk import OFFICIAL_ID


def import_distribution_pack(session, entry, payload):
    identifier=entry['id']
    if not OFFICIAL_ID.fullmatch(identifier):raise ValueError('Invalid official identifier')
    if len(payload)!=entry['packBytes'] or hashlib.sha256(payload).hexdigest()!=entry['packHash']:
        raise ValueError('Distribution checksum mismatch')
    pack=json.loads(gzip.decompress(payload));norm=pack['norm'];blocks=pack['items']
    if pack['schemaVersion']!=1 or norm['id']!=identifier or norm['latestVersion']!=entry['latestVersion']:
        raise ValueError('Distribution identity mismatch')
    if not blocks or len({b['id'] for b in blocks})!=len(blocks):raise ValueError('Missing or duplicated blocks')
    for block in blocks:
        if not block['versions']:raise ValueError('Missing versions')
        for version in block['versions']:
            if hashlib.sha256(version['xml'].encode()).hexdigest()!=version['hash']:
                raise ValueError('Block checksum mismatch')
            node=ET.fromstring(version['xml'])
            if version['text']!='\n'.join(''.join(p.itertext()) for p in node):raise ValueError('Text does not match source XML')
    version_id=entry['latestVersion']
    version=session.get(Record,version_id)
    current=session.get(Record,identifier)
    if current and current.kind!='norm':raise ValueError('Identifier already belongs to another record')
    if version:
        if version.kind!='norm_version' or version.data.get('normId')!=identifier or version.data.get('hash')!=pack['sourceHash'] or version.data.get('blocks')!=blocks:
            raise ValueError('An immutable version already has different content')
    else:
        session.add(Record(id=version_id,kind='norm_version',data={
            'normId':identifier,'hash':pack['sourceHash'],'sourceArchiveHash':pack['sourceHash'],
            'distributionHash':entry['packHash'],'sourceUrl':entry['sourceUrl'],
            'blocks':blocks,'downloadedAt':now(),'parser':'verified-distribution-1','reviewState':'imported',
            'rawResponseIncluded':False}))
    date_key=lambda value:re.sub(r'\D','',value or '')[:14]
    if current and date_key(current.data.get('sourceUpdatedAt'))>date_key(entry.get('sourceUpdatedAt')):
        session.commit();return 'archived_older'
    data={**norm,**entry,'officialId':identifier,'source':'BOE','coverage':'imported','reviewState':'pending'}
    data.pop('units',None)
    if current:
        if current.data.get('latestVersion')!=version_id:
            for card in session.scalars(select(Record).where(Record.kind=='card')):
                if any(c.get('normId')==identifier and c.get('versionId')!=version_id for c in card.data.get('citations',[])):
                    card.data={**card.data,'blocked':True,'editorialState':'pending'};card.revision+=1
        current.data=data
    else:session.add(Record(id=identifier,kind='norm',data=data))
    index_norm(session,identifier,data);session.commit()
    return 'duplicate' if version else 'imported'
