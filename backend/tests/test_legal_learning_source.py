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
