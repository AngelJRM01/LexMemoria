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
  if (versions.isEmpty || requiresLegalContextReview(versions.last)) {
    return false;
  }
  final text = (versions.last['text'] as String? ?? '').trim();
  if (text.length > 80) return true;
  return text.isNotEmpty &&
      !RegExp(r'^\(?\s*(?:derogad[oa]|suprimid[oa]|sin contenido)\s*[.)]*$',
              caseSensitive: false)
          .hasMatch(text);
}

class _LegalContent {
  final String body;
  final List<String> notes;
  _LegalContent(this.body, this.notes);
}

final _legalContentCache = Expando<_LegalContent>();
_LegalContent _legalContent(Map version) {
  final cached = _legalContentCache[version];
  if (cached != null) return cached;
  final original = version['text'] as String? ?? '';
  final markup = version['xml'] as String? ?? '';
  if (!markup.contains('nota_pie')) return _LegalContent(original, const []);
  final document = XmlDocument.parse(markup);
  bool noteParagraph(XmlElement p) =>
      p.name.local == 'p' &&
      (p.getAttribute('class') ?? '').split(' ').contains('nota_pie');
  final candidates = document.descendants
      .whereType<XmlElement>()
      .where((e) =>
          noteParagraph(e) ||
          (e.name.local == 'blockquote' &&
              e.findAllElements('p').firstOrNull is XmlElement &&
              noteParagraph(e.findAllElements('p').first)))
      .toSet();
  final nodes =
      candidates.where((e) => !e.ancestors.any(candidates.contains)).toList();
  final notes =
      nodes.map((n) => n.innerText.trim()).where((n) => n.isNotEmpty).toList();
  for (final note in nodes) {
    note.parent?.children.remove(note);
  }
  final body = document.rootElement.childElements
      .map((e) => e.innerText.trim())
      .where((v) => v.isNotEmpty)
      .join('\n');
  final result = _LegalContent(body, notes);
  _legalContentCache[version] = result;
  return result;
}

String legalBodyText(Map version) =>
    version['bodyParser'] == 'boe-editorial-2' && version['bodyText'] is String
        ? version['bodyText']
        : _legalContent(version).body;
List<String> legalEditorialNotes(Map version) =>
    version['bodyParser'] == 'boe-editorial-2' &&
            version['editorialNotes'] is List
        ? List<String>.from(version['editorialNotes'])
        : _legalContent(version).notes;
final _reviewNote = RegExp(
    r'inconstitucional|constitucionalidad|nulidad|suspendid|suspension|sentencia.*interpret|interpret.*sentencia|inaplicab',
    caseSensitive: false);
bool requiresLegalContextReview(Map version) =>
    RegExp(r'redacci[oó]n anterior\s*:', caseSensitive: false)
        .hasMatch(legalBodyText(version)) ||
    legalEditorialNotes(version)
        .any((note) => _reviewNote.hasMatch(normalize(note)));

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
