from app.prepared import body_text,study_units,passages


def test_editorial_notes_are_separate_from_educational_body_and_xml_is_preserved():
    version={'text':'Artículo 1\nEl Gobierno resolverá en treinta días.\nSe modifica por una reforma.',
      'xml':'<version><p class="articulo">Artículo 1</p><p class="parrafo">El Gobierno resolverá en treinta días.</p><blockquote><p class="nota_pie">Se modifica por una reforma.</p></blockquote></version>'}
    original=version.copy()
    assert 'Se modifica' not in body_text(version)
    assert version==original
    assert passages('Artículo 1',body_text(version))==['El Gobierno resolverá en treinta días.']


def test_only_articles_are_eligible_and_long_unbroken_rules_are_not_truncated():
    source=[{'id':str(i),'title':title,'type':kind,'versions':[{'text':'El Gobierno resolverá el procedimiento administrativo en treinta días.'}]} for i,(title,kind) in enumerate([
      ('TÍTULO I','encabezado'),('Preámbulo','preambulo'),('Disposición final','precepto'),('Art 1','precepto'),('Artículo 2','precepto')])]
    assert [u['title'] for u in study_units(source)]==['Art 1','Artículo 2']
    assert passages('Artículo 1','El Gobierno '+('resolverá '*100)+'este procedimiento.')==[]


def test_historical_wording_is_editorial_but_current_normative_quotes_remain():
    from app.prepared import editorial_notes,requires_legal_context_review
    version={'text':'Mixed','xml':'<version><p class="parrafo">Regla actual suficientemente larga para estudiar.</p><blockquote><p class="nota_pie">Se modifica.</p><p>Redacción anterior:</p><p>Texto anterior que no está vigente.</p></blockquote><blockquote><p class="parrafo">Texto normativo citado en la regla actual.</p></blockquote></version>'}
    body=body_text(version)
    assert 'Texto anterior' not in body and 'Texto normativo citado' in body
    assert 'Texto anterior' in editorial_notes(version)[0]
    assert not requires_legal_context_review(version)
    version={'text':'Regla actual.','xml':'<version><p class="parrafo">Regla actual.</p><blockquote><p class="nota_pie">No es inconstitucional siempre que se interprete conforme a la Sentencia.</p></blockquote></version>'}
    assert requires_legal_context_review(version)
    assert study_units([{'title':'Artículo 1','versions':[version]}])==[]


def test_review_rejects_headings_and_unfinished_chapeaux_without_cutting_law():
    from app.prepared import safe_study_passage,recall_passages,incomplete_definition_passage
    for text in ['Principios relativos al tratamiento','A efectos del presente Reglamento se entenderá por:', 'la oferta de servicios a los interesados, o']:
        assert not safe_study_passage(text)
    rights='2. Asimismo, todos tienen derecho al Juez ordinario predeterminado por la ley, a la defensa y a la asistencia de letrado, a ser informados de la acusación formulada contra ellos, a un proceso público sin dilaciones indebidas y con todas las garantías, a utilizar los medios de prueba pertinentes para su defensa, a no declarar contra sí mismos, a no confesarse culpables y a la presunción de inocencia.'
    assert len(rights)>320 and rights in recall_passages('Artículo 24',rights)
    assert safe_study_passage(rights)

    definition='1) «datos personales»: información sobre una persona identificada; se incluye la identificación indirecta mediante uno o varios factores.'
    assert incomplete_definition_passage(definition.split(';')[0]+';',definition)
    assert not incomplete_definition_passage(definition,'  '+definition+'  ')
