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


def study_units(units):
    articles=[u for u in units if ARTICLE.match(u['title'])]
    return articles or [u for u in units if u.get('id') not in ('preambulo','fi') and
                       u.get('versions') and len(u['versions'][-1].get('text','').strip())>60]


def count_cards(units):
    return sum(len(chunks(u['title'],u['versions'][-1].get('text',''))) for u in study_units(units) if u.get('versions'))
