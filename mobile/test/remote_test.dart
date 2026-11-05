import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/remote.dart';

class Vault implements CredentialVault {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async { values[key] = value; }
  @override
  Future<void> delete(String key) async { values.remove(key); }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('expired token refreshes without exporting credentials', () async {
    var requests = 0;
    final s = AppStore(await SharedPreferences.getInstance(), {'apiUrl': 'https://example.test'}, client: MockClient((r) async {
      if (r.url.path.endsWith('refresh')) return http.Response(jsonEncode({'accessToken': 'new-access', 'refreshToken': 'new-refresh', 'userId': 'u'}), 200);
      requests++;
      if (requests == 1) return http.Response('{}', 401);
      expect(r.headers['Authorization'], 'Bearer new-access');
      return http.Response('{"records":[],"userId":"u"}', 200);
    }));
    final vault = Vault();
    final sync = RemoteSync(s, secure: vault);
    await sync.saveSession({'accessToken': 'old-access', 'refreshToken': 'old-refresh', 'userId': 'u'});
    expect((await sync.exportRemote())['userId'], 'u');
    expect(requests, 2);
    expect(s.export().contains('new-access'), isFalse);
    expect(s.export().contains('new-refresh'), isFalse);
    s.dispose();
  });
  test('credentials are scoped by API path, not hostname only', () async {
    var called = false;
    final s = AppStore(await SharedPreferences.getInstance(), {'apiUrl': 'https://example.test/a'}, client: MockClient((_) async { called = true; return http.Response('{}', 200); }));
    final vault = Vault();
    final first = RemoteSync(s, secure: vault);
    await first.saveSession({'accessToken': 'a', 'refreshToken': 'b', 'userId': 'u'});
    s.data['apiUrl'] = 'https://example.test/b';
    await expectLater(RemoteSync(s, secure: vault).exportRemote(), throwsStateError);
    expect(called, isFalse);
    s.dispose();
  });
  test('pull restores cards, history and state without duplicate events', () async {
    final snapshot = {'userId': 'u', 'records': [
      {'kind': 'deck', 'id': 'd1', 'title': 'Recuperado'},
      {'kind': 'card', 'id': 'remote-card', 'clientId': 'local-card', 'deckId': 'd1', 'front': 'Q', 'back': 'A', 'revision': 1},
      {'kind': 'review_event', 'id': 'event-record', 'idempotencyKey': 'event1', 'cardId': 'remote-card', 'cardRevision': 1, 'rating': 3, 'occurredAt': '2026-01-01T00:00:00Z', 'algorithm': 'sm2-1'},
      {'kind': 'review_state', 'id': 'state1', 'cardId': 'remote-card', 'dueAt': '2026-01-02T00:00:00Z', 'repetitions': 1},
    ]};
    final s = AppStore(await SharedPreferences.getInstance(), {'apiUrl': 'https://example.test'}, client: MockClient((_) async => http.Response(jsonEncode(snapshot), 200)));
    final sync = RemoteSync(s, secure: Vault());
    await sync.saveSession({'accessToken': 'a', 'refreshToken': 'b', 'userId': 'u'});
    await sync.pull(); await sync.pull();
    expect(s.cards.single.id, 'local-card');
    expect(s.cards.single.deck, 'Recuperado');
    expect(s.list('reviews').length, 1);
    expect(s.state('local-card')['repetitions'], 1);
    expect(s.list('syncConflicts'), isEmpty);
    s.dispose();
  });
  test('pending local review prevents remote state overwrite', () async {
    final snapshot = {'userId': 'u', 'records': [
      {'kind': 'card', 'id': 'remote', 'clientId': 'local', 'front': 'Q', 'back': 'A', 'revision': 1},
      {'kind': 'review_state', 'id': 'state', 'cardId': 'remote', 'repetitions': 9},
    ]};
    final s = AppStore(await SharedPreferences.getInstance(), {'apiUrl': 'https://example.test'}, client: MockClient((_) async => http.Response(jsonEncode(snapshot), 200)));
    await s.addCard(StudyCard(id: 'local', deck: 'D', front: 'Q', back: 'A'));
    await s.review(s.cards.single, 1);
    final before = s.state('local');
    final sync = RemoteSync(s, secure: Vault());
    await sync.saveSession({'accessToken': 'a', 'refreshToken': 'b', 'userId': 'u'});
    await sync.pull();
    expect(s.state('local'), before);
    expect(s.list('syncConflicts').single['kind'], 'pending_reviews');
    s.dispose();
  });
  test('offline edits upload every content revision before their review events', () async {
    final seen = <String>[];
    final store = AppStore(await SharedPreferences.getInstance(), {'apiUrl': 'https://example.test'}, client: MockClient((r) async {
      final body = jsonDecode(r.body) as Map;
      if (r.url.path == '/v1/decks') return http.Response('{"id":"deck"}', 201);
      if (r.url.path == '/v1/cards') {
        seen.add(body['back']); return http.Response('{"id":"remote-card","revision":1}', 201);
      }
      if (r.url.path == '/v1/cards/remote-card') {
        expect(r.headers['If-Match'], '1'); seen.add(body['back']);
        return http.Response('{"id":"remote-card","revision":2}', 200);
      }
      if (r.url.path == '/v1/reviews') {
        expect(body['cardRevision'], 1); expect(body['latencyMs'], 200); return http.Response('{}', 201);
      }
      throw StateError('Unexpected request: ${r.url.path}');
    }));
    final sync = RemoteSync(store, secure: Vault());
    await sync.saveSession({'accessToken': 'a', 'refreshToken': 'b', 'userId': 'u'});
    await store.addCard(StudyCard(id: 'local-card', deck: 'D', front: 'Q', back: 'Original'));
    await store.review(store.cards.single, 3, latencyMs: 200);
    await store.editCard(StudyCard(id: 'local-card', deck: 'D', front: 'Q', back: 'Corrected', revision: 2), expectedRevision: 1);
    await sync.upload(); await sync.upload();
    expect(seen, ['Original', 'Corrected']);
    expect(store.list('reviews').single['synced'], isTrue);
    expect(store.data['remoteCardRevisions']['local-card'], 2);
    store.dispose();
  });
  test('pull preserves local-only edits while server still has known revision', () async {
    final snapshot = {'userId': 'u', 'records': [
      {'kind': 'deck', 'id': 'deck', 'title': 'D'},
      {'kind': 'card', 'id': 'remote', 'clientId': 'local', 'deckId': 'deck', 'front': 'Q', 'back': 'Original', 'revision': 1},
    ]};
    final store = AppStore(await SharedPreferences.getInstance(), {'apiUrl': 'https://example.test'}, client: MockClient((_) async => http.Response(jsonEncode(snapshot), 200)));
    final sync = RemoteSync(store, secure: Vault());
    await sync.saveSession({'accessToken': 'a', 'refreshToken': 'b', 'userId': 'u'});
    await sync.pull();
    await store.editCard(StudyCard(id: 'local', deck: 'D', front: 'Q', back: 'Local edit', revision: 2), expectedRevision: 1);
    await sync.pull();
    expect(store.cards.single.back, 'Local edit');
    expect(store.cards.single.revision, 2);
    expect(store.list('syncConflicts'), isEmpty);
    store.dispose();
  });

}
