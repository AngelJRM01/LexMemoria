import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'legal_units.dart';

final articleHeading =
    RegExp(r'^(?:Art[íi]culo|Art\.?)\s', caseSensitive: false);
String sourceComparable(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

List<String> literalChunks(String title, String text) {
  final paragraphs =
      text.split('\n').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  if (paragraphs.isNotEmpty && paragraphs.first == title.trim()) {
    paragraphs.removeAt(0);
  }
  final pieces = <String>[];
  for (final paragraph in paragraphs) {
    var start = 0;
    while (start < paragraph.length) {
      var boundary = start;
      // Advance in Unicode code points without rescanning or copying the
      // remaining paragraph. Legal tables can contain very long paragraphs.
      for (var count = 0;
          count < 1200 && boundary < paragraph.length;
          count++) {
        final first = paragraph.codeUnitAt(boundary++);
        if (first >= 0xd800 && first <= 0xdbff && boundary < paragraph.length) {
          final second = paragraph.codeUnitAt(boundary);
          if (second >= 0xdc00 && second <= 0xdfff) boundary++;
        }
      }
      if (boundary == paragraph.length) {
        pieces.add(paragraph.substring(start));
        break;
      }
      var cut =
          start + paragraph.substring(start, boundary + 1).lastIndexOf(' ');
      if (cut <= start) cut = boundary;
      pieces.add(paragraph.substring(start, cut));
      start = cut;
      while (start < paragraph.length && paragraph[start].trim().isEmpty) {
        start++;
      }
    }
  }
  final chunks = <String>[];
  var buffer = '';
  for (final piece in pieces) {
    if (buffer.isNotEmpty &&
        buffer.runes.length + 1 + piece.runes.length > 1200) {
      chunks.add(buffer);
      buffer = '';
    }
    buffer = buffer.isEmpty ? piece : '$buffer\n$piece';
  }
  if (buffer.isNotEmpty) chunks.add(buffer);
  return chunks;
}

/// Short contiguous extracts. QA retains its original full-reference chunks.
List<String> exercisePassages(String title, String text,
    {bool paragraphsOnly = true}) {
  final paragraphs =
      text.split('\n').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  if (paragraphs.isNotEmpty && paragraphs.first == title.trim()) {
    paragraphs.removeAt(0);
  }
  final result = <String>[];
  for (final paragraph
      in paragraphsOnly ? paragraphs : [paragraphs.join('\n')]) {
    if (paragraph.runes.length <= 320) {
      if (paragraph.length >= 35) result.add(paragraph);
      continue;
    }
    var prefix = '';
    for (final sentence in paragraph.split(RegExp(r'(?<=[.;!?])\s+'))) {
      final part =
          prefix.isEmpty ? sentence.trim() : '$prefix ${sentence.trim()}';
      prefix = '';
      if (part.length < 35) {
        prefix = part;
        continue;
      }
      // Never manufacture a rule by cutting a sentence in the middle.
      if (part.runes.length <= 320) result.add(part);
    }
  }
  return result;
}

List<String> _legacyPassages(String title, String text,
    {bool paragraphsOnly = true}) {
  final result = <String>[];
  for (final block in literalChunks(title, text)) {
    for (final paragraph in paragraphsOnly ? block.split('\n') : [block]) {
      var remaining = paragraph.trim();
      while (remaining.isNotEmpty) {
        if (remaining.runes.length <= 320) {
          if (remaining.length >= 35) result.add(remaining);
          break;
        }
        final prefix = String.fromCharCodes(remaining.runes.take(321));
        var cut = -1;
        for (final match in RegExp(r'[.;!?]\s').allMatches(prefix)) {
          if (match.start >= 100 && match.end <= prefix.length - 1) {
            cut = match.start + 1;
          }
        }
        if (cut < 0) cut = prefix.lastIndexOf(' ');
        if (cut <= 0) {
          cut = String.fromCharCodes(remaining.runes.take(320)).length;
        }
        final piece = remaining.substring(0, cut).trim();
        if (piece.length >= 35) result.add(piece);
        remaining = remaining.substring(cut).trimLeft();
      }
    }
  }
  return result;
}

class _Target {
  final int start, end;
  final String answer;
  final int weight;
  const _Target(this.start, this.end, this.answer, this.weight);
}

final _quantity = RegExp(
    r'\b(?:\d+|un|una|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|catorce|quince|veinte|veintiuno|veinticuatro|treinta|sesenta)[ \t\u00a0]+(?:días?|mes(?:es)?|años?|horas?|semanas?|euros?)\b',
    unicode: true,
    caseSensitive: false);

final _money = RegExp(
    r'\b\d+(?:[ \u00a0]\d{3})*(?:[.,]\d+)?[ \t\u00a0]+(?:EUR|euros?)\b',
    unicode: true,
    caseSensitive: false);
final _percentage = RegExp(r'\b\d+(?:[.,]\d+)?[ \t\u00a0]*%', unicode: true);

const _institutions = [
  'Comisión Europea',
  'Parlamento Europeo',
  'Consejo Europeo',
  'Consejo de la Unión Europea',
  'Tribunal de Justicia de la Unión Europea',
  'Comité Europeo de Protección de Datos',
  'Supervisor Europeo de Protección de Datos',
  'Banco Central Europeo',
  'Tribunal Constitucional',
  'Tribunal Supremo',
  'Congreso de los Diputados',
  'Cortes Generales',
  'Consejo de Ministros',
  'Ministerio Fiscal',
  'Consejo General del Poder Judicial',
  'Administración pública',
  'Administraciones públicas',
  'Gobierno',
  'Senado',
  'Juez',
  'Tribunal'
];
const _concepts = [
  'protección de datos personales',
  'datos personales',
  'datos genéticos',
  'datos biométricos',
  'datos relativos a la salud',
  'responsable del tratamiento',
  'responsables del tratamiento',
  'encargado del tratamiento',
  'encargados del tratamiento',
  'autoridad de control',
  'autoridades de control',
  'autoridad competente',
  'autoridades competentes',
  'consentimiento explícito',
  'interesado',
  'interesada',
  'interesados',
  'interesadas',
  'seudonimización',
  'derecho de acceso',
  'derecho de rectificación',
  'derecho de supresión',
  'derecho de oposición',
  'portabilidad de los datos',
  'limitación del tratamiento',
  'minimización de datos',
  'limitación de la finalidad',
  'limitación del plazo de conservación',
  'integridad y confidencialidad',
  'licitud, lealtad y transparencia',
  'transferencias internacionales',
  'interés público',
  'intereses vitales',
  'obligación legal',
  'ejercicio de poderes públicos',
  'Estado miembro',
  'Estados miembros',
  'Derecho de la Unión',
  'Derecho nacional',
  'derechos y libertades fundamentales',
  'mercado interior',
  'libre circulación',
  'cooperación judicial',
  'derechos fundamentales',
  'garantías constitucionales',
  'procedimientos administrativos',
  'tutela judicial efectiva',
  'presunción de inocencia',
  'seguridad jurídica',
  'responsabilidad patrimonial',
  'libertad ideológica',
  'libertad religiosa',
  'libertad de expresión',
  'libertad sindical',
  'libertad personal',
  'igualdad ante la ley',
  'derecho de defensa',
  'derecho de reunión',
  'derecho de asociación',
  'derecho de petición',
  'derecho de huelga',
  'sufragio universal',
  'propiedad privada',
  'interés general',
  'orden público',
  'fuerza mayor',
  'buena fe',
  'cosa juzgada',
  'recurso de amparo',
  'recurso de apelación',
  'recurso de casación',
  'silencio administrativo',
  'procedimiento administrativo',
  'acto administrativo',
  'prescripción',
  'caducidad',
  'competencia',
  'consentimiento',
  'domicilio',
  'nacionalidad',
  'inviolabilidad',
  'imparcialidad',
  'legalidad',
  'irretroactividad',
  'publicidad',
  'proporcionalidad',
  'indemnización',
  'notificación',
  'motivación'
];
String targetCategory(String answer) {
  if (_money.hasMatch(answer)) return 'amount';
  if (_percentage.hasMatch(answer)) return 'percentage';
  if (_quantity.hasMatch(answer)) {
    return RegExp(r'euros?', caseSensitive: false).hasMatch(answer)
        ? 'amount'
        : 'duration';
  }
  if (_institutions.any((v) => normalize(v) == normalize(answer))) {
    return 'institution';
  }
  return 'concept';
}

final _legalTermPattern = (() {
  final terms = [..._institutions, ..._concepts]
    ..sort((a, b) => b.length.compareTo(a.length));
  return RegExp(
      r'(?<![\p{L}])(?:' + terms.map(RegExp.escape).join('|') + r')(?![\p{L}])',
      unicode: true,
      caseSensitive: false);
})();
List<_Target> _targets(String text, {int limit = 100}) {
  final found = <_Target>[];
  for (final pattern in [_money, _quantity, _percentage]) {
    for (final m in pattern.allMatches(text).take(limit)) {
      if (found.any((t) => m.start < t.end && m.end > t.start)) continue;
      found.add(_Target(m.start, m.end, m.group(0)!, 4));
      if (found.length >= limit) return found;
    }
  }
  for (final m in _legalTermPattern.allMatches(text)) {
    if (found.any((t) => m.start < t.end && m.end > t.start)) continue;
    final answer = m.group(0)!;
    found.add(_Target(m.start, m.end, answer, answer.contains(' ') ? 3 : 2));
    if (found.length >= limit) break;
  }
  return found;
}

List<_Target> _uniqueTargets(String text) {
  final lower = text.toLowerCase();
  return _targets(text).where((t) {
    final answer = t.answer.toLowerCase();
    return lower.indexOf(answer) == lower.lastIndexOf(answer);
  }).toList()
    ..sort((a, b) => b.weight != a.weight
        ? b.weight.compareTo(a.weight)
        : a.start.compareTo(b.start));
}

/// All answers come from the cited source. Tests ask for an omitted literal
/// expressions; distractors are other source expressions, never invented rules.
List<Json> buildLiteralCards(Json input) {
  final norm = Json.from(input['norm']);
  final units = (input['units'] as List).map((u) => Json.from(u)).toList();
  final format = input['format'] as String? ?? 'qa';
  if (!['qa', 'cloze', 'test', 'reference'].contains(format)) {
    throw ArgumentError('Formato no disponible');
  }
  final eligible = units.where(studyArticle).toList();
  final title = friendlyNormLabel(norm);
  final custom = (input['deck'] as String? ?? '').trim();
  var label = custom.isNotEmpty
      ? custom
      : '$title${norm['exhausted'] == true ? ' · histórico' : ''}${format == 'cloze' ? ' · Huecos' : format == 'test' ? ' · Test literal' : format == 'reference' ? ' · Artículos' : ''}';
  if (label.length > 160) label = '${label.substring(0, 159)}…';
  final referenceTitles =
      eligible.map((u) => u['title'].toString()).toSet().toList();
  final titleCounts = <String, int>{};
  final referenceTexts = <String, String>{};
  final referenceChoices = <String, List<String>>{};
  for (final unit in eligible) {
    final key = sourceComparable(unit['title']);
    titleCounts[key] = (titleCounts[key] ?? 0) + 1;
    if (format == 'reference' && (unit['versions'] as List).isNotEmpty) {
      referenceTexts[unit['title']] =
          sourceComparable(unit['versions'].last['text'] ?? '');
    }
  }
  final result = <Json>[];
  final globalPool = <String>[];
  final globalSeen = <String>{};
  if (format == 'test') {
    for (final u in eligible) {
      if (globalPool.length >= 512) break;
      for (final t in _targets(legalBodyText(u['versions'].last), limit: 64)) {
        if (globalSeen.add(t.answer)) globalPool.add(t.answer);
        if (globalPool.length >= 512) break;
      }
    }
  }
  for (final unit in eligible) {
    final versions = unit['versions'] as List;
    if (versions.isEmpty) continue;
    final version = Json.from(versions.last);
    final displayUnit =
        '${unit['title']}${(titleCounts[sourceComparable(unit['title'])] ?? 0) > 1 ? ' [${unit['id']}]' : ''}';
    final chunks = exercisePassages(unit['title'], legalBodyText(versions.last),
        paragraphsOnly: format != 'reference');
    final localPool = format == 'test'
        ? _targets(legalBodyText(versions.last), limit: 64)
            .map((t) => t.answer)
            .toList()
        : <String>[];
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final seed =
          "lexmemoria:${norm['id']}:${norm['latestVersion']}:${unit['id']}:$i";
      final cue = chunk.split(RegExp(r'\s+')).take(5).join(' ');
      var front =
          'Completa de memoria esta regla de $displayUnit de $title.\n\n$cue…';
      var back = chunk;
      final options = <String>[];
      int? correct;
      if (format == 'reference') {
        if (titleCounts[sourceComparable(unit['title'])] != 1) continue;
        final quote = sourceComparable(chunk);
        final titles = referenceChoices.putIfAbsent(
            quote,
            () => referenceTitles
                .where((t) =>
                    titleCounts[sourceComparable(t)] == 1 &&
                    !referenceTexts[t]!.contains(quote))
                .take(3)
                .toList());
        if (titles.length < 3) continue;
        back = unit['title'];
        front =
            'En $title, ¿cuál de estos artículos o apartados contiene este fragmento?\n\n$chunk';
        final choices = <String>[back, ...titles];
        final shift = sha256.convert(utf8.encode(seed)).bytes.first % 4;
        options.addAll([...choices.skip(shift), ...choices.take(shift)]);
        correct = options.indexOf(back);
      } else if (format != 'qa') {
        final candidates = _uniqueTargets(chunk);
        if (candidates.isEmpty) continue;
        if (format == 'cloze') {
          final targets = <_Target>[];
          var covered = 0;
          for (final target in candidates) {
            if (targets
                .any((t) => target.start < t.end && target.end > t.start)) {
              continue;
            }
            if (target.answer.length > chunk.length * .25 ||
                covered + target.answer.length > chunk.length * .45) {
              continue;
            }
            targets.add(target);
            covered += target.answer.length;
            if (targets.length == (chunk.length >= 200 ? 3 : 2)) break;
          }
          if (targets.length < 2) continue;
          targets.sort((a, b) => a.start.compareTo(b.start));
          var masked = chunk;
          for (var j = targets.length - 1; j >= 0; j--) {
            final t = targets[j];
            masked = masked.replaceRange(
                t.start, t.end, '{{c${j + 1}::${t.answer}}}');
          }
          front =
              'Completa los ${targets.length} huecos · $displayUnit · $title\n\n$masked';
          back = targets
              .asMap()
              .entries
              .map((e) => '${e.key + 1}. ${e.value.answer}')
              .join('\n');
        } else {
          final target = candidates.first;
          back = target.answer;
          final alternatives = <String>[];
          for (final value in candidates
              .skip(1)
              .map((t) => t.answer)
              .followedBy(localPool)
              .followedBy(globalPool)) {
            if (normalize(value) == normalize(back) ||
                alternatives.any((v) => normalize(v) == normalize(value))) {
              continue;
            }
            if (value.length > 64 ||
                targetCategory(value) != targetCategory(back) ||
                sourceComparable(chunk).contains(sourceComparable(value)) ||
                normalize(value).contains(normalize(back)) ||
                normalize(back).contains(normalize(value))) {
              continue;
            }
            alternatives.add(value);
            if (alternatives.length == 3) break;
          }
          if (alternatives.length < 3) continue;
          final choices = [back, ...alternatives];
          final shift = sha256.convert(utf8.encode(seed)).bytes.first % 4;
          options.addAll([...choices.skip(shift), ...choices.take(shift)]);
          correct = options.indexOf(back);
          front =
              '¿Qué expresión completa este fragmento de $displayUnit? · $title\n\n${chunk.replaceRange(target.start, target.end, '_____')}';
        }
      }

      final idSeed =
          '$seed:$format-v3${custom.isEmpty ? '' : ':group:$custom'}';
      result.add(StudyCard(
              id: const Uuid()
                  .v5('6ba7b811-9dad-11d1-80b4-00c04fd430c8', idSeed),
              deck: label,
              front: front,
              back: back,
              explanation: format == 'qa'
                  ? 'Respuesta literal de la fuente. Fecha de efecto: ${displayDate(version['effectiveFrom'])}.'
                  : 'Texto de referencia:\n$chunk\n\nEjercicio de recuerdo literal; no evalúa interpretación jurídica.',
              type: format == 'reference' ? 'test' : format,
              normId: norm['id'],
              unitId: unit['id'],
              versionId: norm['latestVersion'],
              unitVersionHash: version['hash'] ?? '',
              editorialState: 'source_literal',
              options: options,
              correct: correct)
          .toJson());
    }
  }
  return result;
}

Json buildPreparedInstallation(Json input) {
  final prepared = buildLiteralCards(input);
  final format = input['format'] ?? 'qa';
  final legacy = <String>[];
  {
    final norm = Json.from(input['norm']);
    final group = (input['deck'] as String? ?? '').trim();
    for (final unit in input['units'] as List) {
      final versions = unit['versions'] as List;
      if (versions.isEmpty) continue;
      final oldText = versions.last['text'] ?? '';
      final a = literalChunks(unit['title'], oldText).length;
      final b = _legacyPassages(unit['title'], oldText,
              paragraphsOnly: format != 'reference')
          .length;
      final chunks = List.filled(a > b ? a : b, '');
      for (var i = 0; i < chunks.length; i++) {
        final seed =
            "lexmemoria:${norm['id']}:${norm['latestVersion']}:${unit['id']}:$i:$format-v1${group.isEmpty ? '' : ':group:$group'}";
        legacy
            .add(const Uuid().v5('6ba7b811-9dad-11d1-80b4-00c04fd430c8', seed));
        final v2 = seed.replaceFirst(':$format-v1', ':$format-v2');
        legacy.add(const Uuid().v5('6ba7b811-9dad-11d1-80b4-00c04fd430c8', v2));
        if (format == 'qa') {
          legacy.add(const Uuid().v5('6ba7b811-9dad-11d1-80b4-00c04fd430c8',
              seed.replaceFirst(':qa-v1', '')));
        }
      }
    }
  }
  return {'cards': prepared, 'legacyIds': legacy};
}
