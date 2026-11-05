import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'store.dart';

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
  Future<Json> send(String path,
          {Json? body, bool auth = true, bool retry = true}) =>
      request('POST', path, body: body, auth: auth, retry: retry);
  Future<Json> request(String method, String path,
      {Json? body,
      bool auth = true,
      bool retry = true,
      Json extraHeaders = const {}}) async {
    final token = auth ? await secure.read('$prefix:access') : null;
    if (auth && token == null) {
      throw StateError('Activa o recupera tu identidad de sincronización.');
    }
    final uri = Uri.parse('$base$path');
    final headers = <String, String>{
      ...extraHeaders.map((k, v) => MapEntry(k, v.toString())),
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token'
    };
    final response = await (method == 'GET'
            ? store.client.get(uri, headers: headers)
            : method == 'DELETE'
                ? store.client.delete(uri, headers: headers)
                : method == 'PUT'
                    ? store.client.put(uri,
                        headers: headers, body: jsonEncode(body ?? {}))
                    : store.client.post(uri,
                        headers: headers, body: jsonEncode(body ?? {})))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode == 401 && auth && retry) {
      final refresh = await secure.read('$prefix:refresh');
      if (refresh == null) {
        throw StateError('Sesión caducada. Tu progreso local se conserva.');
      }
      final session = await send('/v1/auth/refresh',
          body: {'refreshToken': refresh}, auth: false, retry: false);
      await saveSession(session);
      return request(method, path,
          body: body, retry: false, extraHeaders: extraHeaders);
    }
    if (response.statusCode >= 400) {
      if (response.statusCode == 409) {
        throw StateError(
            'Conflicto al sincronizar. Se conserva la revisión local para resolverla sin sobrescribir el historial.');
      }
      throw StateError(
          'Sincronización no disponible (${response.statusCode}). Reintenta; no se han borrado tus datos.');
    }
    return Json.from(jsonDecode(response.body));
  }

  Future<void> saveSession(Json session) async {
    await secure.write('$prefix:access', session['accessToken']);
    await secure.write('$prefix:refresh', session['refreshToken']);
    if (store.data['remoteUserId'] != session['userId']) {
      store.data['reviews'] =
          store.list('reviews').map((e) => {...e, 'synced': false}).toList();
      store.data.remove('remoteCardIds');
      store.data.remove('remoteCardRevisions');
      store.data.remove('workspaceBase');
    }
    store.data['remoteUserId'] = session['userId'];
    await store.save();
  }

  Future<void> activate() async {
    await saveSession(await send('/v1/auth/guest', auth: false));
  }

  Future<void> disconnect() async {
    try {
      await send('/v1/auth/logout');
    } finally {
      await secure.delete('$prefix:access');
      await secure.delete('$prefix:refresh');
      store.data.remove('remoteUserId');
      await store.save();
    }
  }

  Future<Json> exportRemote() => request('GET', '/v1/account/export');
  Future<String> recoveryCode() async =>
      (await send('/v1/auth/recovery-code'))['recoveryCode'];
  Future<String> recover(String code) async {
    final session = await send('/v1/auth/recover',
        body: {'recoveryCode': code.trim()}, auth: false);
    await saveSession(session);
    return session['recoveryCode'];
  }

  Future<void> eraseRemote() async {
    await request('DELETE', '/v1/account?confirmation=ELIMINAR');
    await secure.delete('$prefix:access');
    await secure.delete('$prefix:refresh');
    store.data.remove('remoteUserId');
    await store.save();
  }

  Future<void> pull() async {
    final snapshot = await exportRemote();
    final records =
        (snapshot['records'] as List).map((v) => Json.from(v)).toList();
    final userId = snapshot['userId'];
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
      final citation = (r['citations'] as List? ?? []).firstOrNull as Map?;
      final remote = StudyCard(
          id: id,
          deck: decks[r['deckId']] ?? local[id]?.deck ?? 'Mazo recuperado',
          front: r['front'],
          back: r['back'],
          explanation: r['explanation'] ?? '',
          type: r['type'] ?? 'qa',
          normId: citation?['normId'] ?? '',
          unitId: citation?['unitId'] ?? '',
          versionId: citation?['versionId'] ?? '',
          unitVersionHash: citation?['unitVersionHash'] ?? '',
          revision: r['revision'] ?? 1,
          blocked: r['blocked'] ?? false,
          editorialState: r['editorialState'] ?? 'user',
          options: List<String>.from(r['options'] ?? []),
          correct: r['correct']);
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
          // The server has not changed since our last download. Preserve local edits for If-Match upload.
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
      final citation =
          (content['citations'] as List? ?? []).firstOrNull as Map?;
      final historical = StudyCard(
              id: id,
              deck: decks[content['deckId']] ?? local[id]!.deck,
              front: content['front'],
              back: content['back'],
              explanation: content['explanation'] ?? '',
              type: content['type'] ?? 'qa',
              normId: citation?['normId'] ?? '',
              unitId: citation?['unitId'] ?? '',
              versionId: citation?['versionId'] ?? '',
              unitVersionHash: citation?['unitVersionHash'] ?? '',
              options: List<String>.from(content['options'] ?? []),
              correct: content['correct'],
              revision: row['cardRevision'])
          .toJson();
      final key = '$id:${row['cardRevision']}';
      if (histories[key] == null) {
        histories[key] = {...historical, 'archivedAt': row['archivedAt']};
      }
    }
    store.data['cardHistory'] = histories.values.toList();
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
    store.data['cards'] = local.values.map((c) => c.toJson()).toList();
    store.data['reviews'] = ordered;
    store.data['states'] = states;
    store.data['remoteCardIds'] = aliases;
    store.data['remoteCardRevisions'] = revisions;
    store.data['syncConflicts'] = conflicts;
    store.data['lastProgressSync'] = DateTime.now().toUtc().toIso8601String();
    await store.save();
  }

  Future<void> syncNotifications() async {
    await send('/v1/legal-updates/subscriptions', body: {
      'normIds': List<String>.from(store.data['follows'] ?? []),
      'enabled': store.data['internalAlerts'] ?? true,
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
        'clientId': c.id,
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
    final remoteCards = <String, String>{};
    final conflictCards =
        store.list('syncConflicts').map((c) => c['cardId']).toSet();
    for (final c in store.cards) {
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
        if (revision != null && version.revision <= revision) continue;
        final deckId = const Uuid()
            .v5('6ba7b811-9dad-11d1-80b4-00c04fd430c8', version.deck);
        final deck = await send('/v1/decks', body: {
          'title': version.deck,
          'visibility': 'private',
          'clientId': deckId
        });
        if (version.revision != (revision ?? 0) + 1) {
          throw StateError(
              'Falta una revisión local de la tarjeta. Se conserva el historial sin sobrescribirlo.');
        }
        final card = alias == null
            ? await send('/v1/cards', body: cardPayload(version, deck['id']))
            : await request('PUT', '/v1/cards/$alias',
                body: cardPayload(version, deck['id']),
                extraHeaders: {'If-Match': '$revision'});
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
    if (conflictCards.isNotEmpty) {
      throw StateError(
          'Se han conservado los conflictos. El resto del progreso se ha subido sin sobrescribirlos.');
    }
    store.data['lastProgressSync'] = DateTime.now().toUtc().toIso8601String();
    await store.save();
  }
}
