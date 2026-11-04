import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('catalogue pages preserve downloaded rows and send cursor', () async {
    var page = 0;
    final prefs = await SharedPreferences.getInstance();
    final s = AppStore(prefs, {'apiUrl': 'https://example.test', 'norms': [{'id': 'saved', 'latestVersion': 'v', 'units': []}]}, client: MockClient((r) async {
      page++;
      if (page == 1) return http.Response(jsonEncode({'items': [{'id': 'a'}], 'nextCursor': 'a'}), 200);
      expect(r.url.queryParameters['cursor'], 'a');
      return http.Response(jsonEncode({'items': [{'id': 'b'}], 'nextCursor': null}), 200);
    }));
    await s.fetchCatalogue(); await s.fetchCatalogue(nextPage: true);
    expect(s.list('norms').map((n) => n['id']).toSet(), {'saved', 'a', 'b'});
    expect(s.data['catalogueCursor'], isNull);
    expect(s.list('norms').firstWhere((n) => n['id'] == 'saved')['units'], isNotNull);
    s.dispose();
  });
  test('failed catalogue request preserves cache and clears loading', () async {
    final s = AppStore(await SharedPreferences.getInstance(), {'apiUrl': 'https://example.test', 'norms': [{'id': 'saved'}]}, client: MockClient((_) async => http.Response('', 503)));
    await expectLater(s.fetchCatalogue(), throwsStateError);
    expect(s.list('norms').single['id'], 'saved');
    expect(s.syncing, isFalse);
    s.dispose();
  });
  test('legal feed deduplicates id and keeps editorial uncertainty', () async {
    final s = AppStore(await SharedPreferences.getInstance(), {'apiUrl': 'https://example.test'}, client: MockClient((_) async => http.Response(jsonEncode({'items': [{'id': 'e1', 'editorialState': 'pending', 'effectiveFrom': null}], 'nextCursor': null}), 200)));
    await s.fetchUpdates(); await s.fetchUpdates();
    expect(s.list('legalUpdates').length, 1);
    expect(s.list('legalUpdates').single['effectiveFrom'], isNull);
    s.dispose();
  });
  test('API URLs reject credentials and nonlocal cleartext', () async {
    final s = AppStore(await SharedPreferences.getInstance(), {});
    for (final url in ['http://example.test', 'https://user:secret@example.test', 'https://example.test?token=x', 'ftp://localhost']) {
      s.data['apiUrl'] = url;
      expect(() => s.apiBase, throwsStateError);
    }
    s.data['apiUrl'] = 'http://127.0.0.1:8000';
    expect(s.apiBase, 'http://127.0.0.1:8000');
    s.dispose();
  });
}
