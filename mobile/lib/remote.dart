import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'store.dart';

/// Optional remote identity. Tokens never enter preferences, exports or logs.
class RemoteSync {
  final AppStore store;
  final FlutterSecureStorage secure;
  RemoteSync(this.store, {this.secure = const FlutterSecureStorage()});
  String get base {
    final value = (store.data['apiUrl'] as String? ?? '').replaceAll(RegExp(r'/$'), '');
    final uri = Uri.tryParse(value);
    if (uri == null || uri.scheme != 'https') throw StateError('Configura una API HTTPS para sincronizar datos privados.');
    return value;
  }
  String get prefix => 'lexmemoria:${Uri.parse(base).host}';
  Future<Json> send(String path, {Json? body, bool auth = true, bool retry = true}) async {
    final token = auth ? await secure.read(key: '$prefix:access') : null;
    if (auth && token == null) throw StateError('Activa primero tu identidad de sincronización.');
    final response = await http.post(Uri.parse('$base$path'), headers: {'Content-Type': 'application/json', if (token != null) 'Authorization': 'Bearer $token'},
      body: jsonEncode(body ?? {})).timeout(const Duration(seconds: 30));
    if (response.statusCode == 401 && auth && retry) {
      final refresh = await secure.read(key: '$prefix:refresh');
      if (refresh == null) throw StateError('Sesión caducada. Tu progreso local se conserva.');
      final session = await send('/v1/auth/refresh', body: {'refreshToken': refresh}, auth: false, retry: false);
      await saveSession(session);
      return send(path, body: body, retry: false);
    }
    if (response.statusCode >= 400) {
      if (response.statusCode == 409) throw StateError('Conflicto al sincronizar. Se conserva la revisión local para resolverla sin sobrescribir el historial.');
      throw StateError('Sincronización no disponible (${response.statusCode}). Reintenta; no se han borrado tus datos.');
    }
    return Json.from(jsonDecode(response.body));
  }
  Future<void> saveSession(Json session) async {
    await secure.write(key: '$prefix:access', value: session['accessToken']);
    await secure.write(key: '$prefix:refresh', value: session['refreshToken']);
    if (store.data['remoteUserId'] != null && store.data['remoteUserId'] != session['userId']) {
      store.data['reviews'] = store.list('reviews').map((e) => {...e, 'synced': false}).toList();
    }
    store.data['remoteUserId'] = session['userId'];
    await store.save();
  }
  Future<void> activate() async {
    await saveSession(await send('/v1/auth/guest', auth: false));
  }
  Future<void> disconnect() async {
    try { await send('/v1/auth/logout'); }
    finally {
      await secure.delete(key: '$prefix:access'); await secure.delete(key: '$prefix:refresh');
      store.data.remove('remoteUserId'); await store.save();
    }
  }
  Future<Json> exportRemote() async {
    final token = await secure.read(key: '$prefix:access');
    if (token == null) throw StateError('No hay sesión remota.');
    final r = await http.get(Uri.parse('$base/v1/account/export'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw StateError('Renueva la sesión subiendo el progreso y reintenta la exportación.');
    return Json.from(jsonDecode(r.body));
  }
  Future<void> eraseRemote() async {
    final token = await secure.read(key: '$prefix:access');
    if (token == null) throw StateError('No hay sesión remota.');
    final r = await http.delete(Uri.parse('$base/v1/account?confirmation=ELIMINAR'), headers: {'Authorization': 'Bearer $token'}).timeout(const Duration(seconds: 30));
    if (r.statusCode != 200) throw StateError('No se ha borrado la cuenta remota. Renueva la sesión y reintenta.');
    await secure.delete(key: '$prefix:access'); await secure.delete(key: '$prefix:refresh');
    store.data.remove('remoteUserId'); await store.save();
  }
  Future<void> upload() async {
    final remoteCards = <String, String>{};
    for (final c in store.cards) {
      final deckId = const Uuid().v5('6ba7b811-9dad-11d1-80b4-00c04fd430c8', c.deck);
      final deck = await send('/v1/decks', body: {'title': c.deck, 'visibility': 'private', 'clientId': deckId});
      final card = await send('/v1/cards', body: {'clientId': c.id, 'deckId': deck['id'], 'front': c.front, 'back': c.back,
        'explanation': c.explanation, 'type': c.type, 'options': c.options, 'correct': c.correct,
        'citations': c.versionId.isEmpty ? [] : [{'normId': c.normId, 'unitId': c.unitId, 'versionId': c.versionId}]});
      remoteCards[c.id] = card['id'];
    }
    final events = store.list('reviews');
    for (var i = 0; i < events.length; i++) {
      final e = events[i];
      if (e['synced'] == true || remoteCards[e['cardId']] == null) continue;
      await send('/v1/reviews', body: {'cardId': remoteCards[e['cardId']], 'cardRevision': e['cardRevision'], 'rating': e['rating'],
        'occurredAt': e['occurredAt'], 'idempotencyKey': e['id']});
      events[i] = {...e, 'synced': true}; store.data['reviews'] = events; await store.save();
    }
    store.data['lastProgressSync'] = DateTime.now().toUtc().toIso8601String(); await store.save();
  }
}
