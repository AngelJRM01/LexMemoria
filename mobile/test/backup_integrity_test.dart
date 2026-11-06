import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/backup.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/persistence.dart';

class Disk implements LocalPersistence {
  String? value;
  bool fail = false;
  Completer<void>? gate;
  Completer<void>? entered;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String text) async {
    entered?.complete();
    entered = null;
    final wait = gate;
    gate = null;
    if (wait != null) await wait.future;
    if (fail) throw StateError('simulated disk failure');
    value = text;
  }

  @override
  Future<void> close() async {}
}

String backup(Json data) => jsonEncode({'schemaVersion': 1, 'data': data});
Json card(String id) =>
    StudyCard(id: id, deck: 'D', front: 'Q', back: 'A').toJson();
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('malformed backups are rejected before touching live or persisted data',
      () async {
    final disk = Disk();
    final store = AppStore(
        await SharedPreferences.getInstance(),
        {
          'cards': [card('original')]
        },
        persistence: disk);
    await store.save();
    final before = disk.value;
    for (final invalid in <Json>[
      {
        'cards': [card('x'), card('x')]
      },
      {
        'cards': [
          {
            ...card('x'),
            'correct': 4,
            'options': ['a', 'b']
          }
        ]
      },
      {
        'cards': [
          {...card('x'), 'blocked': 'false'}
        ]
      },
      {
        'states': {
          'x': {'interval': -1}
        }
      },
      {
        'reviews': [
          {'id': 'e', 'cardId': 'x', 'rating': 8, 'occurredAt': '2026-01-01'}
        ]
      },
      {
        'notes': {
          'x': {'unexpected': 'object'}
        }
      },
      {
        'profile': {
          'restDays': [8]
        }
      },
      {
        'favoriteCards': [42]
      },
    ]) {
      await expectLater(store.restore(backup(invalid)), throwsFormatException);
      expect(store.cards.single.id, 'original');
      expect(disk.value, before);
    }
    store.dispose();
  });
  test('failed restore and reset preserve both memory and disk', () async {
    final disk = Disk();
    final store = AppStore(
        await SharedPreferences.getInstance(),
        {
          'cards': [card('original')],
          'notes': {'a': 'private'}
        },
        persistence: disk);
    await store.save();
    final before = disk.value;
    disk.fail = true;
    await expectLater(
        store.restore(backup({
          'cards': [card('replacement')]
        })),
        throwsStateError);
    await expectLater(store.reset(), throwsStateError);
    expect(store.cards.single.id, 'original');
    expect(disk.value, before);
    disk.fail = false;
    await store.save();
    expect(disk.value, before);
    store.dispose();
  });
  test('restore checkpoint survives reload and can recover the preceding data',
      () async {
    final disk = Disk();
    final store = AppStore(
        await SharedPreferences.getInstance(),
        {
          'cards': [card('original')],
          'notes': {'a': 'private'},
          'futureField': {'preserve': true}
        },
        persistence: disk);
    await store.save();
    await store.restore(backup({
      'cards': [card('replacement')],
      'futureField': {'new': true}
    }));
    expect(store.cards.single.id, 'replacement');
    final reopened = AppStore(await SharedPreferences.getInstance(),
        Json.from(jsonDecode(disk.value!)),
        persistence: disk);
    await reopened.recoverBeforeRestore();
    expect(reopened.cards.single.id, 'original');
    expect(reopened.data['notes']['a'], 'private');
    expect(reopened.data['futureField']['preserve'], isTrue);
    expect(reopened.data['restoreCheckpoint']['data']['restoreCheckpoint'],
        isNull);
    store.dispose();
    reopened.dispose();
  });
  test(
      'concurrent edit during restore cancels replacement and persists latest edit',
      () async {
    final disk = Disk();
    final store = AppStore(
        await SharedPreferences.getInstance(),
        {
          'cards': [card('original')]
        },
        persistence: disk);
    await store.save();
    final gate = Completer<void>();
    final entered = Completer<void>();
    disk.gate = gate;
    disk.entered = entered;
    final operation = store.restore(backup({
      'cards': [card('replacement')]
    }));
    final failed = expectLater(operation, throwsStateError);
    await entered.future;
    store.data['cards'] = [
      ...store.cards.map((c) => c.toJson()),
      card('concurrent')
    ];
    final edit = store.save();
    gate.complete();
    await failed;
    await edit;
    expect(store.cards.map((c) => c.id), ['original', 'concurrent']);
    expect((jsonDecode(disk.value!)['cards'] as List).map((c) => c['id']),
        ['original', 'concurrent']);
    store.dispose();
  });
  test(
      'portable backup strips authority but retains account provenance and unknown data',
      () {
    final restored = decodeStudyBackup(backup({
      'remoteUserId': 'owner',
      'remoteServer': 'https://example.test',
      'remoteCardIds': {'x': 'y'},
      'auth': {'secret': 'must disappear'},
      'futureField': 42
    }));
    expect(restored['remoteUserId'], isNull);
    expect(restored['remoteServer'], isNull);
    expect(restored['remoteCardIds'], isNull);
    expect(restored['auth'], isNull);
    expect(restored['localDataOwnerId'], 'owner');
    expect(restored['futureField'], 42);
  });
  test('failed review, edit and undo do not publish an uncommitted state',
      () async {
    final disk = Disk();
    final store = AppStore(
        await SharedPreferences.getInstance(),
        {
          'cards': [card('original')]
        },
        persistence: disk);
    await store.save();
    disk.fail = true;
    await expectLater(store.review(store.cards.single, 3), throwsStateError);
    expect(store.list('reviews'), isEmpty);
    expect(store.state('original'), isEmpty);
    await expectLater(
        store.editCard(
            StudyCard(
                id: 'original',
                deck: 'D',
                front: 'Changed',
                back: 'A',
                revision: 2),
            expectedRevision: 1),
        throwsStateError);
    expect(store.cards.single.front, 'Q');
    expect(store.list('cardHistory'), isEmpty);
    disk.fail = false;
    await store.review(store.cards.single, 3);
    expect(store.list('reviews').length, 1);
    disk.fail = true;
    await expectLater(store.undoLast(), throwsStateError);
    expect(store.list('reviews').length, 1);
    disk.fail = false;
    await store.undoLast();
    expect(store.list('reviews'), isEmpty);
    store.dispose();
  });
  test('queued independent mutations commit serially without losing additions',
      () async {
    final disk = Disk();
    final store =
        AppStore(await SharedPreferences.getInstance(), {}, persistence: disk);
    await Future.wait([
      store.addCard(StudyCard(id: 'one', deck: 'D', front: 'Q', back: 'A')),
      store.addCard(StudyCard(id: 'two', deck: 'D', front: 'Q', back: 'A')),
      store.setProfile({'dailyGoal': 30}),
      store.setProfile({'subject': 'Civil'})
    ]);
    expect(store.cards.map((c) => c.id), ['one', 'two']);
    expect(store.profile['dailyGoal'], 30);
    expect(store.profile['subject'], 'Civil');
    expect((jsonDecode(disk.value!)['cards'] as List).length, 2);
    store.dispose();
  });
}
