import 'models.dart';
import 'package:xml/xml.dart';

final articleLabel =
    RegExp(r'^(?:art[íi]culo|art\.?)\s+', caseSensitive: false);
String legalUnitKind(Json unit) {
  final title = unit['title'].toString().trim();
  final type = normalize(unit['type'] ?? '');
  if (type == 'encabezado') return 'heading';
  if (type == 'firma') return 'signature';
  if (type == 'nota inicial' || type == 'nota_inicial') return 'editorial_note';
  if (type == 'preambulo') return 'preamble';
  if (articleLabel.hasMatch(title)) return 'article';
  final value = normalize(title);
  if (value.contains('preambulo') ||
      value.startsWith('exposicion de motivos')) {
    return 'preamble';
  }
  if (value.startsWith('disposicion') || value.startsWith('disposiciones')) {
    return 'provision';
  }
  if (value.startsWith('anexo') || value.startsWith('apendice')) return 'annex';
  return 'other';
}

bool studyArticle(Json unit) {
  if (legalUnitKind(unit) != 'article') return false;
  final versions = unit['versions'] as List? ?? [];
  if (versions.isEmpty) return false;
  final text = (versions.last['text'] as String? ?? '').trim();
  if (text.length > 80) return true;
  return text.isNotEmpty &&
      !RegExp(r'^\(?\s*(?:derogad[oa]|suprimid[oa]|sin contenido)\s*[.)]*$',
              caseSensitive: false)
          .hasMatch(text);
}

final _bodyCache = Expando<String>();
String legalBodyText(Map version) {
  if (version['bodyText'] is String) return version['bodyText'];
  final cached = _bodyCache[version];
  if (cached != null) return cached;
  final original = version['text'] as String? ?? '';
  final markup = version['xml'] as String? ?? '';
  if (!markup.contains('nota_pie')) return original;
  final document = XmlDocument.parse(markup);
  for (final note in document
      .findAllElements('p')
      .where((p) => p.getAttribute('class') == 'nota_pie')
      .toList()) {
    note.parent?.children.remove(note);
  }
  final result = document.rootElement.childElements
      .map((e) => e.innerText.trim())
      .where((v) => v.isNotEmpty)
      .join('\n');
  _bodyCache[version] = result;
  return result;
}

Map<String, String> legalUnitContexts(List<Json> units) {
  final levels = <int, String>{};
  final result = <String, String>{};
  for (final unit in units) {
    if (legalUnitKind(unit) == 'heading') {
      final title = unit['title'].toString();
      final normalized = normalize(title);
      final rank = normalized.startsWith('libro')
          ? 10
          : normalized.startsWith('titulo')
              ? 20
              : normalized.startsWith('capitulo')
                  ? 30
                  : normalized.startsWith('seccion')
                      ? 40
                      : normalized.startsWith('subseccion')
                          ? 50
                          : 0;
      levels.removeWhere((key, value) => key >= rank);
      levels[rank] = title;
    } else if (legalUnitKind(unit) == 'article') {
      result[unit['id']] =
          (levels.keys.toList()..sort()).map((k) => levels[k]!).join(' · ');
    }
  }
  return result;
}
