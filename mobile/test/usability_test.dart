import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/library.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/persistence.dart';
import 'package:lexmemoria/profile.dart';
import 'package:lexmemoria/shell.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/study.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('flutter_tts'), (_) async => 1);
  });
  test('starter installs once; full deck preserves edited cards and reviews',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store =
        await AppStore.load(persistence: PreferencesPersistence(prefs));
    expect(store.cards.length, 20);
    expect(store.preparedDecks.length,
        store.corpusNorms.where((n) => (n['count'] as num? ?? 0) > 0).length);
    expect(store.preparedDecks.every((d) => (d['count'] as num? ?? 0) > 0),
        isTrue);
    final original = store.cards.first;
    expect(original.normId, 'BOE-A-1978-31229');
    expect(original.unitVersionHash, isNotEmpty);
    await store.review(original, 3);
    await store.editCard(
        StudyCard.fromJson(
            {...original.toJson(), 'front': 'Mi pregunta', 'revision': 2}),
        expectedRevision: 1);
    final deck =
        store.preparedDecks.firstWhere((d) => d['id'] == original.normId);
    final added = await store.installPreparedDeck(deck);
    expect(added, greaterThan(100));
    expect(await store.installPreparedDeck(deck), 0);
    final reloaded =
        await AppStore.load(persistence: PreferencesPersistence(prefs));
    expect(reloaded.cards.length, store.cards.length);
    expect(reloaded.cards.firstWhere((c) => c.id == original.id).front,
        'Mi pregunta');
    expect(reloaded.state(original.id)['repetitions'], 1);
    expect(reloaded.list('reviews').length, 1);
    final before = reloaded.cards.length;
    Object? integrityError;
    try {
      await reloaded.installPreparedDeck({...deck, 'hash': 'bad'});
    } catch (error) {
      integrityError = error;
    }
    expect(integrityError, isA<StateError>());
    expect(reloaded.cards.length, before);
    store.dispose();
    reloaded.dispose();
  });
  test('dates omit seconds and milliseconds; invalid dates stay unknown', () {
    expect(displayDate('20261105'), '05/11/2026');
    expect(displayDate('2026-11-05T10:24:31.987', time: true),
        '05/11/2026 · 10:24');
    expect(displayDate('2026-11-05'), '05/11/2026');
    expect(displayDate('not a date'), 'Sin fecha');
    expect(displayDate('2026-02-31'), 'Sin fecha');
  });
  test('article paragraphs keep literal numbering and words', () {
    const source =
        'Artículo 1\n1. Primer apartado.\n\n2. Segundo apartado.\na) Una excepción.';
    expect(articleParagraphs(source, 'Artículo 1'),
        ['1. Primer apartado.', '2. Segundo apartado.', 'a) Una excepción.']);
  });
  test('large backups are shared as a portable JSON file', () async {
    final store = AppStore(await SharedPreferences.getInstance(), {
      'notes': {'article': List.filled(350000, 'nota').join(' ')},
      'auth': {'access': 'excluded-from-backup'},
    });
    final params = backupParameters(store.export());
    expect(params.text, isNull);
    final file = params.files!.single;
    expect(await file.length(), greaterThan(1000000));
    expect(params.fileNameOverrides!.single, endsWith('.json'));
    final backup = jsonDecode(await file.readAsString());
    expect(backup['data']['notes'], store.data['notes']);
    expect(backup['data']['auth'], isNull);
    store.dispose();
  });
  testWidgets('library filter stays visible after scrolling results',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore(await SharedPreferences.getInstance(), {});
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LibraryPage(store: store))));
    final position = tester.getTopLeft(find.byType(TextField));
    await tester.drag(find.byType(ListView).last, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.byType(TextField)), position);
    await tester.enterText(find.byType(TextField), 'Constitucion');
    await tester.pumpAndSettle();
    expect(find.text('Constitución Española'), findsOneWidget);
    expect(find.text('Código Civil'), findsNothing);
    await tester.tap(find.byTooltip('Filtros de biblioteca'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Estatal').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Aplicar filtros'));
    await tester.pumpAndSettle();
    expect(find.text('Constitución Española'), findsOneWidget);
    expect(tester.takeException(), isNull);
    store.dispose();
  });
  testWidgets(
      'reader separates fragments, searches and keeps navigation above system inset',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore(await SharedPreferences.getInstance(), {});
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(padding: const EdgeInsets.only(bottom: 34)),
            child: child!),
        home: ReaderPage(store: store, norm: {
          'id': 'BOE-A-1978-31229',
          'sourceUrl': 'https://www.boe.es'
        }, unit: {
          'id': 'a1',
          'title': 'Artículo 1',
          'versions': [
            {
              'text': 'Artículo 1\n1. Primer apartado.\n2. Segundo apartado.',
              'effectiveFrom': '19781229'
            }
          ]
        })));
    await tester.pumpAndSettle();
    expect(
        find.text('1. Primer apartado.', findRichText: true), findsOneWidget);
    expect(find.text('2. Segundo apartado.', findRichText: true), findsNothing);
    expect(tester.getBottomRight(find.byTooltip('Apartado siguiente')).dy,
        lessThan(844 - 34));
    await tester.tap(find.byTooltip('Apartado siguiente'));
    await tester.pumpAndSettle();
    expect(
        find.text('2. Segundo apartado.', findRichText: true), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'primer');
    await tester.pumpAndSettle();
    expect(
        find.text('1. Primer apartado.', findRichText: true), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
  for (final size in [const Size(390, 844), const Size(700, 360)]) {
    testWidgets('main pages fit large text at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = AppStore(await SharedPreferences.getInstance(), {});
      for (final page in <Widget>[
        HomePage(store: store, navigate: (_) {}),
        LibraryPage(store: store),
        StudyPage(store: store),
        ProfilePage(store: store),
        AccountPage(store: store),
        ReaderPage(store: store, norm: {
          'id': 'law',
          'sourceUrl': 'https://www.boe.es'
        }, unit: {
          'id': 'a1',
          'title': 'Artículo 1',
          'versions': [
            {
              'text':
                  'Artículo 1\n1. Un texto de estudio con sus palabras originales.',
              'effectiveFrom': '20260101'
            }
          ]
        })
      ]) {
        await tester.pumpWidget(MaterialApp(
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(2)),
                child: child!),
            home: page is Scaffold || page is ReaderPage || page is AccountPage
                ? page
                : Scaffold(body: page)));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: page.runtimeType.toString());
      }
      await tester.pumpWidget(const SizedBox());
      store.dispose();
    });
  }
}
