#!/usr/bin/env python3
"""Build a traceable, read-only original-act sample for the mobile library."""
import gzip
import hashlib
import json
from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
SAMPLES={'32016R0679':('RGPD · texto original','Reglamento'),
         '32019L1152':('Condiciones laborales transparentes · texto original','Directiva'),
         '32021D0914':('Transferencias de datos · texto original','Decisión')}


def main():
    output=ROOT/'mobile/assets/europe';output.mkdir(parents=True,exist_ok=True)
    entries=[]
    for celex,(title,kind) in SAMPLES.items():
        source=Path('/workspace/lexmemoria-eu-structured')/(celex+'.json.gz')
        structured=json.loads(gzip.decompress(source.read_bytes()))
        if structured['warnings']:raise ValueError('Unresolved structural warnings')
        date=structured['units'][0]['paragraphs'][0]['text']
        match=re.fullmatch(r'(\d{1,2})\.(\d{1,2})\.(\d{4})',date)
        if not match:raise ValueError('Publication date needs review')
        day,month,year=match.groups();published=f'{year}-{int(month):02}-{int(day):02}'
        version=f"EU-{celex}:{structured['rawSha256'][:24]}"
        norm={'id':f'EU-{celex}','officialId':celex,'celex':celex,'short':title,'title':title,
              'source':'EUR-Lex','jurisdiction':'Unión Europea','subject':'Unión Europea','kind':kind,
              'publicationDate':published,'editionKind':'original','latestVersion':version,
              'sourceUrl':f'https://eur-lex.europa.eu/legal-content/ES/TXT/?uri=CELEX:{celex}',
              'attribution':'Fuente: Oficina de Publicaciones de la Unión Europea',
              'licenceUrl':'https://op.europa.eu/en/web/about-us/legal-notices/publications-office-reuse-policy',
              'reviewState':'pending','informative':True,'automaticStudyEligible':False,
              'count':0,'readingNotice':'Texto original publicado. Puede haber modificaciones posteriores; consulta la fuente oficial para comprobar la versión aplicable.'}
        units=[]
        kinds={'article_candidate':'precepto','preamble':'preambulo','recitals':'recitals',
               'adoption':'editorial_note','signature':'firma','heading':'encabezado',
               'annex':'annex','notes':'editorial_note'}
        for item in structured['units']:
            paragraphs=item['paragraphs'];text='\n'.join(p['text'] for p in paragraphs)
            title=item['title'] or 'Preámbulo'
            if item['kind']=='recitals':title='Considerandos'
            units.append({'id':item['id'],'title':title,'type':kinds[item['kind']],
                          'automaticStudyEligible':False,'sourceParagraphs':paragraphs,
                          'versions':[{'id':version+':'+item['id'],'text':text,
                                       'publicationDate':published,'effectiveFrom':None,
                                       'hash':hashlib.sha256(text.encode()).hexdigest(),
                                       'sourceHash':structured['rawSha256']}]})
        pack={'schemaVersion':1,'norm':norm,'items':units,'sourceHash':structured['rawSha256']}
        encoded=gzip.compress(json.dumps(pack,ensure_ascii=False).encode(),mtime=0)
        asset=f'assets/europe/{celex}.json.gz';(ROOT/'mobile'/asset).write_bytes(encoded)
        entries.append({**norm,'bundledAsset':asset,'bundledHash':hashlib.sha256(encoded).hexdigest()})
    (output/'index.json').write_text(json.dumps({'schemaVersion':1,'items':entries},ensure_ascii=False,separators=(',',':'))+'\n')
    print(json.dumps({'readingDocuments':len(entries),'automaticExercises':False}))

if __name__=='__main__':main()
