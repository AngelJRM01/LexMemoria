import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/persistence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({
        'lexmemoria.v1': jsonEncode({'starterInstalled': true})
      }));
  test('review survives reload and can be undone without losing card',
      () async {
    final store = await AppStore.load(
        persistence:
            PreferencesPersistence(await SharedPreferences.getInstance()));
    final c = StudyCard(
        id: 'card-1', deck: 'Privado', front: 'Pregunta', back: 'Respuesta');
    await store.addCard(c);
    await store.review(c, 3);
    final loaded = await AppStore.load(
        persistence:
            PreferencesPersistence(await SharedPreferences.getInstance()));
    expect(loaded.list('reviews').length, 1);
    expect(loaded.state(c.id)['repetitions'], 1);
    expect(loaded.due(), isEmpty);
    await loaded.undoLast();
    expect(loaded.list('reviews'), isEmpty);
    expect(loaded.due().single.id, c.id);
    expect(loaded.cards.length, 1);
  });
  test('blocked cards cannot enter queue or be graded', () async {
    final s = await AppStore.load(
        persistence:
            PreferencesPersistence(await SharedPreferences.getInstance()));
    final c = StudyCard(
        id: 'blocked', deck: 'Law', front: 'Old', back: 'Old', blocked: true);
    await s.addCard(c);
    expect(s.due(), isEmpty);
    await expectLater(s.review(c, 3), throwsStateError);
    expect(s.list('reviews'), isEmpty);
  });
  test('changing track preserves progress and backup roundtrip', () async {
    final s = await AppStore.load(
        persistence:
            PreferencesPersistence(await SharedPreferences.getInstance()));
    await s.addCard(StudyCard(id: '1', deck: 'D', front: 'F', back: 'B'));
    await s.setProfile({'mode': 'Universidad'});
    final backup = s.export();
    await s.setProfile({'mode': 'Oposiciones'});
    expect(s.cards.length, 1);
    await s.reset();
    await s.restore(backup);
    expect(s.mode, 'Universidad');
    expect(s.cards.single.front, 'F');
    await expectLater(s.restore('{"schemaVersion":2}'), throwsFormatException);
  });
  test('new metadata quarantines stale offline pack and blocks linked card',
      () async {
    final s = await AppStore.load(
        persistence:
            PreferencesPersistence(await SharedPreferences.getInstance()));
    s.data['norms'] = [
      {
        'id': 'law',
        'latestVersion': 'v1',
        'units': [
          {'id': 'a1'}
        ]
      }
    ];
    await s.addCard(StudyCard(
        id: 'x',
        deck: 'Law',
        front: 'Q',
        back: 'A',
        normId: 'law',
        versionId: 'v1'));
    await s.review(s.cards.single, 3);
    await s.applyCatalogue([
      {'id': 'law', 'latestVersion': 'v2'}
    ]);
    expect(s.cards.single.blocked, isTrue);
    expect(s.list('norms').single['units'], isNull);
    expect(s.list('archivedPacks').single['latestVersion'], 'v1');
    expect(s.list('reviews').length, 1);
  });

  test('due queue obeys rest and vacation without deleting history', () async {
    final s = await AppStore.load(
        persistence:
            PreferencesPersistence(await SharedPreferences.getInstance()));
    await s
        .addCard(StudyCard(id: 'rest-card', deck: 'D', front: 'Q', back: 'A'));
    await s.setProfile({
      'restDays': [7],
      'vacations': [
        {'start': '2026-11-09', 'end': '2026-11-10'}
      ]
    });
    expect(s.due(at: DateTime(2026, 11, 8)), isEmpty);
    expect(s.due(at: DateTime(2026, 11, 9)), isEmpty);
    expect(s.due(at: DateTime(2026, 11, 11)).single.id, 'rest-card');
    expect(s.cards.length, 1);
  });
}
