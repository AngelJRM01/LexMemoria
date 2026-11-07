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
    return [u for u in units if unit_kind(u)=='article' and u.get('versions') and not requires_legal_context_review(u['versions'][-1]) and
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


from functools import lru_cache

@lru_cache(maxsize=64)
def _legal_content(markup,original):
    if 'nota_pie' not in markup:return original,()
    from defusedxml import ElementTree as ET
    root=ET.fromstring(markup);notes=[]
    def note_paragraph(node):return node.tag=='p' and 'nota_pie' in node.get('class','').split()
    def clean(parent):
        for child in list(parent):
            first=next(child.iter('p'),None)
            if note_paragraph(child) or (child.tag=='blockquote' and first is not None and note_paragraph(first)):
                notes.append(''.join(child.itertext()).strip());parent.remove(child)
            else:clean(child)
    clean(root)
    return '\n'.join(value for child in root if (value:=''.join(child.itertext()).strip())),tuple(notes)


def body_text(version):return _legal_content(version.get('xml',''),version.get('text',''))[0]


def editorial_notes(version):return list(_legal_content(version.get('xml',''),version.get('text',''))[1])


def requires_legal_context_review(version):
    import unicodedata
    pattern=r'inconstitucional|constitucionalidad|nulidad|suspendid|suspension|sentencia.*interpret|interpret.*sentencia|inaplicab'
    return bool(re.search(r'redacci[oó]n anterior\s*:',body_text(version),re.I)) or any(re.search(pattern,''.join(c for c in unicodedata.normalize('NFD',note.lower()) if unicodedata.category(c)!='Mn')) for note in editorial_notes(version))
