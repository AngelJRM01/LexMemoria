import 'models.dart';

int preferredEuropeanEdition(List<Json> versions, DateTime today) {
  if (versions.isEmpty) return -1;
  final now = civilDate(today);
  final candidates = <int>[];
  for (var i = 0; i < versions.length; i++) {
    final v = versions[i];
    if (v['kind'] == 'correction') continue;
    if (v['date'] is String && (v['date'] as String).compareTo(now) > 0) {
      continue;
    }
    candidates.add(i);
  }
  candidates.sort((a, b) => (versions[b]['date'] as String? ?? '')
      .compareTo(versions[a]['date'] as String? ?? ''));
  if (candidates.isNotEmpty) return candidates.first;
  return 0;
}

String europeanEditionLabel(Json version) {
  final label = version['kind'] == 'consolidated'
      ? 'Texto consolidado'
      : version['kind'] == 'correction'
          ? (version['celex'] is String
              ? 'Corrección · ${version['celex']}'
              : 'Corrección de errores')
          : 'Texto original';
  return version['date'] == null
      ? label
      : '$label · ${displayDate(version['date'])}';
}

bool europeanLiteralStudyAllowed(
    Json norm, Json edition, List<Json> documents) {
  if (![
        'Reglamento',
        'Directiva',
        'Decisión',
        'Tratado',
        'Acuerdo internacional'
      ].contains(norm['kind']) ||
      edition['kind'] == 'correction') {
    return false;
  }
  final title = normalize(norm['title'].toString());
  final change =
      RegExp(r'por (?:el|la) que se (?:modifica|deroga|rectifica|corrige)')
          .firstMatch(title);
  if (change != null &&
      !RegExp(r'relativ[oa]|se establece')
          .hasMatch(title.substring(0, change.start))) {
    return false;
  }
  return documents.any((d) =>
      d['sourceParser'] == 'eu-html-leaf-paragraphs-2' &&
      (d['warnings'] as List).isEmpty &&
      (d['units'] as List).any((u) => u['kind'] == 'article_candidate'));
}

/// A missed heading must never merge a second article or annex into a card.
bool europeanArticleParagraphsAllowed(List<Json> paragraphs) {
  final heading = RegExp(
      r'^(?:(?:art[íi]culo|article|art\.?)\s+|anexo(?:\s|$)|(?:t[íi]tulo|cap[íi]tulo|secci[óo]n|parte)\s+[ivxlcdm\d]+(?:\s|$))',
      caseSensitive: false,
      multiLine: true);
  return paragraphs
      .skip(1)
      .every((p) => !heading.hasMatch(p['text'].toString().trim()));
}
