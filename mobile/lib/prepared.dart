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

/// All answers come from the cited source. Tests ask for an omitted literal
/// word; distractors are other words, never invented legal propositions.
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
  for (final unit in eligible) {
    final versions = unit['versions'] as List;
    if (versions.isEmpty) continue;
    final version = Json.from(versions.last);
    final displayUnit =
        '${unit['title']}${(titleCounts[sourceComparable(unit['title'])] ?? 0) > 1 ? ' [${unit['id']}]' : ''}';
    final chunks = literalChunks(unit['title'], version['text'] ?? '');
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
        final words = literalWord.allMatches(chunk).toList();
        if (words.isEmpty) continue;
        final target = words.firstWhere((m) => m.start >= chunk.length ~/ 3,
            orElse: () => words.first);
        final answer = target.group(0)!;
        back = answer;
        if (format == 'cloze') {
          front =
              '$displayUnit · $title\n\n${chunk.replaceRange(target.start, target.end, '{{c1::$answer}}')}';
        } else {
          final alternatives = <String>[];
          for (final word in words) {
            final value = word.group(0)!;
            if (normalize(value) != normalize(answer) &&
                !alternatives.any((v) => normalize(v) == normalize(value))) {
              alternatives.add(value);
            }
            if (alternatives.length == 3) break;
          }
          if (alternatives.length < 3) continue;
          options.addAll([answer, ...alternatives]);
          final shift = sha256.convert(utf8.encode(seed)).bytes.first % 4;
          final rotated = [...options.skip(shift), ...options.take(shift)];
          options
            ..clear()
            ..addAll(rotated);
          correct = options.indexOf(answer);
          front =
              '¿Qué expresión completa este fragmento literal de $displayUnit?\n\n${chunk.replaceRange(target.start, target.end, '_____')}';
        }
      }
      final idSeed =
          '$seed${format == 'qa' ? '' : ':$format-v1'}${custom.isEmpty ? '' : ':group:$custom'}';
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
