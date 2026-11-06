import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/account_pages.dart';
import 'package:lexmemoria/collaboration.dart';
import 'package:lexmemoria/auto_sync.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/remote.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/persistence.dart';
import 'package:lexmemoria/workspace.dart';
import 'remote_test.dart' show Vault;

class Disk implements LocalPersistence {
  bool fail = false;
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String snapshot) async {
    if (fail) throw StateError('disk full');
    value = snapshot;
  }

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<AppStore> local({MockClient? client}) async => AppStore(
      await SharedPreferences.getInstance(), {'apiUrl': 'https://api.test'},
      client: client);
  testWidgets('local profile remains optional and never contacts backend',
      (tester) async {
    var calls = 0;
    final s = await local(client: MockClient((_) async {
      calls++;
      throw StateError('No network for local profile');
    }));
    await tester.pumpWidget(MaterialApp(home: PersonalProfilePage(store: s)));
    expect(find.text('Consultar perfil de mi cuenta'), findsNothing);
    await tester.enterText(find.byType(TextFormField).first, 'Ángel');
    await tester.scrollUntilVisible(find.text('Guardar perfil'), 300,
        scrollable: find.byType(Scrollable).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar perfil'));
    await tester.pumpAndSettle();
    expect(s.profile['account']['displayName'], 'Ángel');
    expect(calls, 0);
    expect(s.profile['account']['allowAliasInvitations'], false);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
  testWidgets(
      'collaboration does not require guest to connect or expose social feed',
      (tester) async {
    final s = await local();
    await tester.pumpWidget(MaterialApp(home: CollaborationPage(store: s)));
    expect(find.textContaining('Puedes seguir estudiando sin cuenta'),
        findsOneWidget);
    expect(find.text('Feed'), findsNothing);
    expect(
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Grupos privados'))
            .onTap,
        isNull);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
  test(
      'workspace includes reading, favorites and exam history, with scoped atomic commit',
      () async {
    final s = await local();
    final before = localWorkspace(s);
    final chosen = {
      ...before,
      'bookmarks': ['n'],
      'examHistory': [
        {'id': 'exam1'}
      ]
    };
    await s.commitWorkspace(before, chosen, chosen, null, s.apiBase);
    expect(s.data['bookmarks'], ['n']);
    expect(s.list('workspaceHistory').length, 1);
    final snapshot = localWorkspace(s);
    s.data['remoteUserId'] = 'other';
    await expectLater(
        s.commitWorkspace(
            snapshot,
            {
              ...snapshot,
              'notes': {'a': 'wrong account'}
            },
            snapshot,
            null,
            s.apiBase),
        throwsStateError);
    expect(s.data['notes'], {});
    s.dispose();
  });
  test('backup strips automatic consent and pending outbound authority',
      () async {
    final s = await local();
    s.data['autoSyncConsent'] = {'userId': 'old', 'server': 'https://api.test'};
    s.data['syncOutbox'] = {'state': 'pending'};
    final backup = s.export();
    await s.restore(backup);
    expect(s.data['autoSyncConsent'], isNull);
    expect(s.data['syncOutbox'], isNull);
    s.dispose();
  });
  test(
      'no backup success before server identity acknowledgement; dirty state follows edits',
      () async {
    var fail = true;
    final s = await local(client: MockClient((r) async {
      if (fail) return http.Response('{}', 503);
      return http.Response('{"userId":"u"}', 200);
    }));
    final sync = RemoteSync(s, secure: Vault());
    await sync
        .saveSession({'userId': 'u', 'accessToken': 'a', 'refreshToken': 'r'});
    await expectLater(sync.upload(), throwsStateError);
    expect(s.data['lastProgressSync'], isNull);
    fail = false;
    await sync.upload();
    expect(sync.progressStatus, 'Sincronizado');
    await s
        .addCard(StudyCard(id: 'new-card', deck: 'D', front: 'Q', back: 'A'));
    expect(sync.progressStatus, 'Cambios pendientes');
    s.dispose();
  });
  testWidgets(
      'automatic queue requires scoped consent and persists confirmation',
      (tester) async {
    var uploaded = 0;
    final s = await local(client: MockClient((r) async {
      if (r.url.path == '/v1/sync/status') {
        return http.Response('{"userId":"u","progressVersion":0}', 200);
      }
      if (r.url.path == '/v1/account/export') {
        return http.Response('{"userId":"u","records":[]}', 200);
      }
      if (r.url.path == '/v1/cards/lookup') {
        return http.Response('{"items":[]}', 200);
      }
      if (r.url.path == '/v1/auth/session') {
        return http.Response('{"userId":"u"}', 200);
      }
      if (r.url.path == '/v1/decks') return http.Response('{"id":"deck"}', 201);
      if (r.url.path == '/v1/cards') {
        uploaded++;
        return http.Response('{"id":"remote","revision":1}', 201);
      }
      throw StateError('Unexpected request');
    }));
    final sync = RemoteSync(s, secure: Vault());
    await sync
        .saveSession({'userId': 'u', 'accessToken': 'a', 'refreshToken': 'r'});
    await tester.pumpWidget(AutoSyncHost(
        store: s, remoteFactory: (_) => sync, child: const SizedBox()));
    await s.addCard(StudyCard(id: 'card-1', deck: 'D', front: 'Q', back: 'A'));
    await tester.pump(const Duration(seconds: 4));
    expect(uploaded, 0);
    await s.setAutoSync(true);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(uploaded, 1);
    expect(s.data['syncOutbox']['state'], 'confirmed');
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
  test(
      'divergent content and pending reviews survive as independent local fork',
      () async {
    late Json snapshot;
    final s = await local(
        client:
            MockClient((_) async => http.Response(jsonEncode(snapshot), 200)));
    final sync = RemoteSync(s, secure: Vault());
    await sync
        .saveSession({'userId': 'u', 'accessToken': 'a', 'refreshToken': 'r'});
    await s.addCard(
        StudyCard(id: 'card', deck: 'D', front: 'Q', back: 'Original'));
    await s.review(s.cards.single, 3);
    final common = s.list('reviews').single;
    s.data['reviews'] = [
      {...common, 'synced': true, 'syncedUserId': 'u'}
    ];
    s.data['remoteCardIds'] = {'card': 'remote-card'};
    s.data['remoteCardRevisions'] = {'card': 1};
    await s.editCard(
        StudyCard(
            id: 'card', deck: 'D', front: 'Q', back: 'Mi edición', revision: 2),
        expectedRevision: 1);
    await s.review(s.cards.single, 1);
    final pending = s.list('reviews').last;
    final serverState = schedule({}, 3, DateTime.parse(common['occurredAt']));
    snapshot = {
      'userId': 'u',
      'records': [
        {'kind': 'deck', 'id': 'deck', 'title': 'D'},
        {
          'kind': 'card',
          'id': 'remote-card',
          'clientId': 'card',
          'deckId': 'deck',
          'front': 'Q',
          'back': 'Edición del otro dispositivo',
          'revision': 2
        },
        {
          'kind': 'card_revision',
          'cardId': 'remote-card',
          'cardRevision': 1,
          'content': {'deckId': 'deck', 'front': 'Q', 'back': 'Original'},
          'archivedAt': '2026-11-06T10:00:00Z'
        },
        {
          ...common,
          'kind': 'review_event',
          'cardId': 'remote-card',
          'idempotencyKey': common['id']
        },
        {...serverState, 'kind': 'review_state', 'cardId': 'remote-card'},
      ]
    };
    await sync.pull();
    expect(s.list('syncConflicts'), isNotEmpty);
    await sync.forkConflict('card');
    expect(s.list('syncConflicts'), isEmpty);
    expect(s.cards.firstWhere((c) => c.id == 'card').back,
        'Edición del otro dispositivo');
    final fork = s.cards.singleWhere((c) => c.id != 'card');
    expect(fork.back, 'Mi edición');
    expect(fork.blocked, isFalse);
    final copyEvent =
        s.list('reviews').singleWhere((e) => e['cardId'] == fork.id);
    expect(copyEvent['rating'], pending['rating']);
    expect(copyEvent['cardRevision'], 2);
    expect(copyEvent['id'], isNot(pending['id']));
    expect(s.list('conflictArchive').single['pendingReviews'].single['id'],
        pending['id']);
    expect(s.list('cardHistory').where((h) => h['id'] == fork.id).length, 1);
    s.dispose();
  });
  test('recovery retries a lost response using a vault-persisted attempt',
      () async {
    Json? attempt;
    var calls = 0;
    final s = await local(client: MockClient((r) async {
      calls++;
      final body = Json.from(jsonDecode(r.body));
      expect(r.url.path, '/v1/auth/recover-idempotent');
      if (calls == 1) {
        attempt = body;
        throw http.ClientException('simulated lost response');
      }
      expect(body, attempt);
      return http.Response(
          '{"userId":"u","accessToken":"a","refreshToken":"r","recoveryCode":"replacement-private-code-1234567890"}',
          200);
    }));
    final sync = RemoteSync(s, secure: Vault());
    await expectLater(sync.recover('old-code-123456789012345'),
        throwsA(isA<http.ClientException>()));
    expect(s.data['remoteUserId'], isNull);
    expect(await sync.recover('old-code-123456789012345'),
        'replacement-private-code-1234567890');
    expect(s.export().contains(attempt!['attemptSecret']), isFalse);
    s.dispose();
  });
  test('failed remote download write leaves every local field unchanged',
      () async {
    final disk = Disk();
    final s = AppStore(
        await SharedPreferences.getInstance(), {'apiUrl': 'https://api.test'},
        persistence: disk,
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'userId': 'u',
              'records': [
                {'kind': 'deck', 'id': 'd', 'title': 'D'},
                {
                  'kind': 'card',
                  'id': 'remote',
                  'clientId': 'card-local',
                  'deckId': 'd',
                  'front': 'Q',
                  'back': 'A',
                  'revision': 1
                }
              ]
            }),
            200)));
    final sync = RemoteSync(s, secure: Vault());
    await sync
        .saveSession({'userId': 'u', 'accessToken': 'a', 'refreshToken': 'r'});
    final before = jsonEncode(s.data);
    disk.fail = true;
    await expectLater(sync.pull(), throwsStateError);
    expect(jsonEncode(s.data), before);
    expect(s.data['lastProgressSync'], isNull);
    s.dispose();
  });
  test(
      'lost aliases recover matching server revision without duplicates or moving a copied deck',
      () async {
    var posts = 0, lookups = 0, deckPosts = 0;
    final s = await local(client: MockClient((r) async {
      if (r.url.path == '/v1/auth/session') {
        return http.Response('{"userId":"u"}', 200);
      }
      if (r.url.path == '/v1/decks') {
        deckPosts++;
        return http.Response('{"id":"native-deck"}', 201);
      }
      if (r.url.path == '/v1/cards') {
        posts++;
        return http.Response('{}', 409);
      }
      if (r.url.path == '/v1/cards/lookup') {
        lookups++;
        return http.Response(
            jsonEncode({
              'items': [
                {
                  'id': 'remote',
                  'clientId': 'card-local',
                  'deckId': 'copied-deck',
                  'deckTitle': 'D',
                  'front': 'Q',
                  'back': 'Local 2',
                  'explanation': '',
                  'type': 'qa',
                  'options': [],
                  'correct': null,
                  'citations': [],
                  'revision': 2
                }
              ]
            }),
            200);
      }
      if (r.url.path == '/v1/cards/remote') {
        expect(jsonDecode(r.body)['deckId'], 'copied-deck');
        return http.Response(
            '{"id":"remote","deckId":"copied-deck","revision":3}', 200);
      }
      throw StateError('Unexpected request');
    }));
    final sync = RemoteSync(s, secure: Vault());
    await sync
        .saveSession({'userId': 'u', 'accessToken': 'a', 'refreshToken': 'r'});
    await s.addCard(
        StudyCard(id: 'card-local', deck: 'D', front: 'Q', back: 'Original'));
    await s.editCard(
        StudyCard(
            id: 'card-local',
            deck: 'D',
            front: 'Q',
            back: 'Local 2',
            revision: 2),
        expectedRevision: 1);
    await sync.upload();
    expect(posts, 0);
    expect(lookups, 1);
    expect(s.data['remoteCardRevisions']['card-local'], 2);
    await s.editCard(
        StudyCard(
            id: 'card-local',
            deck: 'D',
            front: 'Q',
            back: 'Local 3',
            revision: 3),
        expectedRevision: 2);
    await sync.upload();
    expect(deckPosts, 0);
    expect(s.data['remoteCardRevisions']['card-local'], 3);
    s.dispose();
  });
  test(
      'calendar honors available time while keeping overdue reviews before preferences',
      () async {
    expect(
        studyCapacity(
            {'dailyGoal': 200, 'hours': .5, 'estimatedSecondsPerCard': 120}),
        15);
    final s = await local();
    await s.setProfile({
      'dailyGoal': 20,
      'deckPriorities': {'Priority': 1},
      'preferredExerciseTypes': ['test']
    });
    await s.addCard(StudyCard(id: 'old', deck: 'Other', front: 'Q', back: 'A'));
    await s.review(s.cards.single, 1);
    s.data['states']['old']['dueAt'] = '2020-01-01T00:00:00Z';
    await s.addCard(StudyCard(
        id: 'new',
        deck: 'Priority',
        front: 'Q',
        back: 'A',
        type: 'test',
        options: ['A', 'B'],
        correct: 0));
    expect(s.due(includeRest: true).first.id, 'old');
    s.dispose();
  });
  test(
      'workspace merges separate device changes and keeps account authority outside academic data',
      () async {
    late Json serverWorkspace;
    final s = await local(client: MockClient((r) async {
      if (r.url.path == '/v1/auth/session') {
        return http.Response('{"userId":"u"}', 200);
      }
      if (r.url.path == '/v1/account/profile') {
        return http.Response(
            jsonEncode({'data': accountProfileDefaults, 'revision': 1}), 200);
      }
      if (r.url.path == '/v1/workspace') {
        if (r.method == 'PUT') serverWorkspace = Json.from(jsonDecode(r.body));
        return http.Response(
            jsonEncode({
              'data': serverWorkspace,
              'revision': r.method == 'PUT' ? 3 : 2
            }),
            200);
      }
      throw StateError('Unexpected request ${r.url.path}');
    }));
    final sync = RemoteSync(s, secure: Vault());
    await sync
        .saveSession({'userId': 'u', 'accessToken': 'a', 'refreshToken': 'r'});
    final base = localWorkspace(s);
    s.data['workspaceBase'] = base;
    s.data['notes'] = {'article': 'Local note'};
    serverWorkspace = {
      ...base,
      'bookmarks': ['remote-norm'],
      'remoteUserId': 'injected'
    };
    await WorkspaceSynchronizer(s, remote: sync).synchronize();
    expect(s.data['notes'], {'article': 'Local note'});
    expect(s.data['bookmarks'], ['remote-norm']);
    expect(s.data['remoteUserId'], 'u');
    expect(s.data['workspaceBase']['remoteUserId'], 'injected');
    expect(serverWorkspace['profile'].containsKey('account'), false);
    expect(s.profile['account'], accountProfileDefaults);
    expect(s.data['workspaceRevision'], 3);
    s.dispose();
  });
  test(
      'workspace simultaneous edits stop before upload and preserve local notes',
      () async {
    var writes = 0;
    final s = await local(client: MockClient((r) async {
      if (r.url.path == '/v1/auth/session') {
        return http.Response('{"userId":"u"}', 200);
      }
      if (r.url.path == '/v1/account/profile') {
        return http.Response(
            jsonEncode({'data': accountProfileDefaults, 'revision': 1}), 200);
      }
      if (r.method == 'PUT') writes++;
      return http.Response(
          jsonEncode({
            'data': {
              'notes': {'a': 'Other device'}
            },
            'revision': 2
          }),
          200);
    }));
    final sync = RemoteSync(s, secure: Vault());
    await sync
        .saveSession({'userId': 'u', 'accessToken': 'a', 'refreshToken': 'r'});
    s.data['workspaceBase'] = localWorkspace(s);
    s.data['notes'] = {'a': 'Local edit'};
    await expectLater(WorkspaceSynchronizer(s, remote: sync).synchronize(),
        throwsA(isA<RemoteSyncFailure>()));
    expect(writes, 0);
    expect(s.data['notes'], {'a': 'Local edit'});
    s.dispose();
  });
  test('a remote-only card edit downloads without manufacturing a conflict',
      () async {
    final s = await local(
        client: MockClient((r) async => http.Response(
            jsonEncode({
              'userId': 'u',
              'records': [
                {'kind': 'deck', 'id': 'd', 'title': 'D'},
                {
                  'kind': 'card',
                  'id': 'r',
                  'clientId': 'c',
                  'deckId': 'd',
                  'front': 'Q',
                  'back': 'New server answer',
                  'revision': 2
                }
              ]
            }),
            200)));
    final sync = RemoteSync(s, secure: Vault());
    await sync
        .saveSession({'userId': 'u', 'accessToken': 'a', 'refreshToken': 'r'});
    await s
        .addCard(StudyCard(id: 'c', deck: 'D', front: 'Q', back: 'Old answer'));
    s.data['remoteCardRevisions'] = {'c': 1};
    await sync.pull();
    expect(s.cards.single.back, 'New server answer');
    expect(s.list('syncConflicts'), isEmpty);
    s.dispose();
  });
  test(
      'notes and finished exam commit atomically and reject stale device edits',
      () async {
    final disk = Disk();
    final s =
        AppStore(await SharedPreferences.getInstance(), {}, persistence: disk);
    disk.fail = true;
    await expectLater(
        s.updateNote('a', 'Draft', expected: null), throwsStateError);
    expect(s.data['notes'], isNull);
    disk.fail = false;
    await s.updateNote('a', 'Saved', expected: null);
    await expectLater(
        s.updateNote('a', 'Old form', expected: null), throwsStateError);
    expect(s.data['notes']['a'], 'Saved');
    final attempt = {
      'id': 'exam',
      'answers': {'q': 1},
      'result': {'score': 1}
    };
    disk.fail = true;
    await expectLater(s.updateExam(attempt, expected: null), throwsStateError);
    expect(s.data['activeExam'], isNull);
    expect(s.list('examHistory'), isEmpty);
    disk.fail = false;
    await s.updateExam(attempt, expected: null);
    expect(s.list('examHistory').length, 1);
    await s.updateExam(attempt, expected: attempt);
    expect(s.list('examHistory').length, 1);
    await expectLater(s.updateExam(null, expected: null), throwsStateError);
    expect(s.data['activeExam']['id'], 'exam');
    s.dispose();
  });
  test(
      'course editing uses stable identity and preserves another device changes',
      () async {
    final disk = Disk();
    final s =
        AppStore(await SharedPreferences.getInstance(), {}, persistence: disk);
    final course = {'id': 'c', 'title': 'Derecho', 'topics': []};
    final other = {'id': 'other', 'title': 'Otra'};
    s.data['courses'] = [other, course];
    await s.updateCourse({...course, 'title': 'Editada'}, expected: course);
    expect(s.list('courses').first, other);
    final saved = s.list('courses').last;
    await expectLater(
        s.updateCourse({...course, 'title': 'Obsoleta'}, expected: course),
        throwsStateError);
    expect(s.list('courses').last, saved);
    disk.fail = true;
    await expectLater(
        s.updateCourse({...saved, 'title': 'Sin espacio'}, expected: saved),
        throwsStateError);
    expect(s.list('courses').last, saved);
    s.dispose();
  });
  testWidgets(
      'workspace transport failure does not mark card progress as failed',
      (tester) async {
    final s = await local(client: MockClient((r) async {
      if (r.url.path == '/v1/auth/session') {
        return http.Response('{"userId":"u"}', 200);
      }
      if (r.url.path == '/v1/sync/status') {
        return http.Response(
            '{"userId":"u","workspaceRevision":1,"profileRevision":1}', 200);
      }
      return http.Response('{"detail":"Unavailable"}', 503);
    }));
    final sync = RemoteSync(s, secure: Vault());
    await sync
        .saveSession({'userId': 'u', 'accessToken': 'a', 'refreshToken': 'r'});
    await s.setAutoWorkspace(true);
    await tester.pumpWidget(AutoSyncHost(
        store: s, remoteFactory: (_) => sync, child: const SizedBox()));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(s.data['workspaceOutbox']['state'], 'error');
    expect(s.data['syncOutbox'], isNull);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
  testWidgets('group administrator can revoke a member from the interface',
      (tester) async {
    var removed = false;
    final s = await local(client: MockClient((r) async {
      if (r.url.path == '/v1/auth/session') {
        return http.Response('{"userId":"admin"}', 200);
      }
      if (r.method == 'DELETE') {
        removed = true;
        return http.Response('{"removed":true}', 200);
      }
      return http.Response(
          jsonEncode({
            'name': 'Grupo',
            'role': 'admin',
            'revision': 1,
            'members': removed
                ? []
                : [
                    {
                      'id': 'member',
                      'displayName': 'Compañero',
                      'role': 'member'
                    }
                  ],
            'resources': []
          }),
          200);
    }));
    final sync = RemoteSync(s, secure: Vault());
    await sync.saveSession(
        {'userId': 'admin', 'accessToken': 'a', 'refreshToken': 'r'});
    // The page uses the native vault. Seed the same test session through its shared fixture.
    final page = StudyGroupPage(store: s, id: 'group');
    // Route calls use RemoteSync's default vault, so provide its platform method response.
    const channel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'read') {
        return jsonEncode(
            {'userId': 'admin', 'accessToken': 'a', 'refreshToken': 'r'});
      }
      return null;
    });
    await tester.pumpWidget(MaterialApp(home: page));
    await tester.tap(find.text('Consultar grupo'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Miembros'));
    await tester.tap(find.text('Miembros'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byTooltip('Retirar acceso'));
    await tester.tap(find.byTooltip('Retirar acceso'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Confirmar'));
    await tester.pumpAndSettle();
    expect(removed, true);
    await tester.pumpWidget(const SizedBox());
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    s.dispose();
  });
}
