from app.eu_review_structure import structure_document


def test_embedded_draft_is_not_counted_as_articles_of_the_enacting_act():
    texts=['Artículo 1','Una regla.','Hecho en Bruselas, el 1 de enero.','PROYECTO','DECISIÓN N.o […]','Artículo 1','Regla del proyecto.']
    doc={'rawSha256':'h','parser':'fixture','language':'es','paragraphs':[{'id':str(i),'text':t} for i,t in enumerate(texts)]}
    result=structure_document(doc,'32000D0001','source')
    assert [u['title'] for u in result['units'] if u['kind']=='article_candidate']==['Artículo 1']
    assert result['units'][-1]['kind']=='embedded_document'
    assert [p for u in result['units'] for p in u['paragraphs']]==doc['paragraphs']
    assert result['warnings']==[]


def test_ordinal_and_bis_labels_preserve_original_spelling():
    texts=['Artículo primero.','Regla.','Artículo 2 bis','Otra regla.','Artículo 3.º','Tercera regla.']
    doc={'rawSha256':'h','parser':'fixture','language':'es','paragraphs':[{'id':str(i),'text':t} for i,t in enumerate(texts)]}
    result=structure_document(doc,'32000R0001','source')
    assert [u['title'] for u in result['units']]==texts[::2]
