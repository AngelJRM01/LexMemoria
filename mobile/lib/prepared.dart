import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'models.dart';

final articleHeading =
    RegExp(r'^(?:Art[íi]culo|Art\.?)\s', caseSensitive: false);
final literalWord = RegExp(r"\p{L}[\p{L}\p{M}·’'-]{5,}", unicode: true);
String sourceComparable(String value) =>
    value.replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

List<String> literalChunks(String title, String text) {
  final paragraphs =
      text.split('\n').map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
  if (paragraphs.isNotEmpty &&
      (paragraphs.first == title.trim() ||
          RegExp(r'^Art[íi]culo\s', caseSensitive: false)
              .hasMatch(paragraphs.first))) {
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

const _filler = {
  'mediante',
  'tambien',
  'podran',
  'debera',
  'deberan',
  'podria',
  'cuando',
  'cualquier',
  'cualesquiera',
  'aquellos',
  'aquellas',
  'mismos',
  'mismas',
  'respectivamente',
  'siguiente',
  'siguientes',
  'establece',
  'establecen',
  'realizar',
  'presente',
  'correspondiente',
  'correspondientes',
  'asimismo',
  'siempre'
};
final _legalConcept = RegExp(
    r'derech|obliga|plazo|tribunal|jue[zc]|pena|multa|recurso|competen|constituc|garanti|prohib|libert|sancion|consentim|autoriz|procedim|contrat|responsab');
final _quantity = RegExp(
    r'\b(?:\d+|dos|tres|cuatro|cinco|seis|siete|ocho|nueve|diez|quince|veinte|treinta|sesenta)[ \t\u00a0]+(?:días?|mes(?:es)?|años?|horas?|semanas?|euros?)\b',
    unicode: true,
    caseSensitive: false);

List<_Target> _targets(String text, {int limit = 100}) {
  final found = <_Target>[];
  for (final m in _quantity.allMatches(text).take(limit)) {
    found.add(_Target(m.start, m.end, m.group(0)!, 3));
  }
  final words = literalWord.allMatches(text).take(limit).toList();
  for (var i = 0; i < words.length; i++) {
    final word = words[i];
    if (_filler.contains(normalize(word.group(0)!))) continue;
    if (found.any((t) => word.start >= t.start && word.start < t.end)) continue;
    final single = word.group(0)!;
    found.add(_Target(word.start, word.end, single,
        _legalConcept.hasMatch(normalize(single)) ? 2 : 1));
    var end = word.end;
    if (i + 1 < words.length &&
        RegExp(r'^[ \t\u00a0]+$')
            .hasMatch(text.substring(word.end, words[i + 1].start)) &&
        words[i + 1].end - word.start <= 48 &&
        !_filler.contains(normalize(words[i + 1].group(0)!))) {
      end = words[i + 1].end;
      i++;
    }
    final answer = text.substring(word.start, end);
    if (end > word.end) {
      found.add(_Target(word.start, end, answer,
          _legalConcept.hasMatch(normalize(answer)) ? 3 : 2));
    }
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
  final articles =
      units.where((u) => articleHeading.hasMatch(u['title'])).toList();
  final eligible = articles.isNotEmpty
      ? articles
      : units
          .where((u) =>
              !['preambulo', 'fi'].contains(u['id']) &&
              (u['versions'] as List).isNotEmpty &&
              (u['versions'].last['text'] as String? ?? '').trim().length > 60)
          .toList();
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
      for (final t in _targets(u['versions'].last['text'] ?? '', limit: 64)) {
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
    final chunks = format == 'qa'
        ? literalChunks(unit['title'], version['text'] ?? '')
        : exercisePassages(unit['title'], version['text'] ?? '',
            paragraphsOnly: format != 'reference');
    final localPool = format == 'test'
        ? _targets(version['text'] ?? '', limit: 64)
            .map((t) => t.answer)
            .toList()
        : <String>[];
    for (var i = 0; i < chunks.length; i++) {
      final chunk = chunks[i];
      final seed =
          "lexmemoria:${norm['id']}:${norm['latestVersion']}:${unit['id']}:$i";
      var front =
          "¿Qué establece $displayUnit de $title?${chunks.length > 1 ? ' Tramo ${i + 1} de ${chunks.length}.' : ''}";
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
            if (value.length > 64) continue;
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
          '$seed${format == 'qa' ? '' : ':$format-v2'}${custom.isEmpty ? '' : ':group:$custom'}';
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
  if (format != 'qa') {
    final norm = Json.from(input['norm']);
    final group = (input['deck'] as String? ?? '').trim();
    for (final unit in input['units'] as List) {
      final versions = unit['versions'] as List;
      if (versions.isEmpty) continue;
      final chunks = literalChunks(unit['title'], versions.last['text'] ?? '');
      for (var i = 0; i < chunks.length; i++) {
        final seed =
            "lexmemoria:${norm['id']}:${norm['latestVersion']}:${unit['id']}:$i:$format-v1${group.isEmpty ? '' : ':group:$group'}";
        legacy
            .add(const Uuid().v5('6ba7b811-9dad-11d1-80b4-00c04fd430c8', seed));
      }
    }
  }
  return {'cards': prepared, 'legacyIds': legacy};
}
