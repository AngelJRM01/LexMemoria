import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/european_repository.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/prepared.dart';
import 'package:lexmemoria/store.dart';

const corpusPath = String.fromEnvironment('LEXMEMORIA_EU_LOCAL_ROOT');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'complete distribution opens through the real mobile decoder and produces cited RGPD cards',
      () async {
    SharedPreferences.setMockInitialValues({});
    final root = Directory(corpusPath).absolute;
    final client = MockClient((request) async {
      final prefix = Uri.parse(europeanLibraryBase).path;
      if (!request.url.path.startsWith(prefix)) {
        throw StateError('Unexpected source');
      }
      final relative = request.url.path.substring(prefix.length);
      if (relative.contains('..')) throw StateError('Invalid fixture path');
      return http.Response.bytes(
          await File('${root.path}/$relative').readAsBytes(), 200);
    });
    final store =
        AppStore(await SharedPreferences.getInstance(), {}, client: client);
    final repository = EuropeanRepository(store);
    final header = jsonDecode(
        await File('${root.path}/catalogue-manifest.json').readAsString());
    final watch = Stopwatch()..start();
    final catalogue = await repository.catalogue();
    final decodingMs = watch.elapsedMilliseconds;
    watch.reset();
    final reopened = await EuropeanRepository(store).catalogue();
    final warmMicroseconds = watch.elapsedMicroseconds;
    expect(identical(catalogue, reopened), isTrue);
    expect(catalogue.length, header['norms']);
    expect(catalogue.map((n) => n['id']).toSet().length, catalogue.length);
    final summary = catalogue.singleWhere((n) => n['celex'] == '32016R0679');
    final norm =
        Json.from(await repository.object(Json.from(summary['manifest'])));
    final versions =
        (norm['versions'] as List).map((v) => Json.from(v)).toList();
    final original = versions.singleWhere((v) => v['celex'] == '32016R0679');
    final documents = <Json>[];
    for (final ref in original['readingDocuments'] as List) {
      documents.add(Json.from(await repository.object(Json.from(ref))));
    }
    final articles = <Json>[];
    for (var d = 0; d < documents.length; d++) {
      final document = documents[d];
      for (final value in document['units'] as List) {
        final unit = Json.from(value);
        if (unit['kind'] != 'article_candidate') continue;
        final paragraphs = await repository.unitParagraphs(document, unit,
            limit: (unit['paragraphCount'] as num).toInt());
        if (!europeanArticleParagraphsAllowed(paragraphs)) continue;
        articles.add({
          'id': '$d:${unit['id']}',
          'title': unit['title'],
          'type': 'precepto',
          'automaticStudyEligible': true,
          'versions': [
            {
              'text': paragraphs.map((p) => p['text']).join('\n'),
              'hash': sha256
                  .convert(
                      utf8.encode(paragraphs.map((p) => p['text']).join('\n')))
                  .toString()
            }
          ]
        });
      }
    }
    expect(articles, isNotEmpty);
    final cardCounts = <String, int>{};
    for (final format in ['qa', 'cloze', 'test', 'reference']) {
      final cards = buildLiteralCards({
        'norm': {...norm, 'latestVersion': original['celex']},
        'units': articles,
        'format': format
      });
      expect(cards, isNotEmpty, reason: format);
      cardCounts[format] = cards.length;
      for (final card in cards) {
        expect(card['normId'], norm['id']);
        expect(card['versionId'], original['celex']);
        final cited = articles.singleWhere((u) => u['id'] == card['unitId']);
        expect(card['unitVersionHash'],
            (cited['versions'] as List).single['hash']);
      }
    }
    final sourceOnly = catalogue.firstWhere((n) => n['readableEditions'] == 0);
    final fiche =
        Json.from(await repository.object(Json.from(sourceOnly['manifest'])));
    expect(
        (fiche['versions'] as List)
            .every((v) => (v['readingDocuments'] as List).isEmpty),
        isTrue);
    debugPrint(jsonEncode({
      'norms': catalogue.length,
      'records': header['records'],
      'catalogueDecodeMs': decodingMs,
      'catalogueReopenMicroseconds': warmMicroseconds,
      'rgpdStudyArticles': articles.length,
      'rgpdCards': cardCounts,
      'sourceOnlyFiche': fiche['celex']
    }));
    store.dispose();
  }, skip: corpusPath.isEmpty, timeout: const Timeout(Duration(minutes: 5)));
}
