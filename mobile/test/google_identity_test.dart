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
  test('stalled Google login times out without accepting a late token',
      () async {
    final token = Completer<String?>();
    var requests = 0;
    final s = await store(MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    }));
    final operation = connectGoogleIdentity(
        s, Identity(() => token.future), RemoteSync(s, secure: Vault()),
        authenticationTimeout: const Duration(milliseconds: 10));
    await expectLater(operation, throwsA(isA<TimeoutException>()));
    token.complete('late-firebase-token');
    await Future<void>.delayed(Duration.zero);
    expect(requests, 0);
    expect(s.data['remoteUserId'], isNull);
    expect(s.data['notes']['a'], 'private');
    s.dispose();
  });
  testWidgets(
      'account screen stays navigable and releases stalled Google login',
      (tester) async {
    final token = Completer<String?>();
    var requests = 0;
    final s = await store(MockClient((_) async {
      requests++;
      return http.Response('{}', 200);
    }));
    await tester.pumpWidget(MaterialApp(
        home: AccountPage(
            store: s, googleIdentity: Identity(() => token.future))));
    await tester.tap(find.text('Continuar con Google'));
    await tester.pump();
    expect(find.text('Conectando con el servidor…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 8));
    expect(find.textContaining('Puedes seguir estudiando'), findsOneWidget);
    await tester.pump(const Duration(seconds: 83));
    await tester.pump();
    expect(
        tester
            .widget<OutlinedButton>(
                find.widgetWithText(OutlinedButton, 'Continuar con Google'))
            .onPressed,
        isNotNull);
    expect(find.textContaining('Google no ha terminado el acceso'),
        findsOneWidget);
    token.complete('late-token');
    await tester.pump();
    expect(requests, 0);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
  testWidgets(
      'Google stays available after session creation and becomes verification after linking',
      (tester) async {
    final s = await store(MockClient((_) async => http.Response('{}', 200)));
    final identity = Identity(() async => null);
    await tester.pumpWidget(
        MaterialApp(home: AccountPage(store: s, googleIdentity: identity)));
    expect(find.text('Continuar con Google'), findsOneWidget);
    s.data['remoteUserId'] = 'existing-study-account';
    s.data['localDataOwnerId'] = 'existing-study-account';
    s.syncStatusChanged();
    await tester.pump();
    expect(find.text('Vincular Google a mi cuenta'), findsOneWidget);
    expect(
        tester
            .widget<OutlinedButton>(find.widgetWithText(
                OutlinedButton, 'Vincular Google a mi cuenta'))
            .onPressed,
        isNotNull);
    s.data['remoteGoogleLinked'] = true;
    s.syncStatusChanged();
    await tester.pump();
    expect(find.text('Verificar cuenta de Google'), findsOneWidget);
    expect(s.data['remoteUserId'], 'existing-study-account');
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
  test(
      'Apple links to an existing study account without Google flags or data replacement',
      () async {
    final paths = <String>[];
    final s = await store(MockClient((r) async {
      paths.add(r.url.path);
      expect(r.headers['Authorization'], 'Bearer a');
      return http.Response('{"linked":true}', 200);
    }));
    final remote = RemoteSync(s, secure: Vault());
    await remote.saveSession(
        {'userId': 'existing', 'accessToken': 'a', 'refreshToken': 'r'});
    await s.addCard(StudyCard(id: 'c', deck: 'D', front: 'Q', back: 'A'));
    final before = s.cards.single.toJson();
    await connectGoogleIdentity(
        s, Identity(() async => 'apple-firebase-token'), remote,
        provider: 'apple');
    expect(paths, ['/v1/auth/link']);
    expect(s.data['remoteUserId'], 'existing');
    expect(s.data['remoteAppleLinked'], isTrue);
    expect(s.data['remoteGoogleLinked'], isNull);
    expect(s.cards.single.toJson(), before);
    expect(s.export().contains('apple-firebase-token'), isFalse);
    s.dispose();
  });
  test('Apple cancellation and link conflict preserve the current account',
      () async {
    var calls = 0;
    final s = await store(MockClient((_) async {
      calls++;
      return http.Response('{}', 409);
    }));
    final remote = RemoteSync(s, secure: Vault());
    await remote.saveSession(
        {'userId': 'existing', 'accessToken': 'a', 'refreshToken': 'r'});
    expect(
        await connectGoogleIdentity(s, Identity(() async => null), remote,
            provider: 'apple'),
        isFalse);
    expect(calls, 0);
    await expectLater(
        connectGoogleIdentity(s, Identity(() async => 'apple-token'), remote,
            provider: 'apple'),
        throwsStateError);
    expect(calls, 1);
    expect(s.data['remoteUserId'], 'existing');
    expect(s.data['remoteAppleLinked'], isNull);
    s.dispose();
  });
  testWidgets(
      'Apple remains offered alongside Google after signing into the study account',
      (tester) async {
    final s = await store(MockClient((_) async => http.Response('{}', 200)));
    s.data['remoteUserId'] = 'existing';
    await tester.pumpWidget(MaterialApp(
        home: AccountPage(
            store: s,
            googleIdentity: Identity(() async => null),
            appleIdentity: Identity(() async => null))));
    expect(find.text('Vincular Google a mi cuenta'), findsOneWidget);
    expect(find.text('Continuar con Apple'), findsOneWidget);
    await tester.tap(find.text('Continuar con Apple'));
    await tester.pumpAndSettle();
    expect(s.data['remoteUserId'], 'existing');
    expect(find.text('Continuar con Apple'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
}
