import 'dart:convert';
import 'dart:io';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/prepared.dart';
import 'package:lexmemoria/legal_units.dart';

void main(List<String> args) {
  final pack = Json.from(
      jsonDecode(utf8.decode(gzip.decode(File(args[0]).readAsBytesSync()))));
  final units = (pack['items'] as List).map((u) => Json.from(u)).toList();
  final result = <String, dynamic>{
    'norm': pack['norm'],
    'counts': <String, int>{},
    'qaHeadingCandidates': [],
    'longSentencesOmitted': [],
    'samples': <String, dynamic>{}
  };
  for (final format in ['qa', 'cloze', 'test', 'reference']) {
    final cards = buildLiteralCards(
        {'norm': pack['norm'], 'units': units, 'format': format});
    result['counts'][format] = cards.length;
    result['samples'][format] = cards.take(8).toList();
    if (format == 'qa') {
      result['qaHeadingCandidates'] = cards
          .where((c) =>
              !RegExp(r'[.;!?]$').hasMatch(c['back'].toString()) &&
              !RegExp(r'^\d+[.)]|^[a-z][)]').hasMatch(c['back'].toString()))
          .take(40)
          .toList();
    }
  }
  for (final unit in units.where(studyArticle)) {
    final text = legalBodyText(unit['versions'].last);
    for (final p in text.split('\n')) {
      if (p.runes.length > 320 && !RegExp(r'[.;!?]\s').hasMatch(p)) {
        (result['longSentencesOmitted'] as List)
            .add({'unitId': unit['id'], 'title': unit['title'], 'text': p});
      }
    }
  }
  File(args[1]).writeAsStringSync('${jsonEncode(result)}\n');
  stdout.writeln(jsonEncode({
    'norm': pack['norm']['id'],
    'counts': result['counts'],
    'headingCandidates': (result['qaHeadingCandidates'] as List).length,
    'longSentencesOmitted': (result['longSentencesOmitted'] as List).length
  }));
}
