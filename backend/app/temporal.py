"""Conservative selection by source effective dates; never infer legal repeal."""
from datetime import date, datetime


def civil_date(value):
    if isinstance(value, date):
        return value.date() if isinstance(value, datetime) else value
    if not isinstance(value, str):
        raise ValueError('Fecha civil no disponible')
    if len(value) == 8 and value.isdigit():
        return datetime.strptime(value, '%Y%m%d').date()
    return date.fromisoformat(value)


def resolve_block(block, as_of):
    target = civil_date(as_of)
    versions = block.get('versions', [])
    result = {'id': block['id'], 'title': block.get('title', block['id']),
              'asOf': target.isoformat(), 'selectedVersion': None,
              'status': 'unresolved', 'legalInterpretation': False}
    candidates = []
    for version in versions:
        try:
            starts = civil_date(version.get('effectiveFrom'))
            ends = civil_date(version['effectiveTo']) if version.get('effectiveTo') else None
            if ends is not None and ends <= starts:
                raise ValueError('Intervalo contradictorio')
        except (ValueError, TypeError):
            return {**result, 'reason': 'missing_or_invalid_effective_date'}
        candidates.append((starts, ends, version))
    applicable = [(start, end, v) for start, end, v in candidates if start <= target and (end is None or target < end)]
    if not applicable:
        return {**result, 'status': 'unavailable', 'reason': 'no_source_version_for_date'}
    latest_start = max(start for start, _, _ in applicable)
    latest = [v for start, _, v in applicable if start == latest_start]
    # Two different texts with the same effective date require editorial resolution.
    if len({v.get('hash') or v.get('text') for v in latest}) > 1:
        return {**result, 'reason': 'conflicting_versions_same_date'}
    next_dates = sorted(start for start, _, _ in candidates if start > target)
    return {**result, 'status': 'selected_by_source_date', 'selectedVersion': latest[0],
            'nextEffectiveFrom': next_dates[0].isoformat() if next_dates else None,
            'warning': 'Selección según fechas de la fuente. Revisa vigencias parciales y disposiciones transitorias; no es un dictamen de vigencia.'}
