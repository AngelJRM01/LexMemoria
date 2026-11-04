import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'models.dart';

class AppStore extends ChangeNotifier {
  final SharedPreferences prefs;
  Json data;
  String? error;
  bool syncing = false;
  Future<void> _write = Future.value();
  AppStore(this.prefs, this.data);
  static Future<AppStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('lexmemoria.v1');
    Json data;
    try { data = raw == null ? {} : Json.from(jsonDecode(raw)); }
    catch (_) { throw StateError('No se han podido leer los datos guardados. Conserva una copia antes de restablecer la aplicación.'); }
    return AppStore(prefs, data);
  }
  bool get onboarded => data['onboarded'] == true;
  Json get profile => Json.from(data['profile'] ?? {});
  String get mode => profile['mode'] ?? 'Ambos';
  bool get dark => data['dark'] == true;
  List<StudyCard> get cards => (data['cards'] as List? ?? []).map((v) => StudyCard.fromJson(Json.from(v))).toList();
  List<Json> list(String key) => (data[key] as List? ?? []).map((v) => Json.from(v)).toList();
  List<Json> get catalogue {
    final cached = {for (final n in list('norms')) n['id']: n};
    return initialCatalogue().map((n) => <String, dynamic>{...n, ...?cached.remove(n['id'])}).toList()..addAll(cached.values);
  }
  Json state(String id) => Json.from((data['states'] as Map? ?? {})[id] ?? {});
  List<StudyCard> due({String? deck}) => cards.where((c) {
    final when = state(c.id)['dueAt'];
    return !c.blocked && (deck == null || c.deck == deck) &&
      (when == null || !DateTime.parse(when).isAfter(DateTime.now()));
  }).take((profile['dailyGoal'] as num? ?? 20).toInt()).toList();
  Future<void> save() {
    final snapshot = jsonEncode(data);
    _write = _write.catchError((_) {}).then((_) async {
      final ok = await prefs.setString('lexmemoria.v1', snapshot);
      if (!ok) throw StateError('No se pudo guardar. Exporta tus datos.');
    });
    notifyListeners();
    return _write;
  }
  Future<void> setProfile(Json p) async { data['profile'] = {...profile, ...p}; await save(); }
  Future<void> addCard(StudyCard c) async {
    data['cards'] = [...cards.map((v) => v.toJson()), c.toJson()]; await save();
  }
  Future<void> add(String key, Json value) async { data[key] = [...list(key), value]; await save(); }
  Future<void> toggle(String key, String id) async {
    final values = List<String>.from(data[key] ?? []);
    values.contains(id) ? values.remove(id) : values.add(id);
    data[key] = values; await save();
  }
  bool has(String key, String id) => (data[key] as List? ?? []).contains(id);
  Future<void> review(StudyCard card, int rating, {int latencyMs = 0}) async {
    if (card.blocked) throw StateError('Tarjeta bloqueada por revisión normativa');
    final at = DateTime.now().toUtc();
    final previous = state(card.id);
    final event = <String, dynamic>{'id': const Uuid().v4(), 'cardId': card.id,
      'cardRevision': card.revision, 'rating': rating, 'occurredAt': at.toIso8601String(),
      'previous': previous, 'latencyMs': latencyMs, 'algorithm': 'sm2-1'};
    data['states'] = {...(data['states'] as Map? ?? {}), card.id: schedule(previous, rating, at)};
    data['reviews'] = [...list('reviews'), event];
    data['session'] = null;
    await save();
  }
  Future<void> undoLast() async {
    final events = list('reviews');
    if (events.isEmpty) return;
    final last = events.last;
    if (last['synced'] == true) throw StateError('La revisión sincronizada conserva su historial y no se puede deshacer.');
    events.removeLast();
    data['reviews'] = events;
    data['states'] = {...(data['states'] as Map? ?? {}), last['cardId']: last['previous']};
    await save();
  }
  Future<void> reset() async { data = {}; await save(); }
  Future<void> restore(String text) async {
    final parsed = jsonDecode(text);
    if (parsed is! Map || parsed['schemaVersion'] != 1 || parsed['data'] is! Map) {
      throw const FormatException('Copia incompatible');
    }
    final restored = Json.from(parsed['data']);
    for (final c in restored['cards'] as List? ?? []) { StudyCard.fromJson(Json.from(c)); }
    // A local backup never restores server authentication.
    restored.remove('auth');
    data = restored; await save();
  }
  String export() => const JsonEncoder.withIndent('  ').convert({'schemaVersion': 1,
    'exportedAt': DateTime.now().toUtc().toIso8601String(), 'data': {...data}..remove('auth')});

  Future<void> fetchCatalogue() async {
    final base = (data['apiUrl'] as String? ?? '').replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty) throw StateError('Configura la dirección del servidor en Perfil.');
    final uri = Uri.parse(base);
    if (uri.scheme != 'https' && uri.host != '10.0.2.2' && uri.host != 'localhost' && uri.host != '127.0.0.1') {
      throw StateError('El servidor debe usar HTTPS.');
    }
    syncing = true; error = null; notifyListeners();
    try {
      final response = await http.get(Uri.parse('$base/v1/library/norms?limit=100')).timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) throw StateError('Servidor no disponible (${response.statusCode})');
      final result = Json.from(jsonDecode(response.body));
      final norms = (result['items'] as List).map((n) => Json.from(n)).toList();
      await applyCatalogue(norms);
      data['lastSync'] = DateTime.now().toUtc().toIso8601String(); await save();
    } catch (e) { error = 'No se pudo sincronizar. Los datos locales se conservan. $e'; rethrow; }
    finally { syncing = false; notifyListeners(); }
  }
  Future<void> applyCatalogue(List<Json> norms) async {
    final old = {for (final n in list('norms')) n['id']: n};
    final changed = <String>{};
    for (final n in norms) {
      final before = old[n['id']];
      final update = <String, dynamic>{...?before, ...n};
      if (before != null && before['latestVersion'] != null && before['latestVersion'] != n['latestVersion']) {
        changed.add(n['id']);
        if (before['units'] != null) data['archivedPacks'] = [...list('archivedPacks'), before];
        update.remove('units'); update.remove('downloadedAt');
        update['coverage'] = 'pending_download_after_change';
      }
      old[n['id']] = update;
      for (final c in cards) {
        if (c.normId == n['id'] && c.versionId.isNotEmpty && c.versionId != n['latestVersion']) changed.add(c.normId);
      }
    }
    data['norms'] = old.values.toList();
    data['cards'] = cards.map((c) => changed.contains(c.normId) ? {...c.toJson(), 'blocked': true, 'editorialState': 'pending'} : c.toJson()).toList();
    await save();
  }
  Future<void> downloadNorm(Json norm) async {
    final base = (data['apiUrl'] as String? ?? '').replaceAll(RegExp(r'/$'), '');
    final version = norm['latestVersion'];
    if (base.isEmpty || version == null) throw StateError('Importa primero esta norma en el servidor.');
    final uri = Uri.parse('$base/v1/library/norms/${norm['id']}/units').replace(queryParameters: {'version': version});
    final r = await http.get(uri).timeout(const Duration(seconds: 45));
    if (r.statusCode != 200) throw StateError('No se descargó el texto (${r.statusCode}). Reintenta.');
    final payload = Json.from(jsonDecode(r.body));
    final rows = list('norms').where((n) => n['id'] != norm['id']).toList();
    rows.add({...norm, 'units': payload['items'], 'downloadedAt': DateTime.now().toUtc().toIso8601String()});
    data['norms'] = rows; await save();
  }
}
