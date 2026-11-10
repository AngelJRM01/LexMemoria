import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/main.dart';
import 'package:lexmemoria/library.dart';
import 'package:lexmemoria/european_repository.dart';
import 'package:lexmemoria/study.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/persistence.dart';

class RecordingStorage implements LocalPersistence {
  int writes = 0;
  bool fail = false;
  String? snapshot;
  Completer<void>? hold;
  Completer<void>? entered;
  @override
  Future<String?> read() async => snapshot;
  @override
  Future<void> write(String value) async {
    writes++;
    if (fail) throw StateError('Disk full');
    snapshot = value;
    entered?.complete();
    if (hold != null) await hold!.future;
  }

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('answer and continuation commit once and roll back together on failure',
      () async {
    final storage = RecordingStorage();
    final store = AppStore(await SharedPreferences.getInstance(), {},
        persistence: storage);
    const ids = ['a', 'b'];
    final card = StudyCard(id: 'a', deck: 'D', front: 'Q', back: 'A');
    await store.addCard(card);
    storage.writes = 0;
    await store.review(card, 3, sessionIds: ids, nextIndex: 1);
    expect(storage.writes, 1);
    final saved = jsonDecode(storage.snapshot!);
    expect(saved['session']['index'], 1);
    expect(saved['reviews'].length, 1);
    expect(saved['states']['a']['repetitions'], 1);
    final before = store.export();
    storage.fail = true;
    await expectLater(
        store.review(card, 3, sessionIds: ids, nextIndex: 1), throwsStateError);
    expect(store.list('reviews').length, 1);
    expect(store.data['session']['index'], 1);
    expect(jsonDecode(store.export())['data'], jsonDecode(before)['data']);
    store.dispose();
  });

  test('caller-owned fields cannot change the confirmed snapshot while saving',
      () async {
    final storage = RecordingStorage()
      ..hold = Completer<void>()
      ..entered = Completer<void>();
    final store = AppStore(await SharedPreferences.getInstance(), {},
        persistence: storage);
    final note = <String, dynamic>{'text': 'Original'};
    final operation = store.setProfile({'customNote': note});
    await storage.entered!.future;
    note['text'] = 'Changed during write';
    storage.hold!.complete();
    await operation;
    expect(store.profile['customNote']['text'], 'Original');
    expect(jsonDecode(storage.snapshot!)['profile'], store.profile);
    store.dispose();
  });

  test('deck index respects edits and the latest review state', () async {
    final store = AppStore(await SharedPreferences.getInstance(), {});
    await store
        .addCard(StudyCard(id: 'a', deck: 'First', front: 'Q', back: 'A'));
    expect(store.due(deck: 'First', includeRest: true).length, 1);
    await store.editCard(
        StudyCard(id: 'a', deck: 'Second', front: 'Q', back: 'A', revision: 2),
        expectedRevision: 1);
    expect(store.due(deck: 'First', includeRest: true), isEmpty);
    expect(store.due(deck: 'Second', includeRest: true).length, 1);
    await store.review(store.cards.single, 3);
    expect(store.due(deck: 'Second', includeRest: true), isEmpty);
    store.dispose();
  });

  test(
      'European pagination reuses results and bookmark changes invalidate the filter',
      () {
    final source = <Json>[
      {
        'id': 'a',
        'kind': 'Reglamento',
        'year': '2026',
        'readableEditions': 1,
        '_search': 'proteccion de datos'
      },
      {
        'id': 'b',
        'kind': 'Directiva',
        'year': '2025',
        'readableEditions': 0,
        '_search': 'empleo'
      }
    ];
    final filter = EuropeanCatalogueFilter();
    expect(identical(filter.select(source), source), true);
    final rows = filter.select(source, query: 'protección');
    expect(rows.single['id'], 'a');
    expect(identical(filter.select(source, query: 'protección'), rows), true);
    expect(
        filter.select(source, saved: true, bookmarks: ['b']).single['id'], 'b');
    expect(
        filter.select(source, saved: true, bookmarks: ['a']).single['id'], 'a');
    expect(filter.select(source, textOnly: true).single['id'], 'a');
  });

  testWidgets('rapid answer taps store exactly one review and one continuation',
      (tester) async {
    final storage = RecordingStorage();
    final store = AppStore(await SharedPreferences.getInstance(), {},
        persistence: storage);
    await store.addCard(StudyCard(id: 'a', deck: 'D', front: 'Q', back: 'A'));
    await store.addCard(StudyCard(id: 'b', deck: 'D', front: 'Q2', back: 'A2'));
    storage.writes = 0;
    await tester.pumpWidget(
        MaterialApp(home: ReviewPage(store: store, queue: store.cards)));
    await tester.tap(find.text('Mostrar respuesta'));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(ListView).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.ancestor(
        of: find.text('Bien'), matching: find.byType(OutlinedButton)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bien'));
    await tester.tap(find.text('Bien'));
    await tester.pumpAndSettle();
    expect(store.list('reviews').length, 1);
    expect(store.data['session']['index'], 1);
    expect(storage.writes, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets(
      'tabs load on demand and hidden library retains its filter without rebuilding',
      (tester) async {
    SharedPreferences.setMockInitialValues(
        {'lexmemoria.v1': '{"starterInstalled":true,"onboarded":true}'});
    final prefs = await SharedPreferences.getInstance();
    final store = (await tester.runAsync(
        () => AppStore.load(persistence: PreferencesPersistence(prefs))))!;
    await tester.pumpWidget(LexMemoria(store: store));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryPage, skipOffstage: false), findsNothing);
    expect(find.byType(StudyPage, skipOffstage: false), findsNothing);
    await tester.tap(find.text('Biblioteca').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Constitución');
    await tester.pumpAndSettle();
    final library = tester.widget(find.byType(LibraryPage));
    await tester.tap(find.text('Perfil').last);
    await tester.pumpAndSettle();
    await tester.runAsync(() => store.setProfile({'dailyGoal': 30}));
    await tester.pumpAndSettle();
    expect(
        identical(tester.widget(find.byType(LibraryPage, skipOffstage: false)),
            library),
        true);
    await tester.tap(find.text('Biblioteca').last);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<EditableText>(find.byType(EditableText).first)
            .controller
            .text,
        'Constitución');
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
