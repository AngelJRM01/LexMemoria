"""Reviewed structural rules; no legal currency or educational certification."""
import re
from .eu_structure import UnitCursor, structure_metadata

PARSER='eu-structure-reviewed-2'
ORDINALS={'primero':'1','segundo':'2','tercero':'3','cuarto':'4','quinto':'5',
          'sexto':'6','séptimo':'7','octavo':'8','noveno':'9','décimo':'10','único':'único'}
LABEL=re.compile(r'^Artículo\s+(\d+(?:\s*(?:bis|ter|quater|quinquies|sexies|[a-z]))?|'+ '|'.join(ORDINALS)+r')[.º°]{0,2}$',re.I)


class ReviewCursor(UnitCursor):
    def __init__(self):super().__init__();self.embedded=False
    def feed(self,row):
        text=row['text'].strip()
        if not self.embedded and self.phase in ('signature','notes') and text.upper()=='PROYECTO':
            self.embedded=True;self.index+=1
            return {'id':f'eu-unit-{self.index}','kind':'embedded_document',
                    'title':text,'automaticStudyEligible':False}
        if self.embedded:return None
        match=LABEL.fullmatch(text)
        if match and not self.annex:
            value=match[1].lower();canonical=ORDINALS.get(value,re.sub(r'\s+','',value))
            result=super().feed({**row,'text':'Artículo '+canonical})
            if result:result['title']=text
            return result
        return super().feed(row)


def structure_document(document,celex,url):
    cursor=ReviewCursor();units=[];current=None
    for paragraph in document['paragraphs']:
        boundary=cursor.feed(paragraph)
        if boundary is not None:current={**boundary,'paragraphs':[]};units.append(current)
        current['paragraphs'].append(dict(paragraph))
    return {**structure_metadata(document,celex,url),'parser':PARSER,
            'warnings':cursor.final_warnings(),'units':units}
