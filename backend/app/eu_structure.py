"""Conservative EU paragraph classification; candidates are not study banks."""
import re

PARSER = 'eu-structure-candidates-1'
ARTICLE = re.compile(r'^Artículo\s+(\d+[a-z]*|único)\s*[.º°]?$', re.I)
ANNEX = re.compile(r'^ANEXO(?:\s+[IVXLCDM\d]+)?(?:\s*[—–:].*)?$', re.I)
HEADING = re.compile(r'^(?:CAPÍTULO|TÍTULO|SECCIÓN|PARTE)\s+[IVXLCDM\d]+$', re.I)


class UnitCursor:
    """Shared state machine for ordinary and bounded-memory classification."""
    def __init__(self):
        self.annex=False;self.seen=set();self.warnings=[]
        self.phase='preamble';self.index=0

    def feed(self,row):
        text=row['text'].strip();article=ARTICLE.fullmatch(text);kind=None
        if ANNEX.fullmatch(text):self.annex=True;kind='annex'
        elif self.annex:pass
        elif HEADING.fullmatch(text):kind='heading'
        elif article:
            kind='article_candidate';number=article[1].lower()
            if number in self.seen:self.warnings.append('duplicate_article_number:'+number)
            self.seen.add(number);self.phase='operative'
        elif text.lower().startswith('considerando lo siguiente'):
            kind='recitals';self.phase='recitals'
        elif re.match(r'^(?:HAN ADOPTADO|HA ADOPTADO|ADOPTA)\b',text,re.I):
            kind='adoption';self.phase='operative'
        elif re.match(r'^Hech[oa] en\s',text):kind='signature';self.phase='signature'
        elif re.fullmatch(r'\(\d+\)',text) and self.phase=='signature':
            kind='notes';self.phase='notes'
        if not self.index or kind is not None:
            self.index+=1
            return {'id':f'eu-unit-{self.index}','kind':kind or self.phase,
                    'title':text if kind else '', 'automaticStudyEligible':False}
        return None

    def final_warnings(self):
        return self.warnings+([] if self.seen else ['no_article_headings_recognized'])


def structure_metadata(document,celex,url):
    return {'schemaVersion':1,'parser':PARSER,'celex':celex,'sourceUrl':url,
            'rawSha256':document['rawSha256'],'paragraphParser':document['parser'],
            'language':document['language'],
            'editionKind':'consolidated' if celex.startswith('0') else
                          'original_act_or_related_document' if celex.startswith('3') else 'unclassified',
            'currency':'not_verified','legalReview':'not_performed','clientReady':False,
            'sourceCleaning':document.get('sourceCleaning',{}),'sourceQualityWarnings':document.get('qualityWarnings',[])}


def structure_document(document,celex,url):
    """Preserve every paragraph once; no inference of currency from CELEX."""
    cursor=UnitCursor();units=[];current=None
    for row in document['paragraphs']:
        boundary=cursor.feed(row)
        if boundary is not None:
            current={**boundary,'paragraphs':[]};units.append(current)
        current['paragraphs'].append(dict(row))
    return {**structure_metadata(document,celex,url),'warnings':cursor.final_warnings(),'units':units}
