from app.eu_structure import structure_document


def build(texts, celex='32016R0679'):
    paragraphs = [dict(id=str(i), text=t, sourceAnchor=None) for i,t in enumerate(texts)]
    doc = dict(paragraphs=paragraphs, rawSha256='abc',parser='fixture',language='es')
    result = structure_document(doc,celex,'https://example.test/original')
    assert [p for u in result['units'] for p in u['paragraphs']] == paragraphs
    assert all(not u['automaticStudyEligible'] for u in result['units'])
    return result


def test_recitals_annex_and_signature_do_not_become_articles():
    r=build(['Considerando lo siguiente:', '(1)', 'Se aplica el artículo 3.',
             'HA ADOPTADO EL PRESENTE REGLAMENTO:', 'Artículo 1', 'Objeto',
             '1. Una regla.', 'Hecho en Bruselas, el 1 de enero.', '(1)',
             'Una nota.', 'ANEXO I', 'Artículo 2', 'Regla del anexo.'])
    assert [u['kind'] for u in r['units']] == ['recitals','adoption','article_candidate','signature','notes','annex']
    assert r['currency']=='not_verified' and not r['clientReady']


def test_duplicate_number_is_reported_not_silently_merged():
    r=build(['Artículo 1','A','Artículo 1','B'])
    assert r['warnings']==['duplicate_article_number:1']


def test_consolidation_is_not_currency_certification():
    r=build(['Artículo único','Una regla.'],'02016R0679-20160504')
    assert r['editionKind']=='consolidated'
    assert r['currency']=='not_verified'


def test_sentence_mentioning_article_is_not_a_heading():
    r=build(['Artículo 4 del Reglamento queda modificado.'])
    assert r['warnings']==['no_article_headings_recognized']
