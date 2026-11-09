import hashlib
import io
import json
import pytest
from app.eu_large_html import extract_stream
from app.eu_processing import extract_html,ExtractionError


def test_streaming_preserves_paragraphs_and_multibyte_characters_across_chunks():
    raw=('<html><head><title>Ignorar</title></head><body><p id="a">Artículo 1</p>'
         '<p>La protección de datos será efectiva y útil para todas las personas.</p>'
         '<p>Una línea<br>otra línea y símbolo €.</p></body></html>').encode()
    output=io.BytesIO();digest,count=extract_stream(io.BytesIO(raw),output,'text/html',hashlib.sha256(raw).hexdigest(),chunk_size=1)
    result=json.loads(output.getvalue())
    assert result['paragraphs']==extract_html(raw,'text/html')['paragraphs']
    assert digest==hashlib.sha256(output.getvalue()).hexdigest()
    assert count==3 and result['unitsAreLegalArticles'] is False


def test_wrong_original_hash_is_rejected():
    raw=b'<html><body><p>A sufficiently long paragraph that contains over forty characters.</p></body></html>'
    with pytest.raises(ExtractionError,match='source_hash_mismatch'):
        extract_stream(io.BytesIO(raw),io.BytesIO(),'text/html','invalid')


def test_text_outside_paragraph_tags_does_not_split_into_characters():
    raw='<html><body>Un texto histórico completo sin etiquetas de párrafo.<p>Otra frase con protección.</p></body></html>'.encode()
    out=io.BytesIO()
    extract_stream(io.BytesIO(raw),out,'text/html',hashlib.sha256(raw).hexdigest(),chunk_size=1)
    assert json.loads(out.getvalue())['paragraphs']==extract_html(raw,'text/html')['paragraphs']
