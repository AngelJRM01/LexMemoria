import hashlib
import io
import json
from app.eu_leaf_processing import LeafParagraphs,PARSER
from app.eu_large_html import extract_stream
from app.eu_processing import extract_html
from app.eu_structure import structure_document


def test_nested_layout_table_does_not_swallow_article_boundaries():
    raw=('<html><body><table><tr><td><p>HA ADOPTADO EL PRESENTE REGLAMENTO:</p>'
         '<p id="a1">Artículo 1</p><p>Una regla de protección suficientemente extensa.</p>'
         '<p>Artículo 2</p><p>Otra regla de protección de las personas.</p></td></tr></table></body></html>').encode()
    assert len(extract_html(raw,'text/html')['paragraphs'])==1
    out=io.BytesIO();extract_stream(io.BytesIO(raw),out,'text/html',hashlib.sha256(raw).hexdigest(),chunk_size=1,parser_class=LeafParagraphs,parser_version=PARSER)
    doc=json.loads(out.getvalue());structured=structure_document(doc,'32000R0001','source')
    assert [u['title'] for u in structured['units'] if u['kind']=='article_candidate']==['Artículo 1','Artículo 2']
    assert doc['paragraphs'][1]['sourceAnchor']=='a1'
    assert sum(p['text'].count('Una regla') for p in doc['paragraphs'])==1


def test_parent_text_and_explicit_line_breaks_preserve_order():
    raw='<html><body><div>Texto inicial suficientemente largo.</div><td>Prefijo<p>Artículo 1</p>Regla<br>Continuación</td></body></html>'.encode()
    out=io.BytesIO();extract_stream(io.BytesIO(raw),out,'text/html',hashlib.sha256(raw).hexdigest(),parser_class=LeafParagraphs)
    texts=[p['text'] for p in json.loads(out.getvalue())['paragraphs']]
    assert texts==['Texto inicial suficientemente largo.','Prefijo','Artículo 1','Regla','Continuación']
