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
}
