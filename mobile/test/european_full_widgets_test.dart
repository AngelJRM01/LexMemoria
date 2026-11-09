import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/european_library.dart';
import 'package:lexmemoria/european_repository.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/store.dart';

class PageRepository extends EuropeanRepository {
  final List<int> offsets = [];
  PageRepository(super.store);
  @override
  Future<List<Json>> unitParagraphs(Json document, Json unit,
      {int offset = 0, int limit = 30}) async {
    offsets.add(offset);
    return List.generate(
        limit,
        (i) => {
              'id': '${offset + i}',
              'text': 'Fragmento de lectura ${offset + i + 1}.'
            });
  }
}

class NormRepository extends PageRepository {
  NormRepository(super.store);
  @override
  Future<dynamic> object(Json ref) async {
    if (ref['path'] == 'norm') {
      return {
        'schemaVersion': 1,
        'id': 'EU-32000R0001',
        'title': 'Reglamento europeo de prueba',
        'versions': [
          {
            'celex': '32000R0001',
            'kind': 'original',
            'sourceUrl': 'https://eur-lex.europa.eu/',
            'resources': [],
            'readingDocuments': [
              {'path': 'document', 'sha256': 'b' * 64}
            ]
          }
        ]
      };
    }
    return {
      'celex': '32000R0001',
      'sourceHash': 'a' * 64,
      'sourceParser': 'eu-html-leaf-paragraphs-2',
      'warnings': [],
      'units': [
        {
          'id': 'a',
          'title': 'Artículo 1',
          'kind': 'article_candidate',
          'firstParagraph': 0,
          'paragraphCount': 40
        }
      ]
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('European norm remains usable on a phone with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore(await SharedPreferences.getInstance(), {});
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!),
        home: FullEuropeanNormPage(
            store: store,
            summary: {
              'id': 'EU-32000R0001',
              'manifest': {'path': 'norm'}
            },
            repository: NormRepository(store))));
    await tester.pumpAndSettle();
    expect(find.text('Artículo 1'), findsOneWidget);
    await tester.tap(find.text('Artículo 1'));
    await tester.pumpAndSettle();
    expect(find.text('Fragmento de lectura 1.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets(
      'million-paragraph annex opens one page and saves a resumable position',
      (tester) async {
    final store = AppStore(await SharedPreferences.getInstance(), {});
    final repository = PageRepository(store);
    final summary = {
      'id': 'EU-32000R0001',
      'title': 'Norma',
      'manifest': {'path': 'public'}
    };
    await tester.pumpWidget(MaterialApp(
        home: EuropeanUnitPage(
            store: store,
            repository: repository,
            norm: {'id': summary['id']},
            summary: summary,
            edition: {
              'celex': '32000R0001',
              'kind': 'original',
              'sourceUrl': 'https://eur-lex.europa.eu/'
            },
            document: {'sourceHash': 'a' * 64, '_referenceHash': 'b' * 64},
            unit: {
              'id': 'annex',
              'title': 'ANEXO',
              'paragraphCount': 2000000,
              'firstParagraph': 0
            })));
    await tester.pumpAndSettle();
    expect(repository.offsets, [0]);
    expect(find.text('Fragmento de lectura 1.'), findsOneWidget);
    expect(find.text('Fragmento de lectura 21.'), findsNothing);
    await tester.tap(find.byTooltip('Página siguiente'));
    await tester.pumpAndSettle();
    expect(repository.offsets, [0, 20]);
    expect(find.text('Fragmento de lectura 21.'), findsOneWidget);
    final positions = store.data['readerPositions'] as Map;
    expect((positions.values.single as Map)['fragment'], 20);
    expect(store.list('norms').single['europeanManifest'], isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets(
      'original resource files are paginated instead of shown all at once',
      (tester) async {
    final resources = List.generate(
        1000,
        (i) => <String, dynamic>{
              'url': 'https://publications.europa.eu/$i',
              'mime': 'image/jpeg'
            });
    await tester.pumpWidget(
        MaterialApp(home: EuropeanResourcesPage(resources: resources)));
    await tester.pumpAndSettle();
    expect(find.text('Original 1'), findsOneWidget);
    expect(find.text('Original 21'), findsNothing);
    await tester.tap(find.byTooltip('Página siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Original 21'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
