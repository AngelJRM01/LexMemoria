import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/google_identity.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/profile.dart';
import 'package:lexmemoria/remote.dart';
import 'package:lexmemoria/store.dart';

class Identity implements GoogleIdentity {
  final Future<String?> Function() result;
  Identity(this.result);
  @override
  bool get available => true;
  @override
  Future<String?> authenticate() => result();
}

class Vault implements CredentialVault {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

Future<AppStore> store(MockClient client) async => AppStore(
    await SharedPreferences.getInstance(),
    {
      'apiUrl': 'https://api.test',
      'notes': {'a': 'private'},
      'profile': {'dailyGoal': 20}
    },
    client: client);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'cancelled Google selection never contacts backend or changes local data',
      () async {
    var requests = 0;
    final s = await store(MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    }));
    final before = jsonEncode(s.data);
    expect(
        await connectGoogleIdentity(
            s, Identity(() async => null), RemoteSync(s, secure: Vault())),
        isFalse);
    expect(requests, 0);
    expect(jsonEncode(s.data), before);
    s.dispose();
  });
  test(
      'Firebase token is exchanged for a secure backend session without uploading study content',
      () async {
    final paths = <String>[];
    final s = await store(MockClient((r) async {
      paths.add(r.url.path);
      expect(jsonDecode(r.body), {'idToken': 'firebase-only-token'});
      expect(r.headers['Authorization'], isNull);
      return http.Response(
          '{"userId":"google-user","accessToken":"backend-access","refreshToken":"backend-refresh"}',
          200);
    }));
    await s.addCard(StudyCard(id: 'c', deck: 'D', front: 'Q', back: 'A'));
    await s.review(s.cards.single, 3);
    final vault = Vault();
    expect(
        await connectGoogleIdentity(
            s,
            Identity(() async => 'firebase-only-token'),
            RemoteSync(s, secure: vault)),
        isTrue);
    expect(paths, ['/v1/auth/oidc']);
    expect(s.cards.single.id, 'c');
    expect(s.list('reviews').length, 1);
    expect(s.data['notes']['a'], 'private');
    expect(s.data['remoteGoogleLinked'], isTrue);
    for (final secret in [
      'firebase-only-token',
      'backend-access',
      'backend-refresh'
    ]) {
      expect(s.export().contains(secret), isFalse);
    }
    expect(vault.values.length, 1);
    s.dispose();
  });
  test(
      'existing guest links Google and retains account, aliases and review state',
      () async {
    final requests = <String>[];
    final s = await store(MockClient((r) async {
      requests.add(r.url.path);
      expect(r.headers['Authorization'], 'Bearer access');
      return http.Response('{"linked":true}', 200);
    }));
    final remote = RemoteSync(s, secure: Vault());
    await remote.saveSession({
      'userId': 'guest',
      'accessToken': 'access',
      'refreshToken': 'refresh'
    });
    await s.addCard(StudyCard(id: 'c', deck: 'D', front: 'Q', back: 'A'));
    await s.review(s.cards.single, 3);
    s.data['remoteCardIds'] = {'c': 'remote-c'};
    final before = s.state('c');
    await connectGoogleIdentity(
        s, Identity(() async => 'firebase-only-token'), remote);
    expect(requests, ['/v1/auth/link']);
    expect(s.data['remoteUserId'], 'guest');
    expect(s.data['remoteCardIds'], {'c': 'remote-c'});
    expect(s.state('c'), before);
    s.dispose();
  });
  test('link conflict never falls back to login or switches study accounts',
      () async {
    final paths = <String>[];
    final s = await store(MockClient((r) async {
      paths.add(r.url.path);
      return http.Response('{}', 409);
    }));
    final remote = RemoteSync(s, secure: Vault());
    await remote.saveSession(
        {'userId': 'guest', 'accessToken': 'a', 'refreshToken': 'r'});
    await expectLater(
        connectGoogleIdentity(
            s, Identity(() async => 'firebase-only-token'), remote),
        throwsStateError);
    expect(paths, ['/v1/auth/link']);
    expect(s.data['remoteUserId'], 'guest');
    expect(s.data['remoteGoogleLinked'], isNull);
    expect(s.data['notes']['a'], 'private');
    s.dispose();
  });
  test(
      'changing server during Google selection cancels before any token is sent',
      () async {
    final selected = Completer<String?>();
    var requests = 0;
    final s = await store(MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    }));
    final operation = connectGoogleIdentity(
        s, Identity(() => selected.future), RemoteSync(s, secure: Vault()));
    final failure = expectLater(operation, throwsStateError);
    s.data['apiUrl'] = 'https://different.test';
    selected.complete('firebase-only-token');
    await failure;
    expect(requests, 0);
    expect(s.data['remoteUserId'], isNull);
    s.dispose();
  });
  test(
      'changing account during login HTTP reply cannot overwrite the new account',
      () async {
    final entered = Completer<void>(), release = Completer<void>();
    final s = await store(MockClient((_) async {
      entered.complete();
      await release.future;
      return http.Response(
          '{"userId":"old-target","accessToken":"a","refreshToken":"r"}', 200);
    }));
    final operation = connectGoogleIdentity(
        s,
        Identity(() async => 'firebase-only-token'),
        RemoteSync(s, secure: Vault()),
        confirmAccountChange: true);
    final failure = expectLater(operation, throwsStateError);
    await entered.future;
    s.data['remoteUserId'] = 'new-account';
    s.data['localDataOwnerId'] = 'new-account';
    release.complete();
    await failure;
    expect(s.data['remoteUserId'], 'new-account');
    expect(s.data['notes']['a'], 'private');
    s.dispose();
  });
  testWidgets('Google button appears only with a configured API and provider',
      (tester) async {
    final s = AppStore(await SharedPreferences.getInstance(), {});
    final identity = Identity(() async => null);
    await tester.pumpWidget(
        MaterialApp(home: AccountPage(store: s, googleIdentity: identity)));
    expect(find.text('Continuar con Google'), findsNothing);
    s.data['apiUrl'] = 'https://api.test';
    await tester.pumpWidget(MaterialApp(
        home: AccountPage(
            key: const ValueKey('configured'),
            store: s,
            googleIdentity: identity)));
    expect(find.text('Continuar con Google'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
}
