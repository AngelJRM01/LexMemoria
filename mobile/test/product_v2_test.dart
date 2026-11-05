import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/persistence.dart';
import 'package:lexmemoria/exercises.dart';
import 'package:lexmemoria/university.dart';
import 'package:lexmemoria/workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('editing archives content and preserves review history', () async {
    final store = AppStore(await SharedPreferences.getInstance(), {});
    await store
        .addCard(StudyCard(id: 'card', deck: 'D', front: 'Q', back: 'A'));
    await store.review(store.cards.single, 3);
    final before = store.state('card');
    await store.editCard(
        StudyCard(
            id: 'card', deck: 'D', front: 'Q', back: 'Corrected', revision: 2),
        expectedRevision: 1);
    expect(store.state('card'), before);
    expect(store.list('reviews').single['cardRevision'], 1);
    expect(store.list('cardHistory').single['back'], 'A');
    expect(store.cards.single.revision, 2);
    await expectLater(store.editCard(store.cards.single, expectedRevision: 1),
        throwsStateError);
    await expectLater(
        store.review(
            StudyCard(id: 'card', deck: 'D', front: 'Q', back: 'A'), 3),
        throwsStateError);
    store.dispose();
  });
  test('university grades preserve weighting and pending assessments', () {
    final a = <Json>[
      {'weight': 60, 'maximum': 20, 'score': 10},
      {'weight': 40, 'maximum': 10, 'score': null},
    ];
    expect(courseGrade(a),
        {'weight': 100.0, 'completedWeight': 60.0, 'earned': 3.0});
    expect(
        () => courseGrade([
              ...a,
              {'weight': 1, 'maximum': 10}
            ]),
        throwsFormatException);
    expect(
        () => courseGrade([
              {'weight': 50, 'maximum': 10, 'score': 11}
            ]),
        throwsFormatException);
    expect(
        () => courseGrade([
              {'weight': 50, 'maximum': 0}
            ]),
        throwsFormatException);
  });
  testWidgets('true false accepts response then reveals feedback',
      (tester) async {
    final card = StudyCard(
        id: 'c',
        deck: 'D',
        front: 'Pregunta',
        back: 'Explicación',
        type: 'truefalse',
        options: ['Verdadero', 'Falso'],
        correct: 0);
    dynamic answer;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ExerciseInput(
                card: card, revealed: false, onChanged: (v) => answer = v))));
    await tester.tap(find.text('A. Verdadero'));
    expect(answer, 0);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ExerciseInput(
                card: card, revealed: true, onChanged: (v) => answer = v))));
    expect(find.text('Respuesta correcta.'), findsOneWidget);
  });
  testWidgets('ordering exposes accessible controls and records order',
      (tester) async {
    final card = StudyCard(
        id: 'o',
        deck: 'D',
        front: 'Ordena',
        back: 'Orden',
        type: 'order',
        options: ['Uno', 'Dos', 'Tres']);
    dynamic answer;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ExerciseInput(
                card: card, revealed: false, onChanged: (v) => answer = v))));
    await tester.pump();
    expect(answer, isA<List<int>>());
    final before = List<int>.from(answer);
    await tester.tap(find.byTooltip('Bajar elemento 1'));
    expect(answer, isNot(before));
    expect((answer as List).toSet(), {0, 1, 2});
  });
  testWidgets('guest layout supports text scale 200 percent', (tester) async {
    // A narrow, large-text course page exercises wrapping and form navigation.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore(await SharedPreferences.getInstance(), {});
    await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2)),
            child: child!),
        home: UniversityPage(store: store)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    store.dispose();
  });
  test(
      'bundled BOE texts verify hashes and reload without copying text into preferences',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store =
        await AppStore.load(persistence: PreferencesPersistence(prefs));
    expect(store.bundledNorms.length, 20);
    final constitution =
        store.catalogue.firstWhere((n) => n['id'] == 'BOE-A-1978-31229');
    expect(constitution['units'], isNull);
    final beforeDownload = prefs.getString('lexmemoria.v1')!.length;
    await store.downloadNorm(constitution);
    final loaded =
        store.catalogue.firstWhere((n) => n['id'] == constitution['id']);
    expect((loaded['units'] as List).length, greaterThan(100));
    expect(loaded['attribution'], contains('Agencia Estatal'));
    expect(prefs.getString('lexmemoria.v1')!.length - beforeDownload,
        lessThan(10000));
    final restored =
        await AppStore.load(persistence: PreferencesPersistence(prefs));
    expect(
        restored.catalogue
            .firstWhere((n) => n['id'] == constitution['id'])['units'],
        isNotNull);
    Object? integrityError;
    try {
      await store.loadBundledPack({...constitution, 'bundledHash': 'invalid'});
    } catch (error) {
      integrityError = error;
    }
    expect(integrityError, isA<StateError>());
    store.dispose();
    restored.dispose();
  });

  test(
      'workspace three-way merge combines independent edits and retains conflicts',
      () {
    final base = <String, dynamic>{
      'profile': {'dailyGoal': 20},
      'notes': {},
      'courses': [],
      'follows': []
    };
    final local = {
      ...base,
      'notes': {'a': 'Local note'}
    };
    final remote = {
      ...base,
      'courses': [
        {'id': 'course-1'}
      ]
    };
    final result = mergeWorkspace(local, remote, base);
    expect(result['conflicts'], isEmpty);
    expect(result['merged']['notes'], {'a': 'Local note'});
    expect(result['merged']['courses'], [
      {'id': 'course-1'}
    ]);
    expect(
        mergeWorkspace(
            local,
            {
              ...remote,
              'notes': {'a': 'Remote note'}
            },
            base)['conflicts'],
        ['notes']);
    expect(equalWorkspace({'b': 1, 'a': 2}, {'a': 2, 'b': 1}), isTrue);
  });
}
