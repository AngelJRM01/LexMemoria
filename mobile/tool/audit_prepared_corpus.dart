import 'dart:convert';
import 'dart:io';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/prepared.dart';
import 'package:lexmemoria/legal_units.dart';

void main(List<String> args) {
  final root = args.isEmpty ? '/workspace/lexmemoria-distribution' : args.first;
  final limit = args.length > 1 ? int.parse(args[1]) : 0;
  final catalogue = jsonDecode(utf8.decode(
      gzip.decode(File('$root/catalogue.json.gz').readAsBytesSync()))) as Map;
  final totals = <String, int>{'qa': 0, 'cloze': 0, 'test': 0, 'reference': 0};
  var checked = 0;
  for (final item in catalogue['items'] as List) {
    if (limit > 0 && checked >= limit) break;
    final entry = Json.from(item);
    final pack = Json.from(jsonDecode(utf8.decode(gzip
        .decode(File('$root/boe/${entry['id']}.json.gz').readAsBytesSync()))));
    final units = (pack['items'] as List).map((u) => Json.from(u)).toList();
    final byId = {for (final unit in units) unit['id']: unit};
    final source = {
      for (final unit in units)
        unit['id']: (unit['versions'].last['text'] as String)
            .replaceAll(RegExp(r'\s+'), ' ')
    };
    final ids = <String>{};
    final referenceSources = <String, List<String>>{};
    for (final unit in units) {
      referenceSources
          .putIfAbsent(unit['title'] as String, () => [])
          .add(sourceComparable(unit['versions'].last['text']));
    }
    for (final format in totals.keys) {
      final cards = buildLiteralCards(
          {'norm': pack['norm'], 'units': units, 'format': format});
      if (format == 'qa' && cards.length != entry['count']) {
        throw StateError(
            'Fragment count mismatch: ${entry['id']}, ${cards.length} != ${entry['count']}');
      }
      for (final card in cards) {
        final unit = byId[card['unitId']]!;
        if (legalUnitKind(unit) != 'article') {
          throw StateError('Non-article used as an exercise');
        }
        if (format == 'qa' && (card['back'] as String).runes.length > 1200) {
          throw StateError('Oversized recall rule');
        }
        if (format == 'test' &&
            (card['options'] as List).any(
                (v) => targetCategory(v) != targetCategory(card['back']))) {
          throw StateError('Unrelated distractor category');
        }
        if (!ids.add(card['id']) ||
            card['normId'] != entry['id'] ||
            card['unitVersionHash'] != unit['versions'].last['hash']) {
          throw StateError('Citation or identity mismatch');
        }
        if (format == 'reference') {
          if (card['back'] != unit['title']) {
            throw StateError('Wrong article reference');
          }
          final prefix =
              'En ${friendlyNormLabel(Json.from(pack['norm']))}, ¿cuál de estos artículos o apartados contiene este fragmento?\n\n';
          if (!(card['front'] as String).startsWith(prefix)) {
            throw StateError('Missing reference context');
          }
          final quote = sourceComparable(
              (card['front'] as String).substring(prefix.length));
          for (final option in card['options'] as List) {
            if (option == card['back']) continue;
            if ((referenceSources[option] ?? [])
                .any((text) => text.contains(quote))) {
              throw StateError('Ambiguous reference answer');
            }
          }
        } else if (format == 'cloze') {
          final holes = RegExp(r'\{\{c(\d+)::(.+?)\}\}')
              .allMatches(card['front'])
              .toList();
          if (holes.length < 2) {
            throw StateError('Insufficient learning targets');
          }
          final expected = <String>[];
          for (final hole in holes) {
            final answer = hole.group(2)!;
            if (!source[card['unitId']]!
                .contains(answer.replaceAll(RegExp(r'\s+'), ' '))) {
              throw StateError('Cloze answer not in source');
            }
            expected.add('${hole.group(1)}. $answer');
          }
          if (card['back'] != expected.join('\n')) {
            throw StateError('Cloze answer key mismatch');
          }
        } else {
          final answer =
              (card['back'] as String).replaceAll(RegExp(r'\s+'), ' ');
          // Supplemental full sentences keep new slots after legacy short cards.
          const start = 0;
          final found = source[card['unitId']]!.indexOf(answer, start);
          if (found < 0) {
            throw StateError('Answer not found in official source');
          }
        }
        if ((card['options'] as List).isNotEmpty &&
            card['options'][card['correct']] != card['back']) {
          throw StateError('Incorrect marked answer');
        }
      }
      totals[format] = totals[format]! + cards.length;
    }
    checked++;
    if (checked % 250 == 0) {
      stdout
          .writeln(jsonEncode({'normsChecked': checked, 'exercises': totals}));
    }
  }
  final result = {
    'normsChecked': checked,
    'allNormsChecked': checked == catalogue['norms'],
    'exercises': totals,
    'validationPassed': true,
    'legalReview': 'not_performed'
  };
  File('$root/exercises-verification${limit > 0 ? '-sample' : ''}.json')
      .writeAsStringSync(
          '${const JsonEncoder.withIndent('  ').convert(result)}\n');
  stdout.writeln(jsonEncode(result));
}
