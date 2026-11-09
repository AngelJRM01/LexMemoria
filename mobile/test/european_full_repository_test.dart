import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/european_repository.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'missed ordinal articles and chapter headings cannot leak into exercises',
      () {
    final header = {'id': '1', 'text': 'Artículo 1'};
    expect(
        europeanArticleParagraphsAllowed([
          header,
          {'id': '2', 'text': 'La presente norma establece las condiciones.'}
        ]),
        isTrue);
    for (final text in [
      'Artículo décimo primero',
      'Artículo 2 bis',
      'ANEXO II',
      'CAPÍTULO II Disposiciones generales',
      'Artículo único'
    ]) {
      expect(
          europeanArticleParagraphsAllowed([
            header,
            {'id': '2', 'text': text}
          ]),
          isFalse,
          reason: text);
    }
  });

  test(
      'literal study excludes OCR corrections and structurally ambiguous texts',
      () {
    final norm = {
      'kind': 'Reglamento',
      'title': 'Reglamento relativo a los datos'
    };
    final edition = {'kind': 'original'};
    final doc = {
      'sourceParser': 'eu-html-leaf-paragraphs-2',
      'warnings': [],
      'units': [
        {'kind': 'article_candidate'}
      ]
    };
    expect(europeanLiteralStudyAllowed(norm, edition, [doc]), isTrue);
    expect(europeanLiteralStudyAllowed(norm, {'kind': 'correction'}, [doc]),
        isFalse);
    expect(
        europeanLiteralStudyAllowed(norm, edition, [
          {...doc, 'sourceParser': 'eu-pdf-ocr-spa-1'}
        ]),
        isFalse);
    expect(
        europeanLiteralStudyAllowed(norm, edition, [
          {
            ...doc,
            'warnings': ['duplicate_article_number:1']
          }
        ]),
        isFalse);
    expect(
        europeanLiteralStudyAllowed(
            {
              ...norm,
              'title': 'Reglamento por el que se modifica otro reglamento'
            },
            edition,
            [doc]),
        isFalse);
  });

  test('changing EU edition archives old text and preserves cards and notes',
      () async {
    final store = AppStore(await SharedPreferences.getInstance(), {
      'norms': [
        {
          'id': 'EU-32000R0001',
          'latestVersion': 'old',
          'units': [
            {'id': 'a'}
          ],
          'europeanOffline': true
        }
      ],
      'cards': [],
      'notes': {'mine': 'Texto personal'},
      'reviews': [
        {'answer': 'ok'}
      ]
    });
    await store
        .saveEuropeanNorm({'id': 'EU-32000R0001', 'latestVersion': 'new'});
    expect(store.list('norms').single.containsKey('units'), isFalse);
    expect(store.list('norms').single.containsKey('europeanOffline'), isFalse);
    expect(store.list('archivedPacks').single['units'], [
      {'id': 'a'}
    ]);
    expect(store.data['notes'], {'mine': 'Texto personal'});
    expect(store.list('reviews'), [
      {'answer': 'ok'}
    ]);
    await expectLater(
        store.saveEuropeanNorm({'id': 'BOE-test'}), throwsStateError);
    expect(store.list('norms').length, 1);
    store.dispose();
  });

  test(
      'verified catalogue and pages remain available offline without touching progress',
      () async {
    final responses = <String, List<int>>{};
    Json object(dynamic value, {bool lines = false}) {
      final raw =
          utf8.encode(lines ? '${jsonEncode(value)}\n' : jsonEncode(value));
      final bytes = GZipEncoder().encode(raw);
      final hash = sha256.convert(bytes).toString();
      final path = 'objects/${hash.substring(0, 2)}/$hash.gz';
      responses['$europeanLibraryBase$path'] = bytes;
      return {
        'path': path,
        'sha256': hash,
        'bytes': bytes.length,
        'expandedBytes': raw.length,
        'encoding': lines ? 'jsonl' : 'json'
      };
    }

    final page = object({
      'unitId': 'a',
      'paragraph': {'id': 'p', 'text': 'Una regla.', 'sourcePage': 3}
    }, lines: true);
    final index = object({
      'schemaVersion': 1,
      'items': [
        {
          'id': 'EU-32016R0679',
          'celex': '32016R0679',
          'title': 'Protección de datos',
          'kind': 'Reglamento',
          'year': '2016',
          'editions': 1,
          'readableEditions': 1,
          'manifest': page
        }
      ]
    });
    responses['${europeanLibraryBase}catalogue-manifest.json'] = utf8.encode(
        jsonEncode({
      'schemaVersion': 1,
      'baseUrl': europeanLibraryBase,
      'norms': 1,
      'index': index
    }));
    var offline = false;
    final client = MockClient((request) async {
      if (offline) throw http.ClientException('offline');
      return http.Response.bytes(responses[request.url.toString()]!, 200);
    });
    final store = AppStore(
        await SharedPreferences.getInstance(), {'cards': [], 'reviews': []},
        client: client);
    final repo = EuropeanRepository(store);
    final initialCatalogue = await repo.catalogue();
    expect(initialCatalogue.single['_search'], contains('rgpd'));
    expect(
        identical(
            initialCatalogue, await EuropeanRepository(store).catalogue()),
        isTrue);
    final document = {
      'pages': [
        {...page, 'firstParagraph': 0, 'paragraphs': 1}
      ]
    };
    final unit = {'id': 'a', 'firstParagraph': 0, 'paragraphCount': 1};
    expect((await repo.unitParagraphs(document, unit)).single['sourcePage'], 3);
    offline = true;
    final restored = EuropeanRepository(store);
    expect((await restored.catalogue()).length, 1);
    expect((await restored.unitParagraphs(document, unit)).single['text'],
        'Una regla.');
    expect(store.data['cards'], isEmpty);
    expect(store.data['reviews'], isEmpty);
    store.dispose();
  });

  test(
      'corrupted downloads and references outside the content tree are rejected',
      () async {
    final store = AppStore(await SharedPreferences.getInstance(), {},
        client: MockClient((_) async =>
            http.Response.bytes(Uint8List.fromList([1, 2, 3]), 200)));
    final repo = EuropeanRepository(store);
    final hash = 'a' * 64;
    final ref = {
      'path': 'objects/aa/$hash.gz',
      'sha256': hash,
      'bytes': 3,
      'expandedBytes': 8
    };
    await expectLater(repo.compressed(ref), throwsStateError);
    expect(
        () => repo.objectUri({...ref, 'path': '../private'}), throwsStateError);
    expect(store.prefs.getString(EuropeanRepository.manifestKey), isNull);
    store.dispose();
  });

  test(
      'future consolidations and corrections are not silently selected as current',
      () {
    final versions = <Json>[
      {'kind': 'correction', 'date': null},
      {'kind': 'original', 'date': null},
      {'kind': 'consolidated', 'date': '2026-01-01'},
      {'kind': 'consolidated', 'date': '2027-01-01'},
    ];
    expect(preferredEuropeanEdition(versions, DateTime(2026, 11, 9)), 2);
    expect(europeanEditionLabel(versions.first), 'Corrección de errores');
  });
}
