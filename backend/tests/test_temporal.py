import pytest
from app.temporal import civil_date, resolve_block
from app.db import Record
from app.main import create_app
from fastapi.testclient import TestClient


def block(*versions):
    return {'id': 'stable-a1', 'title': 'Artículo 1', 'versions': list(versions)}


def v(start, text, **kw):
    return {'effectiveFrom': start, 'text': text, **kw}


def test_future_reform_does_not_replace_current_text():
    b = block(v('20250101', 'Anterior', publicationDate='20241201'),
              v('20270101', 'Futura', publicationDate='20261101'))
    result = resolve_block(b, '2026-11-04')
    assert result['selectedVersion']['text'] == 'Anterior'
    assert result['nextEffectiveFrom'] == '2027-01-01'
    assert result['legalInterpretation'] is False


def test_effective_boundary_is_inclusive_and_old_text_preserved():
    b = block(v('20250101', 'A'), v('20260101', 'B'))
    assert resolve_block(b, '2026-01-01')['selectedVersion']['text'] == 'B'
    assert resolve_block(b, '2025-12-31')['selectedVersion']['text'] == 'A'
    assert b['versions'][0]['text'] == 'A'


def test_missing_date_is_not_guessed_from_publication():
    b = block(v('20250101', 'A'), {'publicationDate': '20260101', 'text': 'Unknown'})
    result = resolve_block(b, '2026-11-04')
    assert result['status'] == 'unresolved'
    assert result['selectedVersion'] is None


def test_same_date_conflict_requires_editorial_resolution():
    b = block(v('20250101', 'A'), v('20250101', 'B'))
    assert resolve_block(b, '2026-11-04')['reason'] == 'conflicting_versions_same_date'


def test_before_history_and_expired_version_are_unavailable():
    b = block(v('20250101', 'A', effectiveTo='20260101'))
    assert resolve_block(b, '2024-12-31')['selectedVersion'] is None
    assert resolve_block(b, '2026-01-01')['selectedVersion'] is None


def test_invalid_dates_and_intervals():
    with pytest.raises(ValueError): civil_date('2026-02-30')
    assert resolve_block(block(v('bad', 'A')), '2026-11-04')['status'] == 'unresolved'
    assert resolve_block(block(v('20260101', 'A', effectiveTo='20250101')), '2026-11-04')['status'] == 'unresolved'


def test_historical_units_http_contract(tmp_path):
    app = create_app('sqlite:///' + str(tmp_path / 'db'))
    with app.state.factory() as s:
        s.add(Record(id='version1', kind='norm_version', data={'normId': 'law1', 'blocks': [block(v('20250101', 'A'), v('20270101', 'B'))]}))
        s.commit()
    client = TestClient(app)
    response = client.get('/v1/library/norms/law1/units?version=version1&asOf=2026-11-04')
    assert response.status_code == 200
    assert response.json()['resolvedUnits'][0]['selectedVersion']['text'] == 'A'
    assert response.json()['unresolvedCount'] == 0
    assert client.get('/v1/library/norms/law1/units?version=version1&asOf=bad').status_code == 422
