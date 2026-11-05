import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/library.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/reading.dart';
import 'package:lexmemoria/store.dart';

Json norm() =>
    {'id': 'test-law', 'title': 'Norma de prueba', 'latestVersion': 'v1'};
Json unit(int n) => {
      'id': 'a$n',
      'title': 'Artículo $n',
      'versions': [
        {
          'hash': 'old-$n',
          'text': 'Texto histórico derogado.',
          'effectiveFrom': '20200101'
        },
        {
          'hash': 'current-$n',
          'text':
              'Artículo $n\n1. Primera parte.\n2. Garantía constitucional $n.',
          'effectiveFrom': '20260101'
        },
      ],
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter_tts'), (_) async => 1);
  });

  test(
      'reading positions survive portable backup and reject changed source identities',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store = AppStore(prefs, {});
    final u = unit(1);
    await store.rememberReading(norm(), u, Json.from(u['versions'].last), 1);
    final backup = jsonDecode(store.export());
    final restored = AppStore(prefs, Json.from(backup['data']));
    final saved = restored.readingPosition('test-law', 'a1');
    expect(savedReadingVersion(norm(), u, saved), 1);
    expect(saved['fragment'], 1);
    expect(savedReadingVersion({...norm(), 'latestVersion': 'v2'}, u, saved),
        isNull);
    expect(savedReadingVersion(norm(), unit(2), saved), isNull);
    expect(
        savedReadingVersion(
            norm(), u, {...saved, 'unitVersionHash': 'changed'}),
        isNull);
    expect(
        savedReadingVersion(norm(), u, {...saved, 'normId': 'other'}), isNull);
    expect(savedReadingVersion(norm(), u, {...saved, 'unitVersionHash': ''}),
        isNull);
    expect(restored.data['lastReadUnits']['test-law'], 'a1');
    store.dispose();
    restored.dispose();
  });

  testWidgets(
      'reader resumes exact fragment and clears search without losing it',
      (tester) async {
    final store = AppStore(await SharedPreferences.getInstance(), {});
    await tester.pumpWidget(MaterialApp(
        home: ReaderPage(store: store, norm: norm(), unit: unit(1))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Apartado siguiente'));
    await tester.pumpAndSettle();
    expect(store.readingPosition('test-law', 'a1')['fragment'], 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(MaterialApp(
        home: ReaderPage(store: store, norm: norm(), unit: unit(1))));
    await tester.pumpAndSettle();
    expect(find.text('Fragmento 2 de 2'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Primera');
    await tester.pumpAndSettle();
    expect(find.text('Fragmento 1 de 1'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('Fragmento 2 de 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets(
      'norm text search finds body accents, excludes history and opens matching fragment',
      (tester) async {
    final store = AppStore(await SharedPreferences.getInstance(), {
      'norms': [
        {
          ...norm(),
          'units': [unit(1), unit(2)]
        }
      ]
    });
    await tester
        .pumpWidget(MaterialApp(home: NormPage(store: store, id: 'test-law')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'garantia constitucional 2');
    await tester.pumpAndSettle();
    expect(find.text('Sin coincidencias'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Texto'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    });
    await tester.pumpAndSettle();
    expect(find.text('Artículo 2'), findsOneWidget);
    expect(find.text('Artículo 1'), findsNothing);
    await tester.tap(find.text('Artículo 2'));
    await tester.pumpAndSettle();
    expect(find.text('Fragmento 1 de 1'), findsOneWidget);
    expect(find.byType(LegalParagraph), findsOneWidget);
    expect(tester.widget<LegalParagraph>(find.byType(LegalParagraph)).text,
        contains('Garantía constitucional 2'));
    expect(store.readingPosition('test-law', 'a2')['fragment'], 1);
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'derogado');
    await tester.pumpAndSettle();
    expect(find.text('Sin coincidencias'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets(
      'large norm index builds visible rows on demand and offers valid continue',
      (tester) async {
    final store = AppStore(await SharedPreferences.getInstance(), {
      'norms': [
        {...norm(), 'units': List.generate(10000, (i) => unit(i + 1))}
      ]
    });
    final u = unit(1);
    await store.rememberReading(norm(), u, Json.from(u['versions'].last), 1);
    await tester
        .pumpWidget(MaterialApp(home: NormPage(store: store, id: 'test-law')));
    await tester.pumpAndSettle();
    expect(find.byType(ListTile).evaluate().length, lessThan(40));
    expect(find.text('Artículo 10000'), findsNothing);
    await tester.tap(find.text('Continuar: Artículo 1'));
    await tester.pumpAndSettle();
    expect(find.text('Fragmento 2 de 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('reader resets fragment scroll and builds full article on demand',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore(await SharedPreferences.getInstance(), {});
    final u = unit(1);
    u['versions'].last['text'] =
        'Artículo 1\n1. ${List.filled(200, 'Párrafo extenso para estudiar.').join(' ')}\n'
        '${List.generate(10000, (i) => '${i + 2}. Apartado breve.').join('\n')}';
    await tester.pumpWidget(
        MaterialApp(home: ReaderPage(store: store, norm: norm(), unit: u)));
    await tester.pumpAndSettle();
    final list = find.byType(ListView).last;
    await tester.drag(list, const Offset(0, -500));
    await tester.pumpAndSettle();
    final controller = tester.widget<ListView>(list).controller!;
    expect(controller.offset, greaterThan(0));
    await tester.tap(find.byTooltip('Apartado siguiente'));
    await tester.pumpAndSettle();
    expect(controller.offset, 0);
    expect(find.text('Fragmento 2 de 10001'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Artículo completo'));
    await tester.pumpAndSettle();
    expect(find.byType(LegalParagraph).evaluate().length, lessThan(40));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
