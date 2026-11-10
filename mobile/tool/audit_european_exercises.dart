import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/prepared.dart';
import 'package:lexmemoria/european_policy.dart';

void main(List<String> args) {
  final root = args[0], shard = int.parse(args[1]), shards = int.parse(args[2]);
  final counts = <String, int>{
    'norms': 0,
    'editionsConsidered': 0,
    'editionsEligible': 0,
    'articles': 0,
    'qa': 0,
    'cloze': 0,
    'test': 0,
    'reference': 0
  };
  final blocked = <String, int>{};
  void block(String reason) => blocked[reason] = (blocked[reason] ?? 0) + 1;
  final cache = <String, dynamic>{};
  dynamic load(Json ref) {
    final key = ref['sha256'] as String;
    if (cache.containsKey(key)) return cache[key];
    final bytes = File('$root/${ref['path']}').readAsBytesSync();
    if (bytes.length != ref['bytes'] || sha256.convert(bytes).toString() != key) {
      throw StateError('Object integrity');
    }
    final raw = gzip.decode(bytes);
    if (raw.length != ref['expandedBytes']) throw StateError('Expanded length');
    final dynamic value = ref['encoding'] == 'jsonl'
        ? const LineSplitter()
            .convert(utf8.decode(raw))
            .map((l) => Json.from(jsonDecode(l)))
            .toList()
        : Json.from(jsonDecode(utf8.decode(raw)));
    cache[key] = value;
    if (cache.length > 6) cache.remove(cache.keys.first);
    return value;
  }

  List<Json> paragraphs(Json document, Json unit) {
    final first = unit['firstParagraph'] as int,
        end = first + (unit['paragraphCount'] as int);
    final result = <Json>[];
    for (final value in document['pages'] as List) {
      final page = Json.from(value),
          start = page['firstParagraph'] as int,
          stop = (page['firstParagraph'] as int) + (page['paragraphs'] as int);
      if (stop <= first || start >= end) continue;
      final records = load(page) as List;
      for (var i = 0; i < records.length; i++) {
        if (start + i >= first && start + i < end) {
          if (records[i]['unitId'] != unit['id']) {
            throw StateError('Wrong paragraph unit');
          }
          result.add(Json.from(records[i]['paragraph']));
        }
      }
    }
    if (result.length != end - first) throw StateError('Paragraph coverage');
    return result;
  }

  final header = Json.from(
      jsonDecode(File('$root/catalogue-manifest.json').readAsStringSync()));
  final items = (load(Json.from(header['index']))['items'] as List);
  for (var index = shard; index < items.length; index += shards) {
    final summary = Json.from(items[index]);
    counts['norms'] = counts['norms']! + 1;
    if ((summary['literalStudyEditions'] as num? ?? 0) <= 0) {
      block('not_offered_as_study_material');
      continue;
    }
    final norm = Json.from(load(Json.from(summary['manifest'])));
    for (final value in norm['versions'] as List) {
      final edition = Json.from(value);
      counts['editionsConsidered'] = counts['editionsConsidered']! + 1;
      final docs = (edition['readingDocuments'] as List)
          .map((r) => Json.from(load(Json.from(r))))
          .toList();
      if (!europeanLiteralStudyAllowed(norm, edition, docs)) {
        block('edition_or_document_policy');
        continue;
      }
      final units = <Json>[], titles = <String>{};
      var ambiguous = false;
      for (var d = 0; d < docs.length; d++) {
        final doc = docs[d];
        if (doc['sourceParser'] != 'eu-html-leaf-paragraphs-2' ||
            (doc['warnings'] as List).isNotEmpty) {
          continue;
        }
        for (final value in doc['units'] as List) {
          final unit = Json.from(value);
          if (unit['kind'] != 'article_candidate') continue;
          if (!titles.add(normalize(unit['title']))) {
            ambiguous = true;
            break;
          }
          if ((unit['paragraphCount'] as num) > 5000) {
            block('oversized_article');
            continue;
          }
          final ps = paragraphs(doc, unit);
          if (!europeanArticleParagraphsAllowed(ps)) {
            block('unresolved_heading_inside_article');
            continue;
          }
          final text = ps.map((p) => p['text']).join('\n');
          if (text.length > 1000000) {
            block('oversized_article');
            continue;
          }
          units.add({
            'id': '$d:${unit['id']}',
            'title': unit['title'],
            'type': 'precepto',
            'automaticStudyEligible': true,
            'versions': [
              {
                'text': text,
                'hash': sha256.convert(utf8.encode(text)).toString()
              }
            ]
          });
        }
        if (ambiguous) break;
      }
      if (ambiguous) {
        block('duplicate_article_titles_across_parts');
        continue;
      }
      counts['editionsEligible'] = counts['editionsEligible']! + 1;
      counts['articles'] = counts['articles']! + units.length;
      final byId = {for (final u in units) u['id']: u};
      for (final format in ['qa', 'cloze', 'test', 'reference']) {
        final cards = buildLiteralCards({
          'norm': {...norm, 'latestVersion': edition['celex']},
          'units': units,
          'format': format
        });
        counts[format] = counts[format]! + cards.length;
        for (final card in cards) {
          final unit = byId[card['unitId']]!;
          final text = unit['versions'].last['text'] as String;
          if (card['normId'] != norm['id'] ||
              card['versionId'] != edition['celex'] ||
              card['unitVersionHash'] != unit['versions'].last['hash']) {
            throw StateError('Citation mismatch');
          }
          final quote = format == 'qa'
              ? card['back'] as String
              : format == 'reference'
                  ? (card['front'] as String).split('\n\n').skip(1).join('\n\n')
                  : (card['explanation'] as String)
                      .split('\n\nEjercicio')
                      .first
                      .replaceFirst('Texto de referencia:\n', '');
          if (!safeStudyPassage(quote) ||
              quote.runes.length > (format == 'qa' ? 1200 : 320) ||
              !sourceComparable(text).contains(sourceComparable(quote))) {
            throw StateError(
                'Incomplete or ungrounded exercise: ${norm['id']} ${unit['id']}');
          }
          if (format == 'test' &&
              (card['options'] as List).any(
                  (o) => targetCategory(o) != targetCategory(card['back']))) {
            throw StateError('Incompatible options');
          }
          if ((card['options'] as List).isNotEmpty &&
              card['options'][card['correct']] != card['back']) {
            throw StateError('Wrong key');
          }
          if (format == 'cloze') {
            final holes = RegExp(r'\{\{c\d+::(.+?)\}\}')
                .allMatches(card['front'])
                .toList();
            if (holes.length < 2 ||
                holes.any((h) => !quote.contains(h.group(1)!))) {
              throw StateError('Invalid cloze');
            }
          }
        }
      }
    }
    if (counts['norms']! % 1000 == 0) {
      stdout.writeln(jsonEncode({'shard': shard, 'counts': counts}));
    }
  }
  final report = {
    'shard': shard,
    'shards': shards,
    'counts': counts,
    'blockedReasons': blocked,
    'validationPassed': true,
    'manualReview': false,
    'legalReview': 'not_performed',
    'manifestSha256': sha256
        .convert(File('$root/catalogue-manifest.json').readAsBytesSync())
        .toString()
  };
  File(args[3]).writeAsStringSync('${jsonEncode(report)}\n');
  stdout.writeln(jsonEncode(report));
}
