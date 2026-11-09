"""Verified, bounded-page classification for oversized EU paragraph objects."""
import argparse
from collections import defaultdict
import gzip
import hashlib
import json
from pathlib import Path
import shutil
import sqlite3
import ijson
from .eu_structure import UnitCursor, structure_metadata


class HashReader:
    def __init__(self,file):self.file=file;self.digest=hashlib.sha256()
    def read(self,size=-1):
        data=self.file.read(size);self.digest.update(data);return data


def save_object(root,data):
    digest=hashlib.sha256(data).hexdigest();relative=f'objects/{digest[:2]}/{digest}.json.gz'
    target=root/relative;target.parent.mkdir(parents=True,exist_ok=True)
    if not target.exists():
        temporary=target.with_suffix('.tmp');temporary.write_bytes(gzip.compress(data,mtime=0));temporary.replace(target)
    check=hashlib.sha256()
    with gzip.open(target,'rb') as file:
        while chunk:=file.read(1024**2):check.update(chunk)
    if check.hexdigest()!=digest:raise ValueError('output_hash_mismatch')
    return relative,digest,target.stat().st_size


def prepare(source,output,row,page_bytes=2*1024**2,cursor_class=UnitCursor,parser_version=None,bounded_json_bytes=256*1024**2):
    """Every input paragraph appears once in the same order in verified pages."""
    cursor=cursor_class();metadata={};pages=[];units=[];pending=[];size=0;total=0
    input_rows=hashlib.sha256();output_rows=hashlib.sha256();current=None
    def flush():
        nonlocal pending,size
        if not pending:return
        data=b'\n'.join(pending)+b'\n'
        path,digest,compressed=save_object(output,data)
        pages.append({'path':path,'sha256':digest,'compressedBytes':compressed,
                      'paragraphs':len(pending),'uncompressedBytes':len(data)})
        pending=[];size=0
    cleaning={'nulPaddingCharactersRemoved':0,'excludedEmptyParagraphIds':[]}
    def source_rows():
        # Some legacy JSON has a single enormous escaped NUL padding string.
        # Bound this fallback to 256 MiB; larger sources stay incremental.
        import struct
        with open(source,'rb') as file:
            file.seek(-4,2);declared=struct.unpack('<I',file.read(4))[0]
        if declared<=bounded_json_bytes:
            with gzip.open(source,'rb') as original:encoded=original.read(256*1024**2+1)
            if len(encoded)>256*1024**2:raise ValueError('bounded_json_size_limit')
            if hashlib.sha256(encoded).hexdigest()!=row['output_hash']:raise ValueError('source_hash_mismatch')
            document=json.loads(encoded);del encoded
            metadata.update({k:document.get(k) for k in ('rawSha256','parser','language')})
            yield from document['paragraphs'];return
        with gzip.open(source,'rb') as original:
            reader=HashReader(original);builder=None;depth=0
            for prefix,event,value in ijson.parse(reader,use_float=True):
                if prefix in ('rawSha256','parser','language') and event=='string':metadata[prefix]=value
                if prefix=='paragraphs.item' and event=='start_map':
                    builder=ijson.ObjectBuilder();depth=0
                if builder is not None:
                    builder.event(event,value)
                    if event in ('start_map','start_array'):depth+=1
                    elif event in ('end_map','end_array'):depth-=1
                    if depth==0:
                        yield builder.value;builder=None
            if reader.digest.hexdigest()!=row['output_hash']:raise ValueError('source_hash_mismatch')
    for paragraph in source_rows():
        if not isinstance(paragraph.get('text'),str) or not paragraph.get('id'):raise ValueError('invalid_paragraph')
        removed=paragraph['text'].count('\x00')
        if removed:
            cleaning['nulPaddingCharactersRemoved']+=removed
            paragraph={**paragraph,'text':paragraph['text'].replace('\x00','')}
            if not paragraph['text'].strip():
                cleaning['excludedEmptyParagraphIds'].append(paragraph['id']);continue
        normalized=json.dumps(paragraph,ensure_ascii=False,sort_keys=True).encode()
        input_rows.update(normalized+b'\n')
        boundary=cursor.feed(paragraph)
        if boundary is not None:
            current={**boundary,'firstParagraph':total,'paragraphCount':0};units.append(current)
        record={'unitId':current['id'],'paragraph':paragraph}
        encoded=json.dumps(record,ensure_ascii=False,separators=(',',':')).encode()
        if len(encoded)>4*1024**2:raise ValueError('paragraph_size_limit')
        if pending and size+len(encoded)+1>page_bytes:flush()
        pending.append(encoded);size+=len(encoded)+1;total+=1;current['paragraphCount']+=1
        output_rows.update(json.dumps(json.loads(encoded)['paragraph'],ensure_ascii=False,sort_keys=True).encode()+b'\n')
    if metadata.get('rawSha256')!=row['raw_hash']:raise ValueError('raw_hash_mismatch')
    if not metadata.get('parser') or metadata.get('language')!='es':raise ValueError('source_metadata_missing')
    flush()
    if total==0 or input_rows.digest()!=output_rows.digest():raise ValueError('paragraph_sequence_mismatch')
    manifest={**structure_metadata(metadata,row['celex'],row['url']),'schemaVersion':2,
              'storageLayout':'paged-paragraphs','pages':pages,'units':units,'paragraphs':total,
              'paragraphSequenceSha256':input_rows.hexdigest(),'paragraphSourceSha256':row['output_hash'],
              'warnings':cursor.final_warnings(),'sourceCleaning':cleaning}
    if parser_version:manifest['parser']=parser_version
    encoded=json.dumps(manifest,ensure_ascii=False,sort_keys=True).encode()
    path,_,_=save_object(output,encoded)
    return path,manifest


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--processed',type=Path,default=Path('/workspace/lexmemoria-eu-processed'))
    parser.add_argument('--structures',type=Path,default=Path('/workspace/lexmemoria-eu-structure-stream'))
    args=parser.parse_args();source=args.processed.resolve();output=args.structures.resolve()
    if source==output or source in output.parents or output in source.parents:parser.error('Separate source and output')
    import fcntl
    with (output/'paged-recovery.lock').open('a') as lock:
        fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        db=sqlite3.connect(output/'structure.sqlite3');db.row_factory=sqlite3.Row
        rows=db.execute("SELECT * FROM results WHERE state='failed' AND error='size_limit' ORDER BY source_row").fetchall()
        with sqlite3.connect((source/'processing.sqlite3').as_uri()+'?mode=ro',uri=True) as original:
            original.row_factory=sqlite3.Row
            for failed in rows:
                if shutil.disk_usage(output).free<2*1024**3:raise RuntimeError('insufficient_disk')
                row=original.execute('SELECT * FROM processed WHERE rowid=?',(failed['source_row'],)).fetchone()
                if row is None or row['state']!='extracted':raise ValueError('source_changed')
                path=(source/row['output_path']).resolve()
                if source not in path.parents:raise ValueError('source_path_outside_directory')
                relative,manifest=prepare(path,output,row)
                articles=sum(u['kind']=='article_candidate' for u in manifest['units'])
                with db:db.execute("UPDATE results SET state='candidate',path=?,articles=?,paragraphs=?,warnings=?,error=NULL WHERE source_row=? AND state='failed' AND error='size_limit'",(relative,articles,manifest['paragraphs'],json.dumps(manifest['warnings']),failed['source_row']))
                print(json.dumps({'celex':row['celex'],'state':'candidate','articles':articles,'paragraphs':manifest['paragraphs'],'pages':len(manifest['pages'])}),flush=True)
        db.close()

if __name__=='__main__':main()
