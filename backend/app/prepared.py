"""Literal study fragments; no generated interpretation or claim of validity."""
import re

ARTICLE = re.compile(r'^(?:Art[íi]culo|Art\.?)\s', re.I)


def chunks(title, text, limit=1200):
    paragraphs=[p.strip() for p in text.splitlines() if p.strip()]
    if paragraphs and (paragraphs[0]==title.strip() or re.match(r'^Art[íi]culo\s',paragraphs[0],re.I)):
        paragraphs.pop(0)
    parts=[]
    for paragraph in paragraphs:
        while len(paragraph)>limit:
            cut=paragraph.rfind(' ',0,limit+1)
            if cut<=0:cut=limit
            parts.append(paragraph[:cut]);paragraph=paragraph[cut:].lstrip()
        if paragraph:parts.append(paragraph)
    result=[];buffer=''
    for part in parts:
        if buffer and len(buffer)+1+len(part)>limit:result.append(buffer);buffer=''
        buffer=(buffer+'\n'+part).strip()
    if buffer:result.append(buffer)
    return result


def unit_kind(unit):
    title=unit.get('title','').strip()
    if unit.get('type')=='encabezado':return 'heading'
    if unit.get('type')=='firma':return 'signature'
    if unit.get('type')=='nota_inicial':return 'editorial_note'
    if unit.get('type')=='preambulo':return 'preamble'
    if ARTICLE.match(title):return 'article'
    value=title.lower()
    if 'preámbulo' in value or 'preambulo' in value or value.startswith('exposición de motivos'):return 'preamble'
    if value.startswith(('disposición','disposicion')):return 'provision'
    if value.startswith(('anexo','apéndice')):return 'annex'
    return 'other'


def study_units(units):
    return [u for u in units if unit_kind(u)=='article' and u.get('versions') and
            u['versions'][-1].get('text','').strip() and not re.fullmatch(
                r'\(?\s*(?:derogad[oa]|suprimid[oa]|sin contenido)\s*[.)]*',
                u['versions'][-1].get('text','').strip(),re.I)]


def count_cards(units):
    return sum(len(passages(u['title'],body_text(u['versions'][-1]))) for u in study_units(units))


def passages(title,text):
    paragraphs=[p.strip() for p in text.splitlines() if p.strip()]
    if paragraphs and paragraphs[0]==title.strip():paragraphs.pop(0)
    result=[]
    for paragraph in paragraphs:
        if len(paragraph)<=320:
            if len(paragraph)>=35:result.append(paragraph)
            continue
        prefix=''
        for sentence in re.split(r'(?<=[.;!?])\s+',paragraph):
            part=(prefix+' '+sentence.strip()).strip();prefix=''
            if len(part)<35:prefix=part;continue
            if len(part)<=320:result.append(part)
    return result


def body_text(version):
    original=version.get('text','');markup=version.get('xml','')
    if 'nota_pie' not in markup:return original
    from defusedxml import ElementTree as ET
    root=ET.fromstring(markup)
    for parent in root.iter():
        for child in list(parent):
            if child.tag=='p' and child.get('class')=='nota_pie':parent.remove(child)
    return '\n'.join(value for child in root if (value:=''.join(child.itertext()).strip()))
