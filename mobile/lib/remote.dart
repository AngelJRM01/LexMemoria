import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'store.dart';

StudyCard remoteStudyCard(Json record, String id, String deck,
    {int? revision}) {
  final citation = (record['citations'] as List? ?? []).firstOrNull as Map?;
  return StudyCard(
      id: id,
      deck: deck,
      front: record['front'],
      back: record['back'],
      explanation: record['explanation'] ?? '',
      type: record['type'] ?? 'qa',
      normId: citation?['normId'] ?? '',
      unitId: citation?['unitId'] ?? '',
      versionId: citation?['versionId'] ?? '',
      unitVersionHash: citation?['unitVersionHash'] ?? '',
      revision: revision ?? record['revision'] ?? 1,
      blocked: record['blocked'] ?? false,
      editorialState: record['editorialState'] ?? 'user',
      options: List<String>.from(record['options'] ?? []),
      correct: record['correct']);
}

dynamic _progressSection(String key, Json data) {
  if (key == 'cards') {
    return (data['cards'] as List? ?? [])
        .map((c) => StudyCard.fromJson(Json.from(c)).toJson())
        .toList();
  }
  if (key == 'history') return data['cardHistory'] ?? [];
  return (data['reviews'] as List? ?? [])
      .map((r) => Json.from(r))
      .map((r) => {
            for (final e in r.entries)
              if (!['synced', 'syncedUserId'].contains(e.key)) e.key: e.value
          })
      .toList();
}

String progressFingerprintOf(Json data) => sha256
    .convert(utf8.encode(jsonEncode({
      for (final key in ['cards', 'history', 'reviews'])
        key: _progressSection(key, data)
    })))
    .toString();

/// Optional remote identity. Tokens never enter preferences, exports or logs.
abstract interface class CredentialVault {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class NativeCredentialVault implements CredentialVault {
  final FlutterSecureStorage storage;
  const NativeCredentialVault({this.storage = const FlutterSecureStorage()});
  @override
  Future<String?> read(String key) => storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

class RecoveryPersistenceFailure implements Exception {
  final String replacementCode;
  RecoveryPersistenceFailure(this.replacementCode);
  @override
  String toString() =>
      'No se pudo guardar la sesión recuperada. Conserva el código nuevo.';
}

class _FingerprintCache {
  final int generation;
  final Object? cards, history, reviews;
  final String value;
  _FingerprintCache(AppStore store, this.value)
      : generation = store.progressGeneration,
        cards = store.data['cards'],
        history = store.data['cardHistory'],
        reviews = store.data['reviews'];
  bool matches(AppStore store) =>
      generation == store.progressGeneration &&
      identical(cards, store.data['cards']) &&
      identical(history, store.data['cardHistory']) &&
      identical(reviews, store.data['reviews']);
}

final _fingerprintCache = Expando<_FingerprintCache>();

class _DigestResult implements Sink<Digest> {
  Digest? value;
  @override
  void add(Digest digest) {
    value = digest;
  }

  @override
  void close() {}
}

class _EncodedProgressPart {
  final Object? source;
  final int legacyGeneration;
  final List<int> bytes;
  _EncodedProgressPart(this.source, this.legacyGeneration, this.bytes);
}

final _encodedProgressParts = Expando<Map<String, _EncodedProgressPart>>();
String _cachedProgressFingerprint(AppStore store) {
  final parts = _encodedProgressParts[store] ??= {};
  final output = _DigestResult();
  final digest = sha256.startChunkedConversion(output);
  digest.add(utf8.encode('{'));
  for (final key in ['cards', 'history', 'reviews']) {
    final source = store.data[key == 'history' ? 'cardHistory' : key];
    var cached = parts[key];
    if (cached == null ||
        !identical(cached.source, source) ||
        cached.legacyGeneration != store.legacyDataGeneration) {
      cached = _EncodedProgressPart(source, store.legacyDataGeneration,
          utf8.encode(jsonEncode(_progressSection(key, store.data))));
      parts[key] = cached;
    }
    digest.add(utf8.encode('${key == 'cards' ? '' : ','}"$key":'));
    digest.add(cached.bytes);
  }
  digest.add(utf8.encode('}'));
  digest.close();
  return output.value!.toString();
}

class RemoteSyncFailure extends StateError {
  final int status;
  RemoteSyncFailure(this.status, String message) : super(message);
}

final _refreshes = Expando<Map<String, Future<Json>>>();
final _uploads = Expando<Future<void>>();
final _pulls = Expando<Future<void>>();

class RemoteSync {
  final AppStore store;
  final CredentialVault secure;
  RemoteSync(this.store, {this.secure = const NativeCredentialVault()});
  String get base {
    final value = store.apiBase;
    if (Uri.parse(value).scheme != 'https') {
      throw StateError('La sincronización privada requiere HTTPS.');
    }
    return value;
  }

  String get prefix => 'lexmemoria:$base';

  String get progressFingerprint {
    final cached = _fingerprintCache[store];
    if (cached != null && cached.matches(store)) return cached.value;
    final value = _cachedProgressFingerprint(store);
    _fingerprintCache[store] = _FingerprintCache(store, value);
    return value;
  }

  String get progressStatus {
    if (_uploads[store] != null || _pulls[store] != null) {
      return 'Sincronizando';
    }
    if (store.list('syncConflicts').isNotEmpty) return 'Conflicto';
    final queue = store.data['syncOutbox'];
    if (queue is Map &&
        queue['userId'] == store.data['remoteUserId'] &&
        queue['server'] == store.apiBase) {
      if (queue['state'] == 'conflict') return 'Conflicto';
      if (queue['state'] == 'error') {
        return queue['connection'] == true
            ? 'Error de conexión'
            : 'Error al sincronizar';
      }
    }
    if (store.data['lastProgressSync'] == null) return 'Sin sincronizar';
    return store.data['progressSyncHash'] == progressFingerprint
        ? 'Sincronizado'
        : 'Cambios pendientes';
  }

  bool get needsAccountConfirmation =>
      store.data['localDataOwnerId'] != null ||
      store.data['remoteUserId'] != null;

  void _confirmAccountOperation(bool confirmed) {
    if (needsAccountConfirmation && !confirmed) {
      throw StateError(
          'Confirma el cambio de cuenta antes de conectar estos datos.');
    }
  }

  Future<Json> _boundSession(String server) async {
    final encoded = await secure.read('lexmemoria:$server:session');
    if (encoded == null) return _upgradeLegacySession(server);
    final session = Json.from(jsonDecode(encoded));
    if (store.data['remoteUserId'] != session['userId'] ||
        store.data['remoteServer'] != server ||
        base != server ||
        store.data['localDataOwnerId'] != session['userId'] ||
        store.data['localDataServer'] != server) {
      throw StateError(
          'La sesión no corresponde a estos datos o servidor. Recupera tu cuenta.');
    }
    return session;
  }

  Future<Json> _upgradeLegacySession(String server) async {
    final expected = store.data['remoteUserId'];
    final oldPrefix = 'lexmemoria:$server';
    final access = await secure.read('$oldPrefix:access');
    final refresh = await secure.read('$oldPrefix:refresh');
    if (expected is! String ||
        access == null ||
        refresh == null ||
        base != server) {
      throw StateError(
          'Recupera tu cuenta para verificar la sesión. Tus datos se conservan.');
    }
    final proof = http.Request('GET', Uri.parse('$server/v1/auth/session'))
      ..followRedirects = false
      ..headers['Authorization'] = 'Bearer $access';
    final response = await (() async =>
            http.Response.fromStream(await store.client.send(proof)))()
        .timeout(const Duration(seconds: 30));
    if (base != server || store.data['remoteUserId'] != expected) {
      throw StateError('La cuenta o servidor ha cambiado. Reintenta.');
    }
    Json verified;
    if (response.statusCode == 401) {
      verified = await send('/v1/auth/refresh',
          body: {'refreshToken': refresh}, auth: false, retry: false);
    } else if (response.statusCode == 200) {
      verified = {
        ...Json.from(jsonDecode(response.body)),
        'accessToken': access,
        'refreshToken': refresh
      };
    } else {
      throw StateError(
          'No se pudo verificar la sesión anterior. Actualiza el servidor o recupera tu cuenta.');
    }
    if (verified['userId'] != expected ||
        store.data['remoteUserId'] != expected) {
      throw StateError(
          'La sesión anterior pertenece a otra cuenta. No se ha vinculado.');
    }
    await saveSession(verified);
    return _boundSession(server);
  }

  Future<Json> _refreshSession(Json previous, String server) async {
    final pending = _refreshes[store] ??= {};
    final key = '$server:${previous['userId']}';
    final existing = pending[key];
    if (existing != null) return existing;
    final operation = () async {
      final current = await _boundSession(server);
      if (current['accessToken'] != previous['accessToken']) return current;
      final refreshed = await send('/v1/auth/refresh',
          body: {'refreshToken': current['refreshToken']},
          auth: false,
          retry: false);
      await saveSession(refreshed);
      return refreshed;
    }();
    pending[key] = operation;
    try {
      return await operation;
    } finally {
      if (identical(pending[key], operation)) pending.remove(key);
    }
  }

  Future<Json> send(String path,
          {Json? body, bool auth = true, bool retry = true}) =>
      request('POST', path, body: body, auth: auth, retry: retry);
  Future<Json> request(String method, String path,
      {Json? body,
      bool auth = true,
      bool retry = true,
      int rateRetries = 2,
      Json extraHeaders = const {}}) async {
    final server = base;
    final session = auth ? await _boundSession(server) : null;
    if (base != server) throw StateError('El servidor ha cambiado. Reintenta.');
    final token = session?['accessToken'] as String?;
    if (auth && token == null) {
      throw StateError('Activa o recupera tu identidad de sincronización.');
    }
    final uri = Uri.parse('$server$path');
    final headers = <String, String>{
      ...extraHeaders.map((k, v) => MapEntry(k, v.toString())),
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token'
    };
    final outgoing = http.Request(method, uri)
      ..followRedirects = false
      ..headers.addAll(headers);
    if (method != 'GET' && method != 'DELETE') {
      outgoing.body = jsonEncode(body ?? {});
    }
    final response = await (() async =>
            http.Response.fromStream(await store.client.send(outgoing)))()
        .timeout(Duration(seconds: path.startsWith('/v1/auth/') ? 90 : 30));
    if (base != server ||
        (auth &&
            (store.data['remoteUserId'] != session!['userId'] ||
                store.data['remoteServer'] != server))) {
      throw StateError(
          'La cuenta o el servidor ha cambiado durante la operación.');
    }
    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw StateError(
          'El servidor intenta redirigir una operación privada. No se han reenviado credenciales.');
    }
    if (response.statusCode == 401 && auth && retry) {
      await _refreshSession(session!, server);
      return request(method, path,
          body: body, retry: false, extraHeaders: extraHeaders);
    }
    if (response.statusCode == 429 && rateRetries > 0) {
      final seconds =
          (int.tryParse(response.headers['retry-after'] ?? '') ?? 60)
              .clamp(1, 120);
      await Future<void>.delayed(Duration(seconds: seconds));
      if (base != server ||
          (auth && store.data['remoteUserId'] != session!['userId'])) {
        throw StateError('La cuenta ha cambiado durante la espera.');
      }
      return request(method, path,
          body: body,
          auth: auth,
          retry: retry,
          rateRetries: rateRetries - 1,
          extraHeaders: extraHeaders);
    }
    if (response.statusCode >= 400) {
      if (response.statusCode == 409) {
        throw RemoteSyncFailure(response.statusCode,
            'Conflicto al sincronizar. Se conserva la revisión local para resolverla sin sobrescribir el historial.');
      }
      throw RemoteSyncFailure(response.statusCode,
          'Sincronización no disponible (${response.statusCode}). Reintenta; no se han borrado tus datos.');
    }
    return Json.from(jsonDecode(response.body));
  }

  Future<void> saveSession(Json session,
      {bool confirmAccountChange = false}) async {
    final server = base;
    final expectedUser = store.data['remoteUserId'];
    final expectedOwner = store.data['localDataOwnerId'];
    for (final key in ['userId', 'accessToken', 'refreshToken']) {
      if (session[key] is! String || (session[key] as String).isEmpty) {
        throw StateError(
            'Respuesta de sesión no válida. Tus datos se conservan.');
      }
    }
    final owner = store.data['localDataOwnerId'] ?? store.data['remoteUserId'];
    final ownerServer =
        store.data['localDataServer'] ?? store.data['remoteServer'];
    if (owner != null &&
        (owner != session['userId'] ||
            (ownerServer != null && ownerServer != server)) &&
        !confirmAccountChange) {
      throw StateError(
          'No se pueden vincular datos de otra cuenta sin confirmación.');
    }
    // One secure-store value: never pair a new access token with an old refresh.
    await secure.write(
        '$prefix:session',
        jsonEncode({
          'userId': session['userId'],
          'accessToken': session['accessToken'],
          'refreshToken': session['refreshToken']
        }));
    if (base != server ||
        store.data['remoteUserId'] != expectedUser ||
        store.data['localDataOwnerId'] != expectedOwner) {
      throw StateError(
          'La cuenta ha cambiado mientras se guardaba la sesión. Reintenta.');
    }
    if (store.data['remoteUserId'] != session['userId'] ||
        store.data['remoteServer'] != server) {
      store.data['reviews'] =
          store.list('reviews').map((e) => {...e, 'synced': false}).toList();
      store.data.remove('remoteCardIds');
      store.data.remove('remoteCardRevisions');
      store.data.remove('remoteCardDeckIds');
      store.data.remove('remoteCardClientIds');
      store.data.remove('remoteDeckNames');
      for (final key in [
        'workspaceBase',
        'workspaceRevision',
        'accountProfileBase',
        'accountProfileRevision',
        'autoWorkspaceConsent',
        'workspaceOutbox',
        'serverProgressVersion',
        'autoSyncConsent',
        'syncOutbox'
      ]) {
        store.data.remove(key);
      }
      store.data.remove('remoteGoogleLinked');
      store.data.remove('progressSyncHash');
      store.data.remove('lastProgressSync');
    }
    store.data['remoteUserId'] = session['userId'];
    store.data['remoteServer'] = server;
    store.data['localDataOwnerId'] = session['userId'];
    store.data['localDataServer'] = server;
    await store.save();
    await secure.delete('$prefix:access');
    await secure.delete('$prefix:refresh');
  }

  Future<void> connectGoogle(String firebaseIdToken,
      {bool confirmAccountChange = false}) async {
    if (firebaseIdToken.isEmpty) throw StateError('Identificación incompleta.');
    final initialUser = store.data['remoteUserId'];
    final initialOwner = store.data['localDataOwnerId'];
    if (initialUser != null) {
      // Link the current account; a conflict must never fall back to logging
      // into another account or silently reassign its study data.
      await send('/v1/auth/link', body: {'idToken': firebaseIdToken});
    } else {
      final session = await send('/v1/auth/oidc',
          body: {'idToken': firebaseIdToken}, auth: false);
      if (store.data['remoteUserId'] != initialUser ||
          store.data['localDataOwnerId'] != initialOwner) {
        throw StateError('La cuenta ha cambiado durante el acceso. Reintenta.');
      }
      await saveSession(session, confirmAccountChange: confirmAccountChange);
    }
    store.data['remoteGoogleLinked'] = true;
    await store.save();
  }

  Future<void> activate({bool confirmAccountChange = false}) async {
    _confirmAccountOperation(confirmAccountChange);
    await saveSession(await send('/v1/auth/guest', auth: false),
        confirmAccountChange: confirmAccountChange);
  }

  Future<void> _clearSession() async {
    await secure.delete('$prefix:session');
    await secure.delete('$prefix:access');
    await secure.delete('$prefix:refresh');
    store.data.remove('remoteUserId');
    store.data.remove('remoteServer');
    store.data.remove('remoteGoogleLinked');
    // Keep data ownership after logout: another login must not silently upload it.
    await store.save();
  }

  Future<void> disconnect() async {
    final owner = store.data['remoteUserId'];
    final server = base;
    try {
      await send('/v1/auth/logout');
    } finally {
      if (store.data['remoteUserId'] == owner && base == server) {
        await _clearSession();
      }
    }
  }

  Future<Json> exportRemote() => request('GET', '/v1/account/export');
  Future<String> recoveryCode() async =>
      (await send('/v1/auth/recovery-code'))['recoveryCode'];
  Future<String> recover(String code,
      {bool confirmAccountChange = false}) async {
    _confirmAccountOperation(confirmAccountChange);
    final receiptKey =
        '$prefix:recovery:${sha256.convert(utf8.encode(code.trim()))}';
    var stored = await secure.read(receiptKey);
    if (stored == null) {
      final random = Random.secure();
      stored = jsonEncode({
        'attemptId': const Uuid().v4(),
        'attemptSecret':
            base64UrlEncode(List.generate(32, (_) => random.nextInt(256)))
      });
      // Persist before consuming the code remotely. A failed vault write must
      // not destroy the only available recovery credential.
      await secure.write(receiptKey, stored);
    }
    final attempt = Json.from(jsonDecode(stored));
    final session = await send('/v1/auth/recover-idempotent',
        body: {'recoveryCode': code.trim(), ...attempt}, auth: false);
    final replacement = session['recoveryCode'];
    if (replacement is! String || replacement.length < 20) {
      throw StateError(
          'El servidor no entregó un código de recuperación válido.');
    }
    try {
      await saveSession(session, confirmAccountChange: confirmAccountChange);
    } catch (_) {
      // The old code was already consumed remotely. Never hide its replacement
      // just because Keychain/Keystore or the local disk rejected the session.
      throw RecoveryPersistenceFailure(replacement);
    }
    await secure.delete(receiptKey);
    return replacement;
  }

  Future<void> eraseRemote() async {
    await request('DELETE', '/v1/account?confirmation=ELIMINAR');
    await _clearSession();
  }

  Future<void> eraseWithIdentity(String idToken,
      {String? expectedUserId}) async {
    final owner = store.data['remoteUserId'];
    final server = base;
    await send('/v1/account/delete-with-identity', auth: false, body: {
      'idToken': idToken,
      'confirmation': 'ELIMINAR',
      'expectedUserId': expectedUserId
    });
    if (store.data['remoteUserId'] == owner &&
        base == server &&
        (owner == null || expectedUserId == owner)) {
      await _clearSession();
    }
  }

  Future<void> checkDeletionIdentity(String idToken,
      {String? expectedUserId}) async {
    await send('/v1/account/check-deletion-identity', auth: false, body: {
      'idToken': idToken,
      'confirmation': 'ELIMINAR',
      'expectedUserId': expectedUserId
    });
  }

  Future<void> pull() async {
    final upload = _uploads[store];
    if (upload != null) await upload;
    final previous = _pulls[store];
    if (previous != null) return previous;
    final operation = _performPull();
    _pulls[store] = operation;
    store.syncStatusChanged();
    try {
      await operation;
    } finally {
      if (identical(_pulls[store], operation)) _pulls[store] = null;
      store.syncStatusChanged();
    }
  }

  Future<void> _performPull() async {
    final snapshot = await exportRemote();
    final expected = jsonEncode(store.data);
    final server = base;
    var pendingEdits = false;
    final records =
        (snapshot['records'] as List).map((v) => Json.from(v)).toList();
    final userId = snapshot['userId'];
    if (userId != store.data['remoteUserId']) {
      throw StateError(
          'La respuesta pertenece a otra cuenta. No se ha importado nada.');
    }
    final decks = {
      for (final r in records.where((r) => r['kind'] == 'deck'))
        r['id']: r['title']
    };
    final remoteToLocal = <String, String>{};
    final aliases = <String, dynamic>{};
    final local = {for (final c in store.cards) c.id: c};
    final conflicts = <Json>[];
    final revisions = Json.from(store.data['remoteCardRevisions'] ?? {});
    for (final r in records.where((r) => r['kind'] == 'card')) {
      final id = r['clientId'] as String? ??
          const Uuid().v5('6ba7b811-9dad-11d1-80b4-00c04fd430c8', r['id']);
      remoteToLocal[r['id']] = id;
      aliases[id] = r['id'];
      final knownRevision = revisions[id];
      revisions[id] = r['revision'];
      final remote = remoteStudyCard(
          r, id, decks[r['deckId']] ?? local[id]?.deck ?? 'Mazo recuperado');
      final before = local[id];
      bool sameContent(StudyCard a, StudyCard b) =>
          jsonEncode([
            a.deck,
            a.front,
            a.back,
            a.explanation,
            a.type,
            a.options,
            a.correct,
            a.normId,
            a.unitId,
            a.versionId,
            a.unitVersionHash
          ]) ==
          jsonEncode([
            b.deck,
            b.front,
            b.back,
            b.explanation,
            b.type,
            b.options,
            b.correct,
            b.normId,
            b.unitId,
            b.versionId,
            b.unitVersionHash
          ]);
      if (before != null && !sameContent(before, remote)) {
        if (knownRevision != null &&
            before.revision > knownRevision &&
            remote.revision == knownRevision) {
          pendingEdits = true;
          // The server has not changed since our last download. Preserve local edits for If-Match upload.
        } else if (knownRevision != null &&
            before.revision == knownRevision &&
            remote.revision > knownRevision) {
          local[id] = remote;
        } else {
          conflicts.add({
            'cardId': id,
            'kind': 'card_content',
            'remote': remote.toJson(),
            'local': before.toJson()
          });
          local[id] = StudyCard.fromJson({
            ...before.toJson(),
            'blocked': true,
            'editorialState': 'sync_conflict'
          });
        }
      } else {
        local[id] = remote;
      }
    }
    final histories = {
      for (final h in store.list('cardHistory'))
        '${h['id']}:${h['revision']}': h
    };
    for (final row in records.where((r) => r['kind'] == 'card_revision')) {
      final id = remoteToLocal[row['cardId']];
      if (id == null) continue;
      final content = Json.from(row['content']);
      final historical = remoteStudyCard(
              content, id, decks[content['deckId']] ?? local[id]!.deck,
              revision: row['cardRevision'])
          .toJson();
      final key = '$id:${row['cardRevision']}';
      if (histories[key] == null) {
        histories[key] = {...historical, 'archivedAt': row['archivedAt']};
      }
    }
    final events = {for (final e in store.list('reviews')) e['id']: e};
    for (final r in records.where((r) => r['kind'] == 'review_event')) {
      final card = remoteToLocal[r['cardId']];
      if (card == null) continue;
      final key = r['idempotencyKey'] ?? r['id'];
      final before = events[key];
      if (before != null &&
          (before['rating'] != r['rating'] ||
              DateTime.parse(before['occurredAt']) !=
                  DateTime.parse(r['occurredAt']))) {
        conflicts.add({
          'cardId': card,
          'kind': 'review_event',
          'eventId': key,
          'remote': r,
          'local': before
        });
        continue;
      }
      events[key] = {
        ...?events[key],
        'id': key,
        'cardId': card,
        'cardRevision': r['cardRevision'],
        'rating': r['rating'],
        'occurredAt': r['occurredAt'],
        'latencyMs': r['latencyMs'] ?? 0,
        'response': r['response'],
        'objectiveCorrect': r['objectiveCorrect'],
        'algorithm': r['algorithm'],
        'synced': true,
        'syncedUserId': userId
      };
    }
    final states = Json.from(store.data['states'] ?? {});
    for (final r in records.where((r) => r['kind'] == 'review_state')) {
      final card = remoteToLocal[r['cardId'] ??
          r['id'].toString().substring(userId.toString().length + 1)];
      if (card == null) continue;
      if (events.values
          .any((e) => e['cardId'] == card && e['syncedUserId'] != userId)) {
        conflicts
            .add({'cardId': card, 'kind': 'pending_reviews', 'remoteState': r});
      } else {
        states[card] = r;
      }
    }
    final ordered = events.values.toList()
      ..sort((a, b) =>
          a['occurredAt'].toString().compareTo(b['occurredAt'].toString()));
    final changes = <String, dynamic>{
      'cards': local.values.map((c) => c.toJson()).toList(),
      'cardHistory': histories.values.toList(),
      'reviews': ordered,
      'states': states,
      'remoteCardIds': aliases,
      'remoteCardDeckIds': {
        for (final r in records.where((r) => r['kind'] == 'card'))
          remoteToLocal[r['id']]: r['deckId']
      },
      'remoteCardClientIds': {
        for (final r in records.where((r) => r['kind'] == 'card'))
          remoteToLocal[r['id']]: r['clientId']
      },
      'remoteDeckNames': decks,
      'remoteCardRevisions': revisions,
      'syncConflicts': conflicts,
      'syncOutbox': null,
      'lastProgressSync': DateTime.now().toUtc().toIso8601String(),
    };
    if (!pendingEdits &&
        conflicts.isEmpty &&
        local.keys.every(remoteToLocal.values.contains) &&
        ordered.every((e) => e['syncedUserId'] == userId)) {
      changes['progressSyncHash'] =
          progressFingerprintOf({...store.data, ...changes});
    }
    await store.commitRemotePull(expected, changes, userId, server);
  }

  Future<void> forkConflict(String id) async {
    final owner = store.data['remoteUserId'] as String?;
    final server = base;
    if (owner == null) throw StateError('Conecta la cuenta del conflicto.');
    final expected = store.cardById(id)?.toJson();
    if (expected == null) throw StateError('La tarjeta no está disponible.');
    final snapshot = await exportRemote();
    if (snapshot['userId'] != owner) {
      throw StateError('El servidor devolvió otra cuenta.');
    }
    final rows =
        (snapshot['records'] as List).map((r) => Json.from(r)).toList();
    final alias = (store.data['remoteCardIds'] as Map? ?? {})[id];
    final record =
        rows.where((r) => r['kind'] == 'card' && r['id'] == alias).firstOrNull;
    if (record == null ||
        (store.data['remoteCardRevisions'] as Map? ?? {})[id] !=
            record['revision']) {
      throw StateError(
          'El servidor cambió. Descarga de nuevo antes de resolver.');
    }
    final deck = rows
            .where((r) => r['kind'] == 'deck' && r['id'] == record['deckId'])
            .firstOrNull?['title'] ??
        expected['deck'];
    final remote = remoteStudyCard(record, id, deck);
    final history = rows
        .where((r) => r['kind'] == 'card_revision' && r['cardId'] == alias)
        .map((r) => {
              ...remoteStudyCard(Json.from(r['content']), id, deck,
                      revision: r['cardRevision'])
                  .toJson(),
              'archivedAt': r['archivedAt']
            })
        .toList();
    final events = rows
        .where((r) => r['kind'] == 'review_event' && r['cardId'] == alias)
        .map((r) => {
              'id': r['idempotencyKey'] ?? r['id'],
              'cardId': id,
              'cardRevision': r['cardRevision'],
              'rating': r['rating'],
              'occurredAt': r['occurredAt'],
              'latencyMs': r['latencyMs'] ?? 0,
              'response': r['response'],
              'algorithm': r['algorithm'],
              'synced': true,
              'syncedUserId': owner,
            })
        .toList();
    final state = rows
        .where((r) => r['kind'] == 'review_state' && r['cardId'] == alias)
        .firstOrNull;
    await store.commitConflictFork(
        id, expected, remote, history, events, state, owner, server);
  }

  Future<void> syncNotifications() async {
    await send('/v1/legal-updates/subscriptions', body: {
      'normIds': List<String>.from(store.data['follows'] ?? []),
      'enabled': (store.profile['account'] as Map?)?['legalNotifications'] ??
          store.data['internalAlerts'] ??
          true,
      'frequency': store.data['alertFrequency'] ?? 'immediate',
    });
    final result = await request('GET', '/v1/notifications');
    store.data['notifications'] = result['items'];
    await store.save();
  }

  Future<void> uploadReports() async {
    final reports = store.list('reports');
    for (var i = 0; i < reports.length; i++) {
      final report = reports[i];
      if (report['status'] != 'local_pending') continue;
      final remoteId =
          (store.data['remoteCardIds'] as Map? ?? {})[report['cardId']];
      if (remoteId == null) continue;
      final result = await send('/v1/reports', body: {
        'clientId': report['id'],
        'cardId': remoteId,
        'reason': report['reason'],
        'severity': report['severity'] ?? 'normal'
      });
      reports[i] = {
        ...report,
        'status': result['status'],
        'remoteId': result['id']
      };
      store.data['reports'] = reports;
      await store.save();
    }
  }

  Json cardPayload(StudyCard c, String deckId) => {
        'clientId':
            (store.data['remoteCardClientIds'] as Map? ?? {}).containsKey(c.id)
                ? store.data['remoteCardClientIds'][c.id]
                : c.id,
        'deckId': deckId,
        'front': c.front,
        'back': c.back,
        'explanation': c.explanation,
        'type': c.type,
        'options': c.options,
        'correct': c.correct,
        'citations': c.versionId.isEmpty
            ? []
            : [
                {
                  'normId': c.normId,
                  'unitId': c.unitId,
                  'versionId': c.versionId,
                  if (c.unitVersionHash.isNotEmpty)
                    'unitVersionHash': c.unitVersionHash
                }
              ],
      };
  Future<void> upload() async {
    final pull = _pulls[store];
    if (pull != null) await pull;
    final existing = _uploads[store];
    if (existing != null) return existing;
    final operationOwner = store.data['remoteUserId'];
    final operationServer = base;
    final operation = _performUpload();
    _uploads[store] = operation;
    store.syncStatusChanged();
    try {
      await operation;
    } catch (error) {
      final owner = store.data['remoteUserId'];
      if (owner != null && owner == operationOwner && base == operationServer) {
        try {
          await store.setSyncQueue({
            'userId': owner,
            'server': base,
            'state': error is RemoteSyncFailure && error.status == 409
                ? 'conflict'
                : 'error',
            'connection':
                error is http.ClientException || error is TimeoutException,
          });
        } catch (_) {
          /* Preserve the original error if local storage also fails. */
        }
      }
      rethrow;
    } finally {
      if (identical(_uploads[store], operation)) _uploads[store] = null;
      store.syncStatusChanged();
    }
  }

  Future<void> _performUpload() async {
    final owner = store.data['remoteUserId'];
    final server = base;
    final identity = await request('GET', '/v1/auth/session');
    if (identity['userId'] != owner) {
      throw StateError('El servidor no confirmó la cuenta de la copia.');
    }
    void checkOwner() {
      if (store.data['remoteUserId'] != owner || base != server) {
        throw StateError(
            'La cuenta cambió durante la subida. Tus datos se conservan.');
      }
    }

    final fingerprint = progressFingerprint;
    final unknown = store.cards
        .where((c) => (store.data['remoteCardIds'] as Map? ?? {})[c.id] == null)
        .map((c) => c.id)
        .toList();
    for (var offset = 0; offset < unknown.length; offset += 100) {
      final batch = unknown.skip(offset).take(100).toList();
      final result = await send('/v1/cards/lookup', body: {'clientIds': batch});
      checkOwner();
      for (final raw in result['items'] as List) {
        final existing = Json.from(raw);
        final id =
            (existing['lookupClientId'] ?? existing['clientId']) as String;
        if (!batch.contains(id)) {
          throw StateError(
              'El servidor devolvió un identificador ajeno al lote.');
        }
        final history = [
          ...store
              .list('cardHistory')
              .where((h) => h['id'] == id)
              .map(StudyCard.fromJson),
          ...store.cards.where((c) => c.id == id)
        ];
        final matching = history
            .where((c) => c.revision == existing['revision'])
            .firstOrNull;
        if (matching == null ||
            matching.deck != existing['deckTitle'] ||
            !({
              ...cardPayload(matching, existing['deckId']),
              'clientId': existing['clientId']
            }).entries.every((e) =>
                jsonEncode(canonicalJsonValue(e.value)) ==
                jsonEncode(canonicalJsonValue(existing[e.key])))) {
          throw RemoteSyncFailure(409,
              'Hay otra revisión en la cuenta. Descarga y compara antes de subir; se conserva la versión local.');
        }
        store.data['remoteCardClientIds'] = {
          ...(store.data['remoteCardClientIds'] as Map? ?? {}),
          id: existing['clientId']
        };
        store.data['remoteCardIds'] = {
          ...(store.data['remoteCardIds'] as Map? ?? {}),
          id: existing['id']
        };
        store.data['remoteCardRevisions'] = {
          ...(store.data['remoteCardRevisions'] as Map? ?? {}),
          id: existing['revision']
        };
        store.data['remoteCardDeckIds'] = {
          ...(store.data['remoteCardDeckIds'] as Map? ?? {}),
          id: existing['deckId']
        };
        store.data['remoteDeckNames'] = {
          ...(store.data['remoteDeckNames'] as Map? ?? {}),
          existing['deckId']: existing['deckTitle']
        };
      }
      await store.save();
    }
    final uploadedDecks = <String, Json>{};
    final remoteCards = <String, String>{};
    final conflictCards =
        store.list('syncConflicts').map((c) => c['cardId']).toSet();
    for (final c in store.cards) {
      checkOwner();
      if (conflictCards.contains(c.id)) continue;
      var alias = (store.data['remoteCardIds'] as Map? ?? {})[c.id] as String?;
      var revision =
          (store.data['remoteCardRevisions'] as Map? ?? {})[c.id] as int?;
      final history = [
        ...store
            .list('cardHistory')
            .where((h) => h['id'] == c.id)
            .map(StudyCard.fromJson),
        c
      ]..sort((a, b) => a.revision.compareTo(b.revision));
      if (alias != null && revision == null) {
        throw StateError(
            'Descarga el progreso antes de subir ediciones de este dispositivo.');
      }
      for (final version in history) {
        checkOwner();
        if (revision != null && version.revision <= revision) continue;
        final deckId = const Uuid()
            .v5('6ba7b811-9dad-11d1-80b4-00c04fd430c8', version.deck);
        final knownDeckId =
            (store.data['remoteCardDeckIds'] as Map? ?? {})[c.id];
        final keepDeck = knownDeckId != null &&
            (store.data['remoteDeckNames'] as Map? ?? {})[knownDeckId] ==
                version.deck;
        final deck = keepDeck
            ? <String, dynamic>{'id': knownDeckId}
            : uploadedDecks[deckId] ??
                await send('/v1/decks', body: {
                  'title': version.deck,
                  'visibility': 'private',
                  'clientId': deckId
                });
        uploadedDecks[deckId] = deck;
        checkOwner();
        if (version.revision != (revision ?? 0) + 1) {
          throw StateError(
              'Falta una revisión local de la tarjeta. Se conserva el historial sin sobrescribirlo.');
        }
        Json card;
        try {
          card = alias == null
              ? await send('/v1/cards', body: cardPayload(version, deck['id']))
              : await request('PUT', '/v1/cards/$alias',
                  body: cardPayload(version, deck['id']),
                  extraHeaders: {'If-Match': '$revision'});
        } on RemoteSyncFailure catch (failure) {
          if (failure.status != 409) rethrow;
          final existing = await request(
              'GET', '/v1/cards/by-client/${Uri.encodeComponent(c.id)}');
          final matching = history
              .where((h) => h.revision == existing['revision'])
              .firstOrNull;
          if (matching == null || existing['deckTitle'] != matching.deck) {
            rethrow;
          }
          final payload = cardPayload(matching, existing['deckId']);
          if (!payload.entries.every((e) =>
              jsonEncode(canonicalJsonValue(e.value)) ==
              jsonEncode(canonicalJsonValue(existing[e.key])))) {
            rethrow;
          }
          card = existing;
        }
        checkOwner();
        store.data['remoteCardDeckIds'] = {
          ...(store.data['remoteCardDeckIds'] as Map? ?? {}),
          c.id: card['deckId'] ?? deck['id']
        };
        store.data['remoteDeckNames'] = {
          ...(store.data['remoteDeckNames'] as Map? ?? {}),
          (card['deckId'] ?? deck['id']): version.deck
        };
        alias = card['id'];
        revision = card['revision'];
        store.data['remoteCardIds'] = {
          ...(store.data['remoteCardIds'] as Map? ?? {}),
          c.id: alias
        };
        store.data['remoteCardRevisions'] = {
          ...(store.data['remoteCardRevisions'] as Map? ?? {}),
          c.id: revision
        };
        await store.save();
      }
      if (alias != null) remoteCards[c.id] = alias;
    }
    final events = store.list('reviews');
    for (var i = 0; i < events.length; i++) {
      checkOwner();
      final e = events[i];
      if (e['syncedUserId'] == store.data['remoteUserId'] ||
          remoteCards[e['cardId']] == null) {
        continue;
      }
      await send('/v1/reviews', body: {
        'cardId': remoteCards[e['cardId']],
        'cardRevision': e['cardRevision'],
        'rating': e['rating'],
        'occurredAt': e['occurredAt'],
        'idempotencyKey': e['id'],
        'latencyMs': e['latencyMs'] ?? 0,
        'response': e['response']
      });
      events[i] = {
        ...e,
        'synced': true,
        'syncedUserId': store.data['remoteUserId']
      };
      store.data['reviews'] = events;
      await store.save();
    }
    await uploadReports();
    checkOwner();
    if (conflictCards.isNotEmpty) {
      throw StateError(
          'Se han conservado los conflictos. El resto del progreso se ha subido sin sobrescribirlos.');
    }
    store.data['lastProgressSync'] = DateTime.now().toUtc().toIso8601String();
    store.data['progressSyncHash'] = fingerprint;
    store.data['syncOutbox'] = {
      'state': 'confirmed',
      'userId': owner,
      'server': server
    };
    await store.save();
  }
}
