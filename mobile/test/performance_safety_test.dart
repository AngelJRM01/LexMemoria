import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/remote.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<AppStore> store() async =>
      AppStore(await SharedPreferences.getInstance(), {});
  test(
      'metadata saves preserve card objects and synchronization hash; actual progress invalidates it',
      () async {
    final s = await store();
    await s.addCard(StudyCard(id: 'c', deck: 'D', front: 'Q', back: 'A'));
    final cards = s.cards;
    final sync = RemoteSync(s);
    final hash = sync.progressFingerprint;
    expect(hash, progressFingerprintOf(s.data));
    await s.setProfile({'dailyGoal': 30});
    expect(identical(cards, s.cards), true);
    expect(sync.progressFingerprint, hash);
    await s.review(s.cards.single, 3);
    expect(identical(cards, s.cards), true);
    expect(sync.progressFingerprint, isNot(hash));
    final reviewed = sync.progressFingerprint;
    expect(reviewed, progressFingerprintOf(s.data));
    await s.editCard(
        StudyCard(id: 'c', deck: 'D', front: 'Edited', back: 'A', revision: 2),
        expectedRevision: 1);
    expect(identical(cards, s.cards), false);
    expect(s.cards.single.front, 'Edited');
    expect(sync.progressFingerprint, isNot(reviewed));
    s.dispose();
  });
  test(
      'legacy raw edits become visible after save instead of leaving stale cache or hash',
      () async {
    final s = await store();
    await s.addCard(StudyCard(id: 'c', deck: 'D', front: 'Q', back: 'A'));
    final sync = RemoteSync(s);
    final hash = sync.progressFingerprint;
    expect(s.cards.single.front, 'Q');
    s.data['cards'][0]['front'] = 'Raw change';
    await s.save();
    expect(s.cards.single.front, 'Raw change');
    expect(sync.progressFingerprint, isNot(hash));
    s.dispose();
  });
  test(
      'bounded study session keeps overdue ordering, lapses and filters ahead of new-card preferences',
      () async {
    final s = await store();
    s.data = {
      'profile': {
        'dailyGoal': 3,
        'hours': 1,
        'deckPriorities': {'Preferred': 100}
      },
      'cards': [
        ...List.generate(
            20000,
            (i) => StudyCard(
                    id: 'new-$i', deck: 'Preferred', front: 'Q', back: 'A')
                .toJson()),
        for (final id in ['old-a', 'old-b', 'old-c'])
          StudyCard(id: id, deck: 'D', front: 'Q', back: 'A').toJson(),
        StudyCard(
                id: 'blocked', deck: 'D', front: 'Q', back: 'A', blocked: true)
            .toJson(),
        StudyCard(id: 'future', deck: 'D', front: 'Q', back: 'A').toJson()
      ],
      'states': {
        'old-a': {'dueAt': '2026-11-01T12:00:00Z', 'lapses': 1},
        'old-b': {'dueAt': '2026-11-02T12:00:00Z', 'lapses': 9},
        'old-c': {'dueAt': '2026-11-02T12:00:00Z', 'lapses': 1},
        'future': {'dueAt': '2030-01-01T00:00:00Z'}
      }
    };
    expect(
        s
            .due(at: DateTime.utc(2026, 11, 7), includeRest: true)
            .map((c) => c.id),
        ['old-a', 'old-b', 'old-c']);
    expect(
        s
            .due(deck: 'D', at: DateTime.utc(2026, 11, 7), includeRest: true)
            .map((c) => c.id),
        ['old-a', 'old-b', 'old-c']);
    s.dispose();
  });
  test(
      'judicial review marker survives bundled metadata and preserves original educational data',
      () async {
    final s = await store();
    s.corpusNorms = [
      {
        'id': 'law',
        'latestVersion': 'v1',
        'studyReviewUnitIds': ['a1']
      }
    ];
    s.bundledNorms = [
      {'id': 'law', 'latestVersion': 'v1'}
    ];
    await s.addCard(StudyCard(
        id: 'c',
        deck: 'D',
        front: 'Q',
        back: 'A',
        normId: 'law',
        unitId: 'a1',
        versionId: 'v1',
        editorialState: 'source_literal'));
    expect(s.cards.single.blocked, true);
    expect(s.cards.single.editorialState, 'pending_legal_context');
    expect(s.data['cards'][0]['blocked'], false);
    await expectLater(s.review(s.cards.single, 3), throwsStateError);
    expect(s.list('reviews'), isEmpty);
    expect(s.export(), contains('"id": "c"'));
    s.dispose();
  });
  test('fresh published source does not get hidden by old cached metadata',
      () async {
    final s = await store();
    s.data['norms'] = [
      {
        'id': 'law',
        'latestVersion': 'old',
        'sourceUpdatedAt': '20261105T000000Z',
        'packReady': true,
        'units': [
          {'id': 'a1'}
        ]
      }
    ];
    s.corpusNorms = [
      {
        'id': 'law',
        'latestVersion': 'new',
        'sourceUpdatedAt': '20261107T000000Z',
        'packHash': 'newhash'
      }
    ];
    final current = s.catalogue.firstWhere((n) => n['id'] == 'law');
    expect(current['latestVersion'], 'new');
    expect(current['units'], isNull);
    expect(current['packReady'], false);
    expect(s.data['norms'][0]['latestVersion'], 'old');
    s.dispose();
  });
  test(
      'newer locally imported source is not downgraded or marked stale by an older shipped catalogue',
      () async {
    final s = await store();
    s.data['norms'] = [
      {
        'id': 'law',
        'latestVersion': 'newer',
        'sourceUpdatedAt': '20261108T000000Z'
      }
    ];
    s.corpusNorms = [
      {
        'id': 'law',
        'latestVersion': 'older',
        'sourceUpdatedAt': '20261107T000000Z'
      }
    ];
    await s.addCard(StudyCard(
        id: 'c',
        deck: 'D',
        front: 'Q',
        back: 'A',
        normId: 'law',
        unitId: 'a1',
        versionId: 'newer',
        editorialState: 'source_literal'));
    expect(s.catalogue.firstWhere((n) => n['id'] == 'law')['latestVersion'],
        'newer');
    expect(s.cards.single.blocked, false);
    s.dispose();
  });
}
