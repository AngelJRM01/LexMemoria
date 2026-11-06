import 'dart:convert';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/remote.dart';

class Vault implements CredentialVault {
  final values = <String, String>{};
  bool failWrites = false;
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    if (failWrites) throw StateError('simulated secure-store failure');
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class SessionFailingVault extends Vault {
  @override
  Future<void> write(String key, String value) async {
    if (key.endsWith(':session')) {
      throw StateError('simulated session vault failure');
    }
    return super.write(key, value);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('expired token refreshes without exporting credentials', () async {
    var requests = 0;
    final s = AppStore(await SharedPreferences.getInstance(),
        {'apiUrl': 'https://example.test'}, client: MockClient((r) async {
      if (r.url.path.endsWith('refresh')) {
        return http.Response(
            jsonEncode({
              'accessToken': 'new-access',
              'refreshToken': 'new-refresh',
              'userId': 'u'
            }),
            200);
      }
      requests++;
      if (requests == 1) return http.Response('{}', 401);
      expect(r.headers['Authorization'], 'Bearer new-access');
      return http.Response('{"records":[],"userId":"u"}', 200);
    }));
    final vault = Vault();
    final sync = RemoteSync(s, secure: vault);
    await sync.saveSession({
      'accessToken': 'old-access',
      'refreshToken': 'old-refresh',
      'userId': 'u'
    });
    expect((await sync.exportRemote())['userId'], 'u');
    expect(requests, 2);
    expect(s.export().contains('new-access'), isFalse);
    expect(s.export().contains('new-refresh'), isFalse);
    s.dispose();
  });
  test('credentials are scoped by API path, not hostname only', () async {
    var called = false;
    final s = AppStore(await SharedPreferences.getInstance(),
        {'apiUrl': 'https://example.test/a'}, client: MockClient((_) async {
      called = true;
      return http.Response('{}', 200);
    }));
    final vault = Vault();
    final first = RemoteSync(s, secure: vault);
    await first
        .saveSession({'accessToken': 'a', 'refreshToken': 'b', 'userId': 'u'});
    s.data['apiUrl'] = 'https://example.test/b';
    await expectLater(
        RemoteSync(s, secure: vault).exportRemote(), throwsStateError);
    expect(called, isFalse);
    s.dispose();
  });
  test('pull restores cards, history and state without duplicate events',
      () async {
    final snapshot = {
      'userId': 'u',
      'records': [
        {'kind': 'deck', 'id': 'd1', 'title': 'Recuperado'},
        {
          'kind': 'card',
          'id': 'remote-card',
          'clientId': 'local-card',
          'deckId': 'd1',
          'front': 'Q',
          'back': 'A',
          'revision': 1
        },
        {
          'kind': 'review_event',
          'id': 'event-record',
          'idempotencyKey': 'event1',
          'cardId': 'remote-card',
          'cardRevision': 1,
          'rating': 3,
          'occurredAt': '2026-01-01T00:00:00Z',
          'algorithm': 'sm2-1'
        },
        {
          'kind': 'review_state',
          'id': 'state1',
          'cardId': 'remote-card',
          'dueAt': '2026-01-02T00:00:00Z',
          'repetitions': 1
        },
      ]
    };
    final s = AppStore(await SharedPreferences.getInstance(),
        {'apiUrl': 'https://example.test'},
        client:
            MockClient((_) async => http.Response(jsonEncode(snapshot), 200)));
    final sync = RemoteSync(s, secure: Vault());
    await sync
        .saveSession({'accessToken': 'a', 'refreshToken': 'b', 'userId': 'u'});
    await sync.pull();
    await sync.pull();
    expect(s.cards.single.id, 'local-card');
    expect(s.cards.single.deck, 'Recuperado');
    expect(s.list('reviews').length, 1);
    expect(s.state('local-card')['repetitions'], 1);
    expect(s.list('syncConflicts'), isEmpty);
    s.dispose();
  });
  test('pending local review prevents remote state overwrite', () async {
    final snapshot = {
      'userId': 'u',
      'records': [
        {
          'kind': 'card',
          'id': 'remote',
          'clientId': 'local',
          'front': 'Q',
          'back': 'A',
          'revision': 1
        },
        {
          'kind': 'review_state',
          'id': 'state',
          'cardId': 'remote',
          'repetitions': 9
        },
      ]
    };
    final s = AppStore(await SharedPreferences.getInstance(),
        {'apiUrl': 'https://example.test'},
        client:
            MockClient((_) async => http.Response(jsonEncode(snapshot), 200)));
    await s.addCard(StudyCard(id: 'local', deck: 'D', front: 'Q', back: 'A'));
    await s.review(s.cards.single, 1);
    final before = s.state('local');
    final sync = RemoteSync(s, secure: Vault());
    await sync
        .saveSession({'accessToken': 'a', 'refreshToken': 'b', 'userId': 'u'});
    await sync.pull();
    expect(s.state('local'), before);
    expect(s.list('syncConflicts').single['kind'], 'pending_reviews');
    s.dispose();
  });
  test('offline edits upload every content revision before their review events',
      () async {
    final seen = <String>[];
    final store = AppStore(await SharedPreferences.getInstance(),
        {'apiUrl': 'https://example.test'}, client: MockClient((r) async {
      if (r.url.path == '/v1/cards/lookup') {
        return http.Response('{"items":[]}', 200);
      }
      if (r.url.path == '/v1/auth/session') {
        return http.Response('{"userId":"u"}', 200);
      }
      final body = jsonDecode(r.body) as Map;
      if (r.url.path == '/v1/decks') return http.Response('{"id":"deck"}', 201);
      if (r.url.path == '/v1/cards') {
        seen.add(body['back']);
        return http.Response('{"id":"remote-card","revision":1}', 201);
      }
      if (r.url.path == '/v1/cards/remote-card') {
        expect(r.headers['If-Match'], '1');
        seen.add(body['back']);
        return http.Response('{"id":"remote-card","revision":2}', 200);
      }
      if (r.url.path == '/v1/reviews') {
        expect(body['cardRevision'], 1);
        expect(body['latencyMs'], 200);
        return http.Response('{}', 201);
      }
      throw StateError('Unexpected request: ${r.url.path}');
    }));
    final sync = RemoteSync(store, secure: Vault());
    await sync
        .saveSession({'accessToken': 'a', 'refreshToken': 'b', 'userId': 'u'});
    await store.addCard(
        StudyCard(id: 'local-card', deck: 'D', front: 'Q', back: 'Original'));
    await store.review(store.cards.single, 3, latencyMs: 200);
    await store.editCard(
        StudyCard(
            id: 'local-card',
            deck: 'D',
            front: 'Q',
            back: 'Corrected',
            revision: 2),
        expectedRevision: 1);
    await sync.upload();
    await sync.upload();
    expect(seen, ['Original', 'Corrected']);
    expect(store.list('reviews').single['synced'], isTrue);
    expect(store.data['remoteCardRevisions']['local-card'], 2);
    store.dispose();
  });
  test('pull preserves local-only edits while server still has known revision',
      () async {
    final snapshot = {
      'userId': 'u',
      'records': [
        {'kind': 'deck', 'id': 'deck', 'title': 'D'},
        {
          'kind': 'card',
          'id': 'remote',
          'clientId': 'local',
          'deckId': 'deck',
          'front': 'Q',
          'back': 'Original',
          'revision': 1
        },
      ]
    };
    final store = AppStore(await SharedPreferences.getInstance(),
        {'apiUrl': 'https://example.test'},
        client:
            MockClient((_) async => http.Response(jsonEncode(snapshot), 200)));
    final sync = RemoteSync(store, secure: Vault());
    await sync
        .saveSession({'accessToken': 'a', 'refreshToken': 'b', 'userId': 'u'});
    await sync.pull();
    await store.editCard(
        StudyCard(
            id: 'local',
            deck: 'D',
            front: 'Q',
            back: 'Local edit',
            revision: 2),
        expectedRevision: 1);
    await sync.pull();
    expect(store.cards.single.back, 'Local edit');
    expect(store.cards.single.revision, 2);
    expect(store.list('syncConflicts'), isEmpty);
    store.dispose();
  });
  test('restoring data cannot reuse credentials left in the device vault',
      () async {
    var requests = 0;
    final store = AppStore(await SharedPreferences.getInstance(),
        {'apiUrl': 'https://example.test'}, client: MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    }));
    final vault = Vault();
    final sync = RemoteSync(store, secure: vault);
    await sync
        .saveSession({'accessToken': 'a', 'refreshToken': 'r', 'userId': 'u'});
    final copy = store.export();
    await store.restore(copy);
    await expectLater(sync.exportRemote(), throwsStateError);
    expect(requests, 0);
    expect(store.data['localDataOwnerId'], 'u');
    store.dispose();
  });
  test(
      'logout preserves ownership and blocks silent transfer to another account',
      () async {
    var requests = 0;
    final store = AppStore(await SharedPreferences.getInstance(),
        {'apiUrl': 'https://example.test'}, client: MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    }));
    final vault = Vault();
    final sync = RemoteSync(store, secure: vault);
    await sync.saveSession(
        {'accessToken': 'a', 'refreshToken': 'r', 'userId': 'alice'});
    await sync.disconnect();
    expect(requests, 1);
    await expectLater(sync.activate(), throwsStateError);
    await expectLater(
        sync.recover('private-recovery-code-xxxxxxxx'), throwsStateError);
    await expectLater(
        sync.saveSession(
            {'accessToken': 'b', 'refreshToken': 's', 'userId': 'bob'}),
        throwsStateError);
    expect(requests, 1);
    expect(store.data['localDataOwnerId'], 'alice');
    expect(vault.values, isEmpty);
    store.dispose();
  });
  test(
      'refresh cannot silently replace identity and import a different account',
      () async {
    final store = AppStore(await SharedPreferences.getInstance(),
        {'apiUrl': 'https://example.test'},
        client: MockClient((r) async => r.url.path.endsWith('refresh')
            ? http.Response(
                jsonEncode(
                    {'userId': 'bob', 'accessToken': 'b', 'refreshToken': 's'}),
                200)
            : http.Response('{}', 401)));
    final vault = Vault();
    final sync = RemoteSync(store, secure: vault);
    await sync.saveSession(
        {'accessToken': 'a', 'refreshToken': 'r', 'userId': 'alice'});
    await expectLater(sync.exportRemote(), throwsStateError);
    expect(store.data['remoteUserId'], 'alice');
    expect(
        jsonDecode(
            vault.values['lexmemoria:https://example.test:session']!)['userId'],
        'alice');
    store.dispose();
  });
  test(
      'private requests refuse redirects and do not forward bearer credentials',
      () async {
    var requests = 0;
    final store = AppStore(await SharedPreferences.getInstance(),
        {'apiUrl': 'https://example.test'}, client: MockClient((r) async {
      requests++;
      expect(r.followRedirects, isFalse);
      return http.Response('{}', 307,
          headers: {'location': 'https://other.test/upload'});
    }));
    final sync = RemoteSync(store, secure: Vault());
    await sync.saveSession(
        {'accessToken': 'a', 'refreshToken': 'r', 'userId': 'alice'});
    await expectLater(sync.exportRemote(), throwsStateError);
    expect(requests, 1);
    store.dispose();
  });
  test('response from another account cannot alter local cards', () async {
    final store = AppStore(await SharedPreferences.getInstance(),
        {'apiUrl': 'https://example.test'},
        client: MockClient(
            (_) async => http.Response('{"userId":"bob","records":[]}', 200)));
    final sync = RemoteSync(store, secure: Vault());
    await sync.saveSession(
        {'accessToken': 'a', 'refreshToken': 'r', 'userId': 'alice'});
    await store.addCard(
        StudyCard(id: 'local', deck: 'D', front: 'Private', back: 'A'));
    await expectLater(sync.pull(), throwsStateError);
    expect(store.cards.single.front, 'Private');
    store.dispose();
  });
  test('legacy tokens migrate only after authenticated account proof',
      () async {
    var requests = 0;
    final store = AppStore(await SharedPreferences.getInstance(), {
      'apiUrl': 'https://example.test',
      'remoteUserId': 'alice'
    }, client: MockClient((r) async {
      requests++;
      if (r.url.path.endsWith('/session')) {
        return http.Response('{"userId":"alice"}', 200);
      }
      return http.Response('{"userId":"alice","records":[]}', 200);
    }));
    final vault = Vault()
      ..values.addAll({
        'lexmemoria:https://example.test:access': 'a',
        'lexmemoria:https://example.test:refresh': 'r'
      });
    await RemoteSync(store, secure: vault).exportRemote();
    expect(requests, 2);
    expect(store.data['localDataOwnerId'], 'alice');
    expect(vault.values.keys, ['lexmemoria:https://example.test:session']);
    store.dispose();
  });
  test('wrong legacy account proof never binds local data', () async {
    final store = AppStore(await SharedPreferences.getInstance(),
        {'apiUrl': 'https://example.test', 'remoteUserId': 'alice'},
        client:
            MockClient((_) async => http.Response('{"userId":"bob"}', 200)));
    final vault = Vault()
      ..values.addAll({
        'lexmemoria:https://example.test:access': 'a',
        'lexmemoria:https://example.test:refresh': 'r'
      });
    await expectLater(
        RemoteSync(store, secure: vault).exportRemote(), throwsStateError);
    expect(store.data['remoteUserId'], 'alice');
    expect(vault.values.containsKey('lexmemoria:https://example.test:session'),
        isFalse);
    store.dispose();
  });
  test('parallel unauthorized responses rotate refresh token only once',
      () async {
    var refreshCount = 0, originalCount = 0;
    final both = Completer<void>();
    final store = AppStore(await SharedPreferences.getInstance(),
        {'apiUrl': 'https://example.test'}, client: MockClient((r) async {
      if (r.url.path.endsWith('refresh')) {
        refreshCount++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return http.Response(
            '{"userId":"alice","accessToken":"new","refreshToken":"next"}',
            200);
      }
      if (r.headers['Authorization'] == 'Bearer old') {
        originalCount++;
        if (originalCount == 2) both.complete();
        await both.future;
        return http.Response('{}', 401);
      }
      return http.Response('{"userId":"alice","records":[]}', 200);
    }));
    final sync = RemoteSync(store, secure: Vault());
    await sync.saveSession(
        {'userId': 'alice', 'accessToken': 'old', 'refreshToken': 'original'});
    final copies =
        await Future.wait([sync.exportRemote(), sync.exportRemote()]);
    expect(copies.length, 2);
    expect(refreshCount, 1);
    store.dispose();
  });
  test(
      'recovery exposes replacement code safely when secure storage rejects session',
      () async {
    const replacement = 'replacement-private-code-1234567890';
    final store = AppStore(await SharedPreferences.getInstance(),
        {'apiUrl': 'https://example.test'},
        client: MockClient((_) async => http.Response(
            jsonEncode({
              'userId': 'alice',
              'accessToken': 'a',
              'refreshToken': 'r',
              'recoveryCode': replacement
            }),
            200)));
    final vault = SessionFailingVault();
    try {
      await RemoteSync(store, secure: vault)
          .recover('old-private-code-1234567890');
      fail('Expected secure storage failure');
    } on RecoveryPersistenceFailure catch (error) {
      expect(error.replacementCode, replacement);
      expect(error.toString().contains(replacement), isFalse);
      expect(store.export().contains(replacement), isFalse);
      expect(store.data['remoteUserId'], isNull);
    }
    store.dispose();
  });
  test('in-flight reply is rejected when server changes before it arrives',
      () async {
    final entered = Completer<void>(), release = Completer<void>();
    final store = AppStore(await SharedPreferences.getInstance(),
        {'apiUrl': 'https://example.test/a'}, client: MockClient((_) async {
      entered.complete();
      await release.future;
      return http.Response('{"userId":"alice","records":[]}', 200);
    }));
    final sync = RemoteSync(store, secure: Vault());
    await sync.saveSession(
        {'userId': 'alice', 'accessToken': 'a', 'refreshToken': 'r'});
    final operation = sync.pull();
    final failed = expectLater(operation, throwsStateError);
    await entered.future;
    store.data['apiUrl'] = 'https://example.test/b';
    release.complete();
    await failed;
    expect(store.data['lastProgressSync'], isNull);
    store.dispose();
  });
  test('numbered cloze responses upload intact as an object', () async {
    Json? uploaded;
    final store = AppStore(await SharedPreferences.getInstance(),
        {'apiUrl': 'https://example.test'}, client: MockClient((r) async {
      if (r.url.path == '/v1/cards/lookup') {
        return http.Response('{"items":[]}', 200);
      }
      if (r.url.path == '/v1/auth/session') {
        return http.Response('{"userId":"alice"}', 200);
      }
      if (r.url.path == '/v1/decks') return http.Response('{"id":"d"}', 201);
      if (r.url.path == '/v1/cards') {
        return http.Response('{"id":"remote","revision":1}', 201);
      }
      if (r.url.path == '/v1/reviews') {
        uploaded = Json.from(jsonDecode(r.body));
        return http.Response('{}', 201);
      }
      throw StateError('Unexpected request');
    }));
    final sync = RemoteSync(store, secure: Vault());
    await sync.saveSession(
        {'userId': 'alice', 'accessToken': 'a', 'refreshToken': 'r'});
    await store.addCard(StudyCard(
        id: 'cloze-local',
        deck: 'D',
        type: 'cloze',
        front: '{{c1::Constitución}} y {{c2::tres años}}',
        back: 'Respuestas'));
    await store.review(store.cards.single, 3,
        response: {'1': 'Constitución', '2': 'tres años'});
    await sync.upload();
    expect(uploaded!['response'], {'1': 'Constitución', '2': 'tres años'});
    expect(store.list('reviews').single['synced'], isTrue);
    store.dispose();
  });
  test(
      'expired legacy access refreshes and verifies account without deleting local data',
      () async {
    final store = AppStore(await SharedPreferences.getInstance(), {
      'apiUrl': 'https://example.test',
      'remoteUserId': 'alice',
      'notes': {'a': 'private'}
    }, client: MockClient((r) async {
      if (r.url.path.endsWith('/session')) return http.Response('{}', 401);
      if (r.url.path.endsWith('/refresh')) {
        return http.Response(
            '{"userId":"alice","accessToken":"new","refreshToken":"next"}',
            200);
      }
      expect(r.headers['Authorization'], 'Bearer new');
      return http.Response('{"userId":"alice","records":[]}', 200);
    }));
    final vault = Vault()
      ..values.addAll({
        'lexmemoria:https://example.test:access': 'expired',
        'lexmemoria:https://example.test:refresh': 'r'
      });
    await RemoteSync(store, secure: vault).exportRemote();
    expect(store.data['notes']['a'], 'private');
    expect(store.data['localDataOwnerId'], 'alice');
    store.dispose();
  });
}
