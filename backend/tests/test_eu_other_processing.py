import io
import json
import pytest
from app.eu_other_processing import xml_paragraphs,write_document
from app.eu_processing import ExtractionError


def test_formex_articles_and_paragraphs_not_manifest_metadata():
    raw=b'<ACT><ARTICLE><TI.ART>Art\xc3\xadculo 1</TI.ART><PARAG><NO.PARAG>1.</NO.PARAG><ALINEA>Una regla de datos.</ALINEA></PARAG></ARTICLE></ACT>'
    paragraphs=list(xml_paragraphs(raw))
    assert [p['text'] for p in paragraphs]==['Artículo 1','1. Una regla de datos.']
    with pytest.raises(ExtractionError,match='xml_manifest_metadata_only'):list(xml_paragraphs(b'<DOC><NO.CELEX>32000R0001</NO.CELEX></DOC>'))


def test_source_writer_keeps_pdf_page_and_review_status():
    out=io.BytesIO();metadata={'language':'es','legalReview':'not_performed','unitsAreLegalArticles':False}
    write_document(iter([{'text':'Artículo 1','sourcePage':2}]),metadata,out)
    doc=json.loads(out.getvalue())
    assert doc['paragraphs'][0]['sourcePage']==2
    assert doc['unitsAreLegalArticles'] is False


def test_xml_entities_are_not_expanded():
    from defusedxml.common import DefusedXmlException
    raw=b'<!DOCTYPE ACT [<!ENTITY x "expanded">]><ACT><ARTICLE><ALINEA>&x;</ALINEA></ARTICLE></ACT>'
    with pytest.raises(DefusedXmlException):list(xml_paragraphs(raw))


def test_real_pdf_converter_preserves_page_reference(tmp_path):
    import shutil
    from app.eu_other_processing import pdf_paragraphs
    if not shutil.which('pdftotext'):pytest.skip('poppler converter unavailable')
    content=b'BT /F1 12 Tf 30 700 Td (Articulo 1) Tj 0 -20 Td (This source rule contains sufficient readable text to verify actual PDF extraction.) Tj ET'
    objects=[b'<< /Type /Catalog /Pages 2 0 R >>',b'<< /Type /Pages /Kids [3 0 R] /Count 1 >>',b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>',b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',b'<< /Length '+str(len(content)).encode()+b' >>\nstream\n'+content+b'\nendstream']
    data=bytearray(b'%PDF-1.4\n');offsets=[]
    for i,obj in enumerate(objects,1):
        offsets.append(len(data));data.extend(str(i).encode()+b' 0 obj\n'+obj+b'\nendobj\n')
    xref=len(data);data.extend(b'xref\n0 6\n0000000000 65535 f \n')
    for offset in offsets:data.extend(f'{offset:010d} 00000 n \n'.encode())
    data.extend(b'trailer\n<< /Size 6 /Root 1 0 R >>\nstartxref\n'+str(xref).encode()+b'\n%%EOF\n')
    path=tmp_path/'source.pdf';path.write_bytes(data);metadata={}
    rows=list(pdf_paragraphs(path,metadata))
    assert rows[0]['text']=='Articulo 1' and all(r['sourcePage']==1 for r in rows)
    assert metadata['lastTextPage']==1 and metadata['qualityWarnings']==[]


def test_formex_zip_recovery_reads_members_instead_of_zip_headers(tmp_path):
    import zipfile
    from app.eu_format_recovery import zip_formex_stream
    path=tmp_path/'source.zip'
    with zipfile.ZipFile(path,'w') as package:
        package.writestr('index.xml','<DOC><NO.CELEX>32000R0001</NO.CELEX></DOC>')
        package.writestr('act.xml','<ACT><ARTICLE><TI.ART>Artículo 1</TI.ART><PARAG>Una regla.</PARAG></ARTICLE></ACT>')
    rows=list(zip_formex_stream(path))
    assert [p['text'] for p in rows]==['Artículo 1','Una regla.']
    assert all(p['sourceContainer']=='act.xml' for p in rows)


def test_formex_correction_preserves_body_and_excludes_bibliography(tmp_path):
    from app.eu_format_recovery import formex_stream
    path=tmp_path/'correction.xml'
    path.write_text('<CORR><BIB.INSTANCE><TITLE>Metadatos</TITLE></BIB.INSTANCE><TITLE>Corrección de errores</TITLE><P>Donde dice A debe decir B.</P><ROW><CELL><P>Fecha</P></CELL><CELL>Valor</CELL></ROW></CORR>')
    assert [p['text'] for p in formex_stream(path)]==['Corrección de errores','Donde dice A debe decir B.','Fecha Valor']
