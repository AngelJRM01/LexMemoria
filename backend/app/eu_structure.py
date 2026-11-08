"""Conservative EU paragraph classification; candidates are not study banks."""
import re

PARSER = 'eu-structure-candidates-1'
ARTICLE = re.compile(r'^Artículo\s+(\d+[a-z]*|único)\s*[.º°]?$' , re.I)
ANNEX = re.compile(r'^ANEXO(?:\s+[IVXLCDM\d]+)?(?:\s*[—–:].*)?$', re.I)
HEADING = re.compile(r'^(?:CAPÍTULO|TÍTULO|SECCIÓN|PARTE)\s+[IVXLCDM\d]+$', re.I)


def structure_document(document, celex, url):
    """Preserve every paragraph once; no inference of currency from CELEX."""
    paragraphs = document['paragraphs']
    units = []
    current = None
    annex = False
    seen = set()
    warnings = []
    phase = 'preamble'
    for row in paragraphs:
        text = row['text'].strip()
        article = ARTICLE.fullmatch(text)
        kind = None
        if ANNEX.fullmatch(text):
            annex = True
            kind = 'annex'
        elif annex:
            pass  # Article-like headings inside annexes remain annex content.
        elif HEADING.fullmatch(text):
            kind = 'heading'
        elif article:
            kind = 'article_candidate'
            number = article[1].lower()
            if number in seen:
                warnings.append('duplicate_article_number:' + number)
            seen.add(number)
            phase = 'operative'
        elif text.lower().startswith('considerando lo siguiente'):
            kind = 'recitals'
            phase = 'recitals'
        elif re.match(r'^(?:HAN ADOPTADO|HA ADOPTADO|ADOPTA)\b', text, re.I):
            kind = 'adoption'
            phase = 'operative'
        elif re.match(r'^Hech[oa] en\s', text):
            kind = 'signature'
            phase = 'signature'
        elif re.fullmatch(r'\(\d+\)', text) and phase == 'signature':
            kind = 'notes'
            phase = 'notes'
        if current is None or kind is not None:
            current = {'id': f'eu-unit-{len(units)+1}', 'kind': kind or phase,
                       'title': text if kind else '', 'paragraphs': [],
                       'automaticStudyEligible': False}
            units.append(current)
        current['paragraphs'].append(dict(row))
    if not seen:
        warnings.append('no_article_headings_recognized')
    if celex.startswith('0'):
        edition = 'consolidated'
    elif celex.startswith('3'):
        edition = 'original_act_or_related_document'
    else:
        edition = 'unclassified'
    return {'schemaVersion': 1, 'parser': PARSER, 'celex': celex,
            'sourceUrl': url, 'rawSha256': document['rawSha256'],
            'paragraphParser': document['parser'], 'language': document['language'],
            'editionKind': edition, 'currency': 'not_verified',
            'legalReview': 'not_performed', 'clientReady': False,
            'warnings': warnings, 'units': units}
