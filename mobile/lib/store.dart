import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'persistence.dart';
import 'startup.dart';
import 'prepared.dart';
import 'pack_cache.dart';
import 'catalogue.dart';

class AppStore extends ChangeNotifier {
  final SharedPreferences prefs;
  Json data;
  final http.Client client;
  final LocalPersistence persistence;
  final PackCache packCache;
  List<Json> corpusNorms = [];
  final loadedPackVersions = <String, String>{};
  final _packDownloads = <String, Future<void>>{};
  List<Json> bundledNorms = [];
  final Map<String, List<dynamic>> bundledPacks = {};
  List<Json> preparedDecks = [];
  List<String> get availableSubjects => catalogueSubjects(catalogue);
  String? error;
  bool syncing = false;
  Future<void> _write = Future.value();
  AppStore(this.prefs, this.data,
      {http.Client? client,
      LocalPersistence? persistence,
      PackCache? packCache})
      : client = client ?? http.Client(),
        packCache = packCache ?? MemoryPackCache(),
        persistence = persistence ?? PreferencesPersistence(prefs);
  static Future<AppStore> load({LocalPersistence? persistence}) async {
    final prefs =
        await startupStep('PREFERENCES', SharedPreferences.getInstance);
    final LocalPersistence storage = persistence ??
        await startupStep<LocalPersistence>(
            'SECURE_STORAGE', () => EncryptedPersistence.open(prefs));
    try {
      final saved = await startupStep('READ_SNAPSHOT', storage.read);
      final legacy = prefs.getString('lexmemoria.v1');
      final raw = saved ?? legacy;
      Json data;
      try {
        data = raw == null ? {} : Json.from(jsonDecode(raw));
      } catch (_) {
        throw StartupFailure('SNAPSHOT_FORMAT');
      }
      if (saved == null &&
          legacy != null &&
          storage is! PreferencesPersistence) {
        await startupStep('MIGRATION_WRITE', () => storage.write(legacy));
        if (await startupStep('MIGRATION_VERIFY', storage.read) != legacy) {
          throw StartupFailure('MIGRATION_VERIFY');
        }
        await startupStep(
            'MIGRATION_FINISH', () => prefs.remove('lexmemoria.v1'));
      }
      final store = AppStore(prefs, data,
          persistence: storage,
          packCache: storage is EncryptedPersistence
              ? await startupStep('CORPUS_CACHE', openPackCache)
              : MemoryPackCache());
      final catalogueAsset =
          await rootBundle.load('assets/corpus-catalogue.json.gz');
      final catalogueBytes = catalogueAsset.buffer.asUint8List(
          catalogueAsset.offsetInBytes, catalogueAsset.lengthInBytes);
      store.corpusNorms = storage is EncryptedPersistence
          ? await compute(decodeCorpusCatalogue, catalogueBytes)
          : decodeCorpusCatalogue(catalogueBytes);
      try {
        final manifest = Json.from(jsonDecode(
            await rootBundle.loadString('assets/legal-catalogue.json')));
        store.bundledNorms = (manifest['items'] as List)
            .map((v) => <String, dynamic>{
                  ...Json.from(v),
                  'bundledVersion': v['latestVersion']
                })
            .toList();
      } catch (_) {
        store.error =
            'No se ha podido cargar el catálogo incluido (LEGAL_CATALOGUE). Tus tarjetas y notas se conservan.';
      }
      for (final norm in store
          .list('norms')
          .where((n) => n['bundledReady'] == true)
          .toList()
          .reversed
          .take(4)) {
        final asset = store.bundledNorms
            .where((n) =>
                n['id'] == norm['id'] &&
                n['latestVersion'] == norm['latestVersion'])
            .firstOrNull;
        if (asset != null) {
          try {
            await store.loadBundledPack(asset);
          } catch (_) {
            store.error =
                'No se ha podido abrir un paquete de lectura (LEGAL_PACK). Tus datos personales se conservan; vuelve a descargar el texto.';
          }
        }
      }
      await store.loadPreparedCards();
      return store;
    } catch (_) {
      try {
        await storage.close();
      } catch (_) {/* Preserve the original startup failure. */}
      rethrow;
    }
  }

  bool get onboarded => data['onboarded'] == true;
  Future<void> loadPreparedCards() async {
    final manifest = Json.from(
        jsonDecode(await rootBundle.loadString('assets/ready/index.json')));
    final corpusById = {for (final n in corpusNorms) n['id']: n};
    preparedDecks = (manifest['items'] as List)
        .map((v) => <String, dynamic>{...?corpusById[v['id']], ...Json.from(v)})
        .toList();
    final localIds = preparedDecks.map((d) => d['id']).toSet();
    preparedDecks.addAll(corpusNorms.where(
        (n) => !localIds.contains(n['id']) && (n['count'] as num? ?? 0) > 0));
    if (data['starterInstalled'] != true) {
      await installPreparedDeck(Json.from(manifest['starter']));
      data['starterInstalled'] = true;
      await save();
    }
  }

  Future<int> installPreparedDeck(Json deck,
      {String format = 'qa', String? group}) async {
    if (deck['asset'] == null ||
        format != 'qa' ||
        (group ?? '').trim().isNotEmpty) {
      final norm = catalogue.firstWhere((n) => n['id'] == deck['id']);
      await downloadNorm(norm);
      final loaded = catalogue.firstWhere((n) => n['id'] == deck['id']);
      final prepared = await compute(
          buildPreparedInstallation, <String, dynamic>{
        'norm': loaded,
        'units': loaded['units'],
        'format': format,
        'deck': group
      });
      return addPreparedCards(
          (prepared['cards'] as List).map((v) => Json.from(v)).toList(),
          legacyIds: Set<String>.from(prepared['legacyIds']));
    }
    final asset = await rootBundle.load(deck['asset']);
    final bytes =
        asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes);
    final input = <String, dynamic>{'bytes': bytes, 'hash': deck['hash']};
    final prepared = bytes.length < 64000
        ? await Future<List<Json>>.sync(() => decodePreparedCards(input))
        : await compute(decodePreparedCards, input);
    final count = await addPreparedCards(prepared);
    if (deck['id'] != null) {
      data['installedDecks'] = {
        ...List<String>.from(data['installedDecks'] ?? []),
        deck['id']
      }.toList();
      await save();
    }
    return count;
  }

  Future<int> addPreparedCards(List<Json> prepared,
      {Set<String> legacyIds = const {}}) async {
    if (prepared.isEmpty) {
      throw StateError(
          'No hay fragmentos adecuados para este formato. Prueba Recuerdo literal.');
    }
    final previous = cards;
    final retired = previous
        .where((c) =>
            legacyIds.contains(c.id) &&
            c.revision == 1 &&
            !(data['remoteCardIds'] as Map? ?? {}).containsKey(c.id) &&
            c.editorialState == 'source_literal')
        .toList();
    final retiredIds = retired.map((c) => c.id).toSet();
    if (retired.isNotEmpty) {
      final archive = {
        for (final c in list('supersededPreparedCards')) c['id']: c
      };
      for (final c in retired) {
        archive[c.id] = c.toJson();
      }
      data['supersededPreparedCards'] = archive.values.toList();
      final session = data['session'];
      if (session is Map &&
          session['ids'] is List &&
          (session['ids'] as List).any(retiredIds.contains)) {
        data['session'] = null;
      }
    }
    final existing = previous.map((c) => c.id).toSet();
    final added = prepared.where((c) => !existing.contains(c['id'])).toList();
    data['cards'] = [
      ...previous
          .where((c) => !retiredIds.contains(c.id))
          .map((c) => c.toJson()),
      ...added
    ];
    await save();
    return added.length;
  }

  Json get profile => Json.from(data['profile'] ?? {});
  String get mode => profile['mode'] ?? 'Ambos';
  bool get dark => data['dark'] == true;
  List<StudyCard> get cards => (data['cards'] as List? ?? [])
      .map((v) => StudyCard.fromJson(Json.from(v)))
      .toList();
  List<Json> list(String key) =>
      (data[key] as List? ?? []).map((v) => Json.from(v)).toList();
  List<Json> get catalogue {
    final norms = {for (final n in initialCatalogue()) n['id']: n};
    for (final n in [...corpusNorms, ...bundledNorms, ...list('norms')]) {
      norms[n['id']] = {...?norms[n['id']], ...n};
    }
    for (final n in norms.values) {
      if ((n['bundledVersion'] == n['latestVersion'] ||
              loadedPackVersions[n['id']] == n['latestVersion']) &&
          bundledPacks[n['id']] != null) {
        n['units'] = bundledPacks[n['id']];
      }
    }
    return norms.values.toList();
  }

  Future<List<dynamic>> loadBundledPack(Json norm) async {
    final asset = await rootBundle.load(norm['bundledAsset']);
    final bytes =
        asset.buffer.asUint8List(asset.offsetInBytes, asset.lengthInBytes);
    final pack = await compute(decodeBundledPack, <String, dynamic>{
      'bytes': bytes,
      'hash': norm['bundledHash'],
      'version': norm['latestVersion']
    });
    final items = pack['items'] as List;
    rememberPack(norm, items);
    return items;
  }

  void rememberPack(Json norm, List<dynamic> items) {
    bundledPacks.remove(norm['id']);
    bundledPacks[norm['id']] = items;
    loadedPackVersions[norm['id']] = norm['latestVersion'];
    while (bundledPacks.length > 4) {
      final oldest = bundledPacks.keys.first;
      bundledPacks.remove(oldest);
      loadedPackVersions.remove(oldest);
    }
  }

  Json state(String id) => Json.from((data['states'] as Map? ?? {})[id] ?? {});
  List<StudyCard> due({String? deck, DateTime? at, bool includeRest = false}) {
    final now = at ?? DateTime.now();
    if (!includeRest && !isStudyDay(now, profile)) return [];
    final queue = cards.where((c) {
      final when = DateTime.tryParse(state(c.id)['dueAt'] ?? '');
      return !c.blocked &&
          (deck == null || c.deck == deck) &&
          (when == null || !when.isAfter(now));
    }).toList();
    queue.sort((a, b) {
      final sa = state(a.id), sb = state(b.id);
      if (sa.isEmpty != sb.isEmpty) return sa.isEmpty ? 1 : -1;
      final due = (sa['dueAt'] as String? ?? '')
          .compareTo(sb['dueAt'] as String? ?? '');
      if (due != 0) return due;
      final lapses =
          (sb['lapses'] as num? ?? 0).compareTo(sa['lapses'] as num? ?? 0);
      return lapses == 0 ? a.id.compareTo(b.id) : lapses;
    });
    return queue
        .take((profile['dailyGoal'] as num? ?? 20).toInt().clamp(1, 200))
        .toList();
  }

  Future<void> save() {
    final snapshot = jsonEncode(data);
    _write = _write.catchError((_) {}).then((_) async {
      await persistence.write(snapshot);
    });
    notifyListeners();
    return _write;
  }

  Future<void> setProfile(Json p) async {
    data['profile'] = {...profile, ...p};
    await save();
  }

  Json readingPosition(String normId, String unitId) {
    final positions = data['readerPositions'];
    final value =
        positions is Map ? positions[jsonEncode([normId, unitId])] : null;
    return value is Map ? Json.from(value) : {};
  }

  Future<void> rememberReading(
      Json norm, Json unit, Json version, int fragment) async {
    if (norm['latestVersion'] == null ||
        version['hash'] is! String ||
        (version['hash'] as String).isEmpty ||
        fragment < 0) {
      return;
    }
    data['readerPositions'] = {
      if (data['readerPositions'] is Map) ...data['readerPositions'],
      jsonEncode([norm['id'], unit['id']]): {
        'normId': norm['id'],
        'unitId': unit['id'],
        'normVersion': norm['latestVersion'],
        'unitVersionHash': version['hash'],
        'fragment': fragment,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
      }
    };
    data['lastReadUnits'] = {
      if (data['lastReadUnits'] is Map) ...data['lastReadUnits'],
      norm['id']: unit['id'],
    };
    await save();
  }

  Future<void> addCard(StudyCard c) async {
    data['cards'] = [...cards.map((v) => v.toJson()), c.toJson()];
    await save();
  }

  Future<void> editCard(StudyCard card, {required int expectedRevision}) async {
    final previous = cards.where((c) => c.id == card.id).firstOrNull;
    if (previous == null || previous.revision != expectedRevision) {
      throw StateError(
          'La tarjeta ha cambiado. Conserva el borrador y vuelve a abrirla.');
    }
    if (jsonEncode({...previous.toJson()}..remove('revision')) ==
        jsonEncode({...card.toJson()}..remove('revision'))) {
      return;
    }
    data['cardHistory'] = [
      ...list('cardHistory'),
      {
        ...previous.toJson(),
        'archivedAt': DateTime.now().toUtc().toIso8601String()
      }
    ];
    data['cards'] =
        cards.map((c) => c.id == card.id ? card.toJson() : c.toJson()).toList();
    await save();
  }

  Future<void> add(String key, Json value) async {
    data[key] = [...list(key), value];
    await save();
  }

  Future<void> toggle(String key, String id) async {
    final values = List<String>.from(data[key] ?? []);
    values.contains(id) ? values.remove(id) : values.add(id);
    data[key] = values;
    await save();
  }

  bool has(String key, String id) => (data[key] as List? ?? []).contains(id);
  Future<void> review(StudyCard card, int rating,
      {int latencyMs = 0, dynamic response}) async {
    final current = cards.where((c) => c.id == card.id).firstOrNull;
    if (current == null || current.revision != card.revision) {
      throw StateError('La tarjeta ha cambiado; abre una sesión nueva.');
    }
    if (current.blocked) {
      throw StateError('Tarjeta bloqueada por revisión normativa');
    }
    final at = DateTime.now().toUtc();
    final previous = state(card.id);
    final event = <String, dynamic>{
      'id': const Uuid().v4(),
      'cardId': card.id,
      'cardRevision': card.revision,
      'rating': rating,
      'occurredAt': at.toIso8601String(),
      'previous': previous,
      'latencyMs': latencyMs,
      'response': response,
      'algorithm': 'sm2-1'
    };
    data['states'] = {
      ...(data['states'] as Map? ?? {}),
      card.id: schedule(previous, rating, at)
    };
    data['reviews'] = [...list('reviews'), event];
    data['session'] = null;
    await save();
  }

  Future<void> undoLast() async {
    final events = list('reviews');
    if (events.isEmpty) return;
    final last = events.last;
    if (last['synced'] == true) {
      throw StateError(
          'La revisión sincronizada conserva su historial y no se puede deshacer.');
    }
    events.removeLast();
    data['reviews'] = events;
    data['states'] = {
      ...(data['states'] as Map? ?? {}),
      last['cardId']: last['previous']
    };
    await save();
  }

  Future<void> reset() async {
    data = {};
    bundledPacks.clear();
    await save();
  }

  Future<void> restore(String text) async {
    final parsed = jsonDecode(text);
    if (parsed is! Map ||
        parsed['schemaVersion'] != 1 ||
        parsed['data'] is! Map) {
      throw const FormatException('Copia incompatible');
    }
    final restored = Json.from(parsed['data']);
    for (final c in restored['cards'] as List? ?? []) {
      StudyCard.fromJson(Json.from(c));
    }
    // A local backup never restores server authentication.
    restored.remove('auth');
    restored.remove('remoteUserId');
    restored.remove('remoteCardIds');
    restored.remove('remoteCardRevisions');
    restored.remove('workspaceBase');
    data = restored;
    await save();
  }

  String export() => const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': 1,
        'exportedAt': DateTime.now().toUtc().toIso8601String(),
        'data': {...data}..remove('auth')
      });

  bool get hasRemoteServer {
    try {
      return Uri.parse(apiBase).scheme == 'https';
    } catch (_) {
      return false;
    }
  }

  String get apiBase {
    final base = (data['apiUrl'] as String? ??
            const String.fromEnvironment('LEXMEMORIA_API_URL'))
        .replaceAll(RegExp(r'/$'), '');
    final uri = Uri.tryParse(base);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.scheme != 'https' &&
            !(uri.scheme == 'http' &&
                ['10.0.2.2', 'localhost', '127.0.0.1'].contains(uri.host)))) {
      throw StateError(
          'Configura una API HTTPS válida en Perfil (HTTP solo para desarrollo local).');
    }
    return base;
  }

  Future<void> fetchCatalogue({bool nextPage = false}) async {
    if (syncing) return;
    final base = apiBase;
    final cursor = nextPage ? data['catalogueCursor'] as String? : null;
    if (nextPage && cursor == null) return;
    syncing = true;
    error = null;
    notifyListeners();
    try {
      final response = await client
          .get(Uri.parse('$base/v1/library/norms').replace(queryParameters: {
            'limit': '100',
            if (cursor != null) 'cursor': cursor
          }))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) {
        throw StateError('Servidor no disponible (${response.statusCode})');
      }
      final result = Json.from(jsonDecode(response.body));
      final norms = (result['items'] as List).map((n) => Json.from(n)).toList();
      await applyCatalogue(norms);
      data['catalogueCursor'] = result['nextCursor'];
      data['lastSync'] = DateTime.now().toUtc().toIso8601String();
      await save();
    } catch (e) {
      error = 'No se pudo sincronizar. Los datos locales se conservan. $e';
      rethrow;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Future<void> applyCatalogue(List<Json> norms) async {
    final old = {for (final n in list('norms')) n['id']: n};
    final changed = <String>{};
    for (final n in norms) {
      final before = old[n['id']];
      final update = <String, dynamic>{...?before, ...n};
      if (before != null &&
          before['latestVersion'] != null &&
          before['latestVersion'] != n['latestVersion']) {
        changed.add(n['id']);
        if (before['units'] != null || before['bundledReady'] == true) {
          data['archivedPacks'] = [...list('archivedPacks'), before];
        }
        update.remove('units');
        update.remove('downloadedAt');
        update['coverage'] = 'pending_download_after_change';
      }
      old[n['id']] = update;
      for (final c in cards) {
        if (c.normId == n['id'] &&
            c.versionId.isNotEmpty &&
            c.versionId != n['latestVersion']) {
          changed.add(c.normId);
        }
      }
    }
    data['norms'] = old.values.toList();
    data['cards'] = cards
        .map((c) => changed.contains(c.normId)
            ? {...c.toJson(), 'blocked': true, 'editorialState': 'pending'}
            : c.toJson())
        .toList();
    await save();
  }

  Future<void> downloadNorm(Json norm) async {
    if (norm['bundledAsset'] != null &&
        norm['bundledVersion'] == norm['latestVersion']) {
      await loadBundledPack(norm);
      final saved = {
        ...norm,
        'bundledReady': true,
        'downloadedAt': DateTime.now().toUtc().toIso8601String()
      }..remove('units');
      data['norms'] = [
        ...list('norms').where((n) => n['id'] != norm['id']),
        saved
      ];
      await save();
      return;
    }
    if (norm['packUrl'] != null) {
      await downloadCorpusNorm(norm);
      return;
    }
    final base = apiBase;
    final version = norm['latestVersion'];
    if (base.isEmpty || version == null) {
      throw StateError('Importa primero esta norma en el servidor.');
    }
    final uri = Uri.parse('$base/v1/library/norms/${norm['id']}/units')
        .replace(queryParameters: {'version': version});
    final r = await client.get(uri).timeout(const Duration(seconds: 45));
    if (r.statusCode != 200) {
      throw StateError('No se descargó el texto (${r.statusCode}). Reintenta.');
    }
    final payload = Json.from(jsonDecode(r.body));
    final rows = list('norms').where((n) => n['id'] != norm['id']).toList();
    rows.add({
      ...norm,
      'units': payload['items'],
      'downloadedAt': DateTime.now().toUtc().toIso8601String()
    });
    data['norms'] = rows;
    await save();
  }

  Future<bool> loadCachedNorm(Json norm) async {
    if (norm['packHash'] == null) return false;
    final bytes = await packCache.read(norm['packHash']);
    if (bytes == null) {
      if (norm['packReady'] == true) {
        data['norms'] = list('norms')
            .map((n) => n['id'] == norm['id'] ? {...n, 'packReady': false} : n)
            .toList();
        await save();
      }
      return false;
    }
    final pack = await compute(decodeBundledPack, <String, dynamic>{
      'bytes': bytes,
      'hash': norm['packHash'],
      'version': norm['latestVersion']
    });
    if (pack['norm']['id'] != norm['id']) {
      throw StateError('El paquete no corresponde a esta norma.');
    }
    rememberPack(norm, pack['items']);
    notifyListeners();
    return true;
  }

  Future<void> downloadCorpusNorm(Json norm) {
    final key = '${norm['id']}:${norm['packHash']}';
    return _packDownloads.putIfAbsent(
        key,
        () => _downloadCorpusNorm(norm).whenComplete(() {
              _packDownloads.remove(key);
            }));
  }

  Future<void> _downloadCorpusNorm(Json norm) async {
    final uri = Uri.parse(norm['packUrl']);
    if (uri.scheme != 'https' ||
        uri.host != 'raw.githubusercontent.com' ||
        !uri.path.startsWith('/AngelJRM01/LexMemoria/')) {
      throw StateError('Dirección de contenido no válida.');
    }
    if (loadedPackVersions[norm['id']] == norm['latestVersion'] &&
        bundledPacks[norm['id']] != null) {
      return;
    }
    try {
      if (await loadCachedNorm(norm)) return;
    } catch (_) {/* A verified redownload can repair public cache files. */}
    final expected = (norm['packBytes'] as num).toInt();
    if (expected <= 0 || expected > 64000000) {
      throw StateError('Paquete demasiado grande. Consulta la fuente oficial.');
    }
    final response = await client
        .send(http.Request('GET', uri))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError(
          'No se pudo descargar esta norma (${response.statusCode}). Tus datos se conservan.');
    }
    final builder = BytesBuilder(copy: false);
    var size = 0;
    await for (final chunk
        in response.stream.timeout(const Duration(seconds: 60))) {
      size += chunk.length;
      if (size > expected) {
        throw StateError('El tamaño del paquete no coincide.');
      }
      builder.add(chunk);
    }
    if (size != expected) throw StateError('Descarga incompleta. Reinténtalo.');
    final bytes = builder.takeBytes();
    final pack = await compute(decodeBundledPack, <String, dynamic>{
      'bytes': bytes,
      'hash': norm['packHash'],
      'version': norm['latestVersion']
    });
    if (pack['norm']['id'] != norm['id']) {
      throw StateError('El paquete no corresponde a esta norma.');
    }
    await packCache.write(norm['packHash'], bytes);
    final current = catalogue.where((n) => n['id'] == norm['id']).firstOrNull;
    if (current != null && current['latestVersion'] != norm['latestVersion']) {
      throw StateError(
          'La norma ha cambiado durante la descarga. Vuelve a abrirla para cargar la nueva versión.');
    }
    rememberPack(norm, pack['items']);
    final saved = {
      ...norm,
      'packReady': packCache.persistent,
      'downloadedAt': DateTime.now().toUtc().toIso8601String()
    }..remove('units');
    data['norms'] = [
      ...list('norms').where((n) => n['id'] != norm['id']),
      saved
    ];
    await save();
  }

  Future<void> fetchUpdates({bool nextPage = false}) async {
    final cursor = nextPage ? data['updatesCursor'] as String? : null;
    if (nextPage && cursor == null) return;
    final response = await client
        .get(Uri.parse('$apiBase/v1/legal-updates').replace(queryParameters: {
          'limit': '50',
          if (cursor != null) 'cursor': cursor,
        }))
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw StateError(
          'No se han descargado novedades (${response.statusCode}). Los avisos anteriores se conservan.');
    }
    final result = Json.from(jsonDecode(response.body));
    final items = (result['items'] as List).map((v) => Json.from(v));
    final merged = {
      for (final event in list('legalUpdates')) event['id']: event
    };
    for (final event in items) {
      merged[event['id']] = event;
    }
    data['legalUpdates'] = merged.values.toList();
    data['updatesCursor'] = result['nextCursor'];
    data['lastUpdatesSync'] = DateTime.now().toUtc().toIso8601String();
    await save();
  }

  @override
  void dispose() {
    client.close();
    persistence.close();
    super.dispose();
  }
}

/// Decode outside the UI isolate on native platforms. Verification precedes parsing.
Json decodeBundledPack(Json input) {
  final bytes = input['bytes'] as List<int>;
  if (sha256.convert(bytes).toString() != input['hash']) {
    throw StateError(
        'El paquete jurídico no supera la comprobación de integridad.');
  }
  final decoded = GZipDecoder().decodeBytes(bytes);
  if (decoded.length > 256000000) throw StateError('Paquete demasiado grande.');
  final pack = Json.from(jsonDecode(utf8.decode(decoded)));
  if (pack['schemaVersion'] != 1 ||
      pack['norm']['latestVersion'] != input['version']) {
    throw StateError('Versión de paquete incompatible.');
  }
  return pack;
}

List<Json> decodeCorpusCatalogue(Uint8List bytes) {
  final decoded = GZipDecoder().decodeBytes(bytes);
  if (decoded.length > 32000000) throw StateError('Catálogo demasiado grande.');
  final result = Json.from(jsonDecode(utf8.decode(decoded)));
  final items = (result['items'] as List).map((v) => Json.from(v)).toList();
  if (result['schemaVersion'] != 1 ||
      result['norms'] != items.length ||
      items.map((n) => n['id']).toSet().length != items.length) {
    throw StateError('Catálogo incompleto.');
  }
  for (final norm in items) {
    norm['short'] = friendlyNormLabel(norm);
  }
  return items;
}

List<Json> decodePreparedCards(Json input) {
  final bytes = input['bytes'] as List<int>;
  if (sha256.convert(bytes).toString() != input['hash']) {
    throw StateError('No se ha podido verificar el mazo preparado.');
  }
  final decoded = GZipDecoder().decodeBytes(bytes);
  if (decoded.length > 32000000) throw StateError('Mazo demasiado grande.');
  final pack = Json.from(jsonDecode(utf8.decode(decoded)));
  return (pack['cards'] as List)
      .map((c) => StudyCard.fromJson(Json.from(c)).toJson())
      .toList();
}
