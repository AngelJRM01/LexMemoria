import 'dart:convert';
import 'dart:typed_data';
import 'package:collection/collection.dart';
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
import 'legal_units.dart';
import 'pack_cache.dart';
import 'catalogue.dart';
import 'backup.dart';

String encodeStudySnapshot(Json snapshot) => jsonEncode(snapshot);

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
  void syncStatusChanged() => notifyListeners();
  bool syncing = false;
  Future<void> _write = Future.value();
  int _writeGeneration = 0;
  int _progressGeneration = 0;
  int _legacyDataGeneration = 0;
  int get legacyDataGeneration => _legacyDataGeneration;
  int get progressGeneration => _progressGeneration;
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
      final european = Json.from(
          jsonDecode(await rootBundle.loadString('assets/europe/index.json')));
      store.bundledNorms.addAll((european['items'] as List).map((v) =>
          <String, dynamic>{
            ...Json.from(v),
            'bundledVersion': v['latestVersion']
          }));
      // Reading packs open on demand; never decompress several laws before the home screen.
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
    await retireIncompleteLiteralTemplates();
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

  /// Quarantine incomplete old generated prompts without losing review history.
  Future<void> retireIncompleteLiteralTemplates() async {
    if (data['literalTemplateReview'] == 1) return;
    await _commitMutation(() {
      final remote = data['remoteCardIds'] as Map? ?? {};
      final retired = cards
          .where((c) =>
              c.type == 'qa' &&
              c.revision == 1 &&
              c.editorialState == 'source_literal' &&
              !remote.containsKey(c.id) &&
              c.front.startsWith('Completa de memoria esta regla de ') &&
              !safeStudyPassage(c.back))
          .toList();
      final ids = retired.map((c) => c.id).toSet();
      final archive = {
        for (final c in list('supersededPreparedCards')) c['id']: c
      };
      for (final c in retired) {
        archive[c.id] = c.toJson();
      }
      final session = data['session'];
      final invalidSession = session is Map &&
          session['ids'] is List &&
          (session['ids'] as List).any(ids.contains);
      return {
        ...data,
        'literalTemplateReview': 1,
        'cards': cards
            .where((c) => !ids.contains(c.id))
            .map((c) => c.toJson())
            .toList(),
        'supersededPreparedCards': archive.values.toList(),
        if (invalidSession) 'session': null
      };
    });
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
        ? await Future<Json>.sync(() => decodePreparedInstallation(input))
        : await compute(decodePreparedInstallation, input);
    final count = await addPreparedCards(
        (prepared['cards'] as List).map((c) => Json.from(c)).toList(),
        legacyIds: Set<String>.from(prepared['legacyIds']));
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
    final replacements = {for (final c in prepared) c['id']: c};
    final existing = previous.map((c) => c.id).toSet();
    final added = prepared.where((c) => !existing.contains(c['id'])).toList();
    data['cards'] = [
      ...previous.where((c) => !retiredIds.contains(c.id)).map((c) {
        final next = replacements[c.id];
        // Refresh wording/options only for unchanged local source templates.
        // Identity and review states stay stable; personal/cloud edits win.
        if (next != null &&
            c.revision == 1 &&
            c.editorialState == 'source_literal' &&
            !(data['remoteCardIds'] as Map? ?? {}).containsKey(c.id) &&
            c.normId == next['normId'] &&
            c.unitId == next['unitId'] &&
            c.versionId == next['versionId'] &&
            c.unitVersionHash == next['unitVersionHash'] &&
            c.type == next['type'] &&
            c.back == next['back']) {
          return {
            ...c.toJson(),
            'front': next['front'],
            'explanation': next['explanation'],
            'options': next['options'],
            'correct': next['correct']
          };
        }
        return c.toJson();
      }),
      ...added
    ];
    await save();
    return added.length;
  }

  Json get profile => Json.from(data['profile'] ?? {});
  String get mode => profile['mode'] ?? 'Ambos';
  bool get dark =>
      profile['theme'] == 'dark' ||
      (profile['theme'] == null && data['dark'] == true);
  Object? _policyCorpus, _policyBundled;
  Map<String, Json> _publishedSources = {};
  Map<String, Set<String>> _sourceReviewUnits = {};
  Map<String, Json> get publishedSources {
    if (!identical(_policyCorpus, corpusNorms) ||
        !identical(_policyBundled, bundledNorms)) {
      _publishedSources = {};
      for (final n in [...corpusNorms, ...bundledNorms]) {
        _publishedSources[n['id']] = {...?_publishedSources[n['id']], ...n};
      }
      _sourceReviewUnits = {
        for (final n in _publishedSources.values)
          n['id']: Set<String>.from(n['studyReviewUnitIds'] ?? [])
      };
      _policyCorpus = corpusNorms;
      _policyBundled = bundledNorms;
      _cardCache = null;
    }
    return _publishedSources;
  }

  List<StudyCard> get cards {
    final published = publishedSources;
    if (_cardCache == null ||
        !identical(_cardSource, data['cards']) ||
        !identical(_cardSourceNorms, data['norms'])) {
      _cardSource = data['cards'];
      _cardSourceNorms = data['norms'];
      final localSources = {for (final n in list('norms')) n['id']: n};
      _cardCache = (data['cards'] as List? ?? []).map((v) {
        final card = StudyCard.fromJson(Json.from(v));
        final source = published[card.normId];
        if (source != null &&
            !card.blocked &&
            card.revision == 1 &&
            card.editorialState == 'source_literal') {
          final local = localSources[card.normId];
          String stamp(dynamic v) =>
              v is String ? v.replaceAll(RegExp(r'[^0-9]'), '') : '';
          final newerLocal = local != null &&
              stamp(local['sourceUpdatedAt'])
                      .compareTo(stamp(source['sourceUpdatedAt'])) >
                  0;
          final currentSource = newerLocal ? local : source;
          final changed = card.versionId.isNotEmpty &&
              card.versionId != currentSource['latestVersion'] &&
              currentSource['sourceUpdatedAt'] != null;
          final contextual = card.versionId == source['latestVersion'] &&
              (_sourceReviewUnits[card.normId]?.contains(card.unitId) ?? false);
          if (changed || contextual) {
            return StudyCard.fromJson({
              ...card.toJson(),
              'blocked': true,
              'editorialState':
                  changed ? 'pending_source_update' : 'pending_legal_context'
            });
          }
        }
        return card;
      }).toList();
    }
    return _cardCache!;
  }

  List<Json> list(String key) =>
      (data[key] as List? ?? []).map((v) => Json.from(v)).toList();
  List<Json>? _catalogueCache;
  Object? _catalogueLocal, _catalogueCorpus, _catalogueBundled;
  int _packGeneration = 0, _cataloguePackGeneration = -1;
  List<StudyCard>? _cardCache;
  Object? _cardSource;
  Object? _cardSourceNorms;
  List<Json> get catalogue {
    if (_catalogueCache == null ||
        !identical(_catalogueLocal, data['norms']) ||
        !identical(_catalogueCorpus, corpusNorms) ||
        !identical(_catalogueBundled, bundledNorms) ||
        _cataloguePackGeneration != _packGeneration) {
      _catalogueCache = _buildCatalogue();
      _catalogueLocal = data['norms'];
      _catalogueCorpus = corpusNorms;
      _catalogueBundled = bundledNorms;
      _cataloguePackGeneration = _packGeneration;
    }
    return _catalogueCache!;
  }

  List<Json> _buildCatalogue() {
    final norms = {for (final n in initialCatalogue()) n['id']: n};
    for (final n in [...corpusNorms, ...bundledNorms]) {
      norms[n['id']] = {...?norms[n['id']], ...n};
    }
    for (final local in list('norms')) {
      final source = publishedSources[local['id']];
      String stamp(dynamic value) =>
          value is String ? value.replaceAll(RegExp(r'[^0-9]'), '') : '';
      final adopt = source != null &&
          source['latestVersion'] != local['latestVersion'] &&
          stamp(source['sourceUpdatedAt']).isNotEmpty &&
          stamp(source['sourceUpdatedAt'])
                  .compareTo(stamp(local['sourceUpdatedAt'])) >=
              0;
      if (adopt) {
        norms[local['id']] = {
          ...local,
          ...source,
          'packReady': false,
          'coverage': 'pending_download_after_change'
        }..remove('units');
      } else {
        norms[local['id']] = {...?norms[local['id']], ...local};
      }
    }
    for (final n in norms.values) {
      if (loadedPackVersions[n['id']] == n['latestVersion'] &&
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
    _packGeneration++;
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
  List<StudyCard>? _deckIndexSource;
  Map<String, List<StudyCard>> _deckIndex = {};
  Map<String, StudyCard> _cardIdIndex = {};
  void _ensureCardIndexes() {
    final all = cards;
    if (!identical(all, _deckIndexSource)) {
      final grouped = <String, List<StudyCard>>{};
      final byId = <String, StudyCard>{};
      for (final card in all) {
        (grouped[card.deck] ??= []).add(card);
        byId.putIfAbsent(card.id, () => card);
      }
      _deckIndex = grouped;
      _cardIdIndex = byId;
      _deckIndexSource = all;
    }
  }

  StudyCard? cardById(String id) {
    _ensureCardIndexes();
    return _cardIdIndex[id];
  }

  Iterable<StudyCard> _cardsInDeck(String? deck) {
    if (deck == null) return cards;
    _ensureCardIndexes();
    return _deckIndex[deck] ?? const <StudyCard>[];
  }

  Object? _todayReviewSource;
  String? _todayReviewDate;
  Duration? _todayReviewOffset;
  int _todayReviewLegacy = -1, _todayReviewCount = 0;
  int reviewCountOn(DateTime day) {
    final events = data['reviews'];
    final date = civilDate(day);
    final offset = DateTime.now().timeZoneOffset;
    if (identical(events, _todayReviewSource) &&
        date == _todayReviewDate &&
        offset == _todayReviewOffset &&
        _todayReviewLegacy == _legacyDataGeneration) {
      return _todayReviewCount;
    }
    var count = 0;
    for (final event in events is List ? events : const []) {
      final stamp = DateTime.tryParse(event['occurredAt']?.toString() ?? '');
      if (stamp != null && civilDate(stamp.toLocal()) == date) count++;
    }
    _todayReviewSource = events;
    _todayReviewDate = date;
    _todayReviewOffset = offset;
    _todayReviewLegacy = _legacyDataGeneration;
    return _todayReviewCount = count;
  }

  List<StudyCard> due({String? deck, DateTime? at, bool includeRest = false}) {
    final now = at ?? DateTime.now();
    if (!includeRest && !isStudyDay(now, profile)) return [];
    final settings = profile;
    final allStates = data['states'] as Map? ?? const {};
    Map stateFor(String id) =>
        allStates[id] is Map ? allStates[id] as Map : const {};
    final priorities = settings['deckPriorities'] as Map? ?? const {};
    final preferred =
        (settings['preferredExerciseTypes'] as List? ?? const []).toSet();
    int compare(StudyCard a, StudyCard b) {
      final sa = stateFor(a.id), sb = stateFor(b.id);
      if (sa.isEmpty != sb.isEmpty) return sa.isEmpty ? 1 : -1;
      if (sa.isEmpty && sb.isEmpty) {
        final priority = ((priorities[b.deck] as num?) ?? 0)
            .compareTo((priorities[a.deck] as num?) ?? 0);
        if (priority != 0) return priority;
        if (preferred.contains(a.type) != preferred.contains(b.type)) {
          return preferred.contains(a.type) ? -1 : 1;
        }
      }
      final due = (sa['dueAt'] as String? ?? '')
          .compareTo(sb['dueAt'] as String? ?? '');
      if (due != 0) return due;
      final lapses =
          (sb['lapses'] as num? ?? 0).compareTo(sa['lapses'] as num? ?? 0);
      return lapses == 0 ? a.id.compareTo(b.id) : lapses;
    }

    final capacity = studyCapacity(settings);
    // Keep only the next session instead of sorting the entire collection.
    final selected = HeapPriorityQueue<StudyCard>((a, b) => compare(b, a));
    for (final card in _cardsInDeck(deck)) {
      if (card.blocked) continue;
      final dueAt = stateFor(card.id)['dueAt'];
      final when =
          dueAt == null || dueAt == '' ? null : DateTime.tryParse(dueAt);
      if (when != null && when.isAfter(now)) continue;
      if (selected.length < capacity) {
        selected.add(card);
      } else if (compare(card, selected.first) < 0) {
        selected.removeFirst();
        selected.add(card);
      }
    }
    return selected.toList()..sort(compare);
  }

  Future<void> save() {
    final snapshot = jsonEncode(data);
    _writeGeneration++;
    _progressGeneration++;
    _legacyDataGeneration++;
    _cardCache = null;
    _catalogueCache = null;
    _write = _write.catchError((_) {}).then((_) async {
      await persistence.write(snapshot);
    });
    notifyListeners();
    return _write;
  }

  Future<void> setProfile(Json p) async {
    await _commitMutation(() => {
          ...data,
          'profile': {...profile, ...p}
        });
  }

  Future<void> providerDeletionMarker(String? subject,
          {String? owner, String? server}) =>
      _commitMutation(() => {
            ...data,
            'providerDeletionSubject': subject,
            'providerDeletionOwner': subject == null ? null : owner,
            'providerDeletionServer': subject == null ? null : server,
          });

  Future<void> setSyncQueue(Json value) => _commitMutation(() {
        if (value['userId'] != data['remoteUserId'] ||
            value['server'] != apiBase) {
          throw StateError('La cuenta cambió durante la sincronización.');
        }
        return {...data, 'syncOutbox': value};
      });

  Future<void> acknowledgeProgressVersion(
          dynamic version, String owner, String server) =>
      _commitMutation(() {
        if (data['remoteUserId'] != owner || apiBase != server) {
          throw StateError('La cuenta cambió.');
        }
        return {...data, 'serverProgressVersion': version};
      });

  Future<void> setAutoSync(bool enabled) => _commitMutation(() => {
        ...data,
        'autoSyncConsent': enabled
            ? {
                'userId': data['remoteUserId'],
                'server': apiBase,
                'mode': 'bidirectional-v1'
              }
            : null,
      });

  Future<void> setAutoWorkspace(bool enabled) => _commitMutation(() => {
        ...data,
        'autoWorkspaceConsent': enabled
            ? {'userId': data['remoteUserId'], 'server': apiBase}
            : null,
      });

  Future<void> setWorkspaceQueue(Json value) => _commitMutation(() {
        if (value['userId'] != data['remoteUserId'] ||
            value['server'] != apiBase) {
          throw StateError('La cuenta cambió.');
        }
        return {...data, 'workspaceOutbox': value};
      });

  Future<void> commitAccountProfile(Json expected, Json value, int revision,
          String owner, String server) =>
      _commitMutation(() {
        if (data['remoteUserId'] != owner ||
            apiBase != server ||
            jsonEncode(profile['account'] ?? {}) != jsonEncode(expected)) {
          throw StateError(
              'Tu perfil o la cuenta cambió. Se conserva la edición local.');
        }
        return {
          ...data,
          'profile': {...profile, 'account': value, 'theme': value['theme']},
          'accountProfileBase': value,
          'accountProfileRevision': revision
        };
      });

  Future<void> commitConflictFork(
          String id,
          Json expected,
          StudyCard remote,
          List<Json> remoteHistory,
          List<Json> remoteEvents,
          Json? remoteState,
          String owner,
          String server) =>
      _commitMutation(() {
        if (data['remoteUserId'] != owner || apiBase != server) {
          throw StateError('La cuenta cambió; el conflicto se conserva.');
        }
        final current = cardById(id);
        if (current == null ||
            jsonEncode(current.toJson()) != jsonEncode(expected)) {
          throw StateError('La tarjeta cambió. Vuelve a comparar.');
        }
        final forkId = const Uuid().v4();
        final localHistory = list('cardHistory')
            .where((h) =>
                h['id'] == id && (h['revision'] as int) < current.revision)
            .toList();
        for (var revision = 1; revision < current.revision; revision++) {
          if (!localHistory.any((h) => h['revision'] == revision)) {
            throw StateError(
                'Falta una revisión local; guarda una copia antes de resolver.');
          }
        }
        final eventConflicts = list('syncConflicts')
            .where((c) => c['cardId'] == id && c['kind'] == 'review_event')
            .map((c) => c['eventId'])
            .toSet();
        final pending = list('reviews')
            .where((e) =>
                e['cardId'] == id &&
                (e['syncedUserId'] != owner ||
                    eventConflicts.contains(e['id'])))
            .toList()
          ..sort((a, b) =>
              a['occurredAt'].toString().compareTo(b['occurredAt'].toString()));
        Json forkState = {};
        final forkEvents = <Json>[];
        for (final event in pending) {
          forkEvents.add({
            ...event,
            'id': const Uuid().v4(),
            'cardId': forkId,
            'synced': false,
            'syncedUserId': null,
            'previous': forkState
          });
          forkState = schedule(
              forkState, event['rating'], DateTime.parse(event['occurredAt']));
        }
        final conflict = list('syncConflicts')
            .where((c) => c['cardId'] == id && c['kind'] == 'card_content')
            .firstOrNull;
        final fork = {
          ...current.toJson(),
          'id': forkId,
          'deck': '${current.deck} · versión local',
          'blocked': conflict?['local']?['blocked'] ?? current.blocked,
          'editorialState': 'user'
        };
        return {
          ...data,
          'cards': [
            ...cards.where((c) => c.id != id).map((c) => c.toJson()),
            remote.toJson(),
            fork
          ],
          'cardHistory': [
            ...list('cardHistory').where((h) => h['id'] != id),
            ...remoteHistory,
            ...localHistory
                .map((h) => {...h, 'id': forkId, 'deck': fork['deck']})
          ],
          'reviews': [
            ...list('reviews').where((e) => e['cardId'] != id),
            ...remoteEvents,
            ...forkEvents
          ],
          'states': {
            ...Json.from(data['states'] ?? {}),
            id: remoteState ?? {},
            forkId: forkState
          },
          'conflictArchive': [
            ...list('conflictArchive'),
            {
              'at': DateTime.now().toUtc().toIso8601String(),
              'cardId': id,
              'local': current.toJson(),
              'localState': state(id),
              'pendingReviews': pending,
              'forkId': forkId
            }
          ],
          'syncConflicts':
              list('syncConflicts').where((c) => c['cardId'] != id).toList(),
          'syncOutbox': null,
          'session': null,
        };
      });

  Future<void> commitRemotePull(
          String expected, Json changes, String owner, String server) =>
      _commitMutation(() {
        if (data['remoteUserId'] != owner ||
            apiBase != server ||
            jsonEncode(data) != expected) {
          throw StateError(
              'Tus datos o la cuenta cambiaron durante la descarga. Se conservan; vuelve a comparar.');
        }
        return {...data, ...changes};
      });

  Future<void> commitWorkspace(Json expected, Json chosen, dynamic base,
          String? owner, String server,
          {int? revision}) =>
      _commitMutation(() {
        if (data['remoteUserId'] != owner || apiBase != server) {
          throw StateError('La cuenta cambió. Se conserva el espacio local.');
        }
        for (final key in expected.keys) {
          final fallback = expected[key] is List
              ? []
              : expected[key] is Map
                  ? {}
                  : null;
          final current = key == 'profile'
              ? (Json.from(profile)
                ..remove('account')
                ..remove('theme'))
              : data[key] ?? fallback;
          if (jsonEncode(canonicalJsonValue(current)) !=
              jsonEncode(canonicalJsonValue(expected[key]))) {
            throw StateError(
                'Tus datos han cambiado durante la sincronización. Vuelve a comparar; no se han sobrescrito.');
          }
        }
        return {
          ...data,
          for (final key in expected.keys)
            if (key != 'profile') key: chosen[key],
          'profile': {
            ...Json.from(chosen['profile'] ?? {}),
            if (profile.containsKey('account')) 'account': profile['account'],
            if (profile.containsKey('theme')) 'theme': profile['theme']
          },
          'workspaceHistory': [
            ...list('workspaceHistory'),
            {'at': DateTime.now().toUtc().toIso8601String(), 'data': expected}
          ],
          'workspaceBase': base,
          if (revision != null) 'workspaceRevision': revision,
          'workspaceOutbox': null,
          'lastWorkspaceSync': DateTime.now().toUtc().toIso8601String()
        };
      });

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

  Json _europeanSourceChange(Json norm) {
    if (norm['id'] is! String || !(norm['id'] as String).startsWith('EU-')) {
      throw StateError('Identificador europeo incompatible.');
    }
    final old = list('norms').where((n) => n['id'] == norm['id']).firstOrNull;
    final merged = <String, dynamic>{...?old, ...norm};
    final changed =
        old != null && old['latestVersion'] != norm['latestVersion'];
    if (changed) {
      for (final key in [
        'units',
        'bundledReady',
        'packReady',
        'europeanOffline'
      ]) {
        merged.remove(key);
      }
      if (!norm.containsKey('downloadedAt')) merged.remove('downloadedAt');
    }
    return {
      ...data,
      'norms': [...list('norms').where((n) => n['id'] != norm['id']), merged],
      if (changed && old['units'] is List)
        'archivedPacks': [...list('archivedPacks'), old]
    };
  }

  Future<void> rememberEuropeanReading(
          Json norm, String unitId, String hash, int offset) =>
      _commitMutation(() => {
            ..._europeanSourceChange(norm),
            'readerPositions': {
              if (data['readerPositions'] is Map) ...data['readerPositions'],
              jsonEncode([norm['id'], unitId]): {
                'normId': norm['id'],
                'unitId': unitId,
                'normVersion': norm['latestVersion'],
                'unitVersionHash': hash,
                'fragment': offset,
                'updatedAt': DateTime.now().toUtc().toIso8601String()
              },
            },
            'lastReadUnits': {
              if (data['lastReadUnits'] is Map) ...data['lastReadUnits'],
              norm['id']: unitId
            },
          });

  Future<void> saveEuropeanNorm(Json norm) =>
      _commitMutation(() => _europeanSourceChange(norm));

  Future<void> addCard(StudyCard c) async {
    await _commitMutation(() => {
          ...data,
          'cards': [...cards.map((v) => v.toJson()), c.toJson()]
        });
  }

  Future<void> editCard(StudyCard card, {required int expectedRevision}) async {
    await _commitMutation(() {
      final previous = cardById(card.id);
      if (previous == null || previous.revision != expectedRevision) {
        throw StateError(
            'La tarjeta ha cambiado. Conserva el borrador y vuelve a abrirla.');
      }
      if (jsonEncode({...previous.toJson()}..remove('revision')) ==
          jsonEncode({...card.toJson()}..remove('revision'))) {
        return data;
      }
      return {
        ...data,
        'cardHistory': [
          ...list('cardHistory'),
          {
            ...previous.toJson(),
            'archivedAt': DateTime.now().toUtc().toIso8601String()
          }
        ],
        'cards': cards
            .map((c) => c.id == card.id ? card.toJson() : c.toJson())
            .toList()
      };
    });
  }

  Future<void> updateCourse(Json course, {required Json expected}) =>
      _commitMutation(() {
        final courses = list('courses');
        final index = courses.indexWhere((c) => c['id'] == expected['id']);
        if (index < 0 ||
            course['id'] != expected['id'] ||
            jsonEncode(canonicalJsonValue(courses[index])) !=
                jsonEncode(canonicalJsonValue(expected))) {
          throw StateError(
              'La asignatura cambió mientras la editabas. Se conserva su estado; vuelve a comparar.');
        }
        courses[index] = course;
        return {...data, 'courses': courses};
      });

  Future<void> updateNote(String key, String value,
          {required String? expected}) =>
      _commitMutation(() {
        final notes = Json.from(data['notes'] ?? {});
        if (notes[key] != expected) {
          throw StateError(
              'La nota cambió mientras la editabas. Conserva tu texto y vuelve a comparar.');
        }
        return {
          ...data,
          'notes': {...notes, key: value}
        };
      });

  Future<void> updateExam(Json? value, {required dynamic expected}) =>
      _commitMutation(() {
        if (jsonEncode(canonicalJsonValue(data['activeExam'])) !=
            jsonEncode(canonicalJsonValue(expected))) {
          throw StateError(
              'El simulacro cambió en otro dispositivo. Se conserva su estado; vuelve a consultarlo.');
        }
        return {
          ...data,
          'activeExam': value,
          if (value?['result'] != null)
            'examHistory': [
              ...list('examHistory').where((e) => e['id'] != value!['id']),
              value
            ]
        };
      });

  Future<void> add(String key, Json value) async {
    await _commitMutation(() => {
          ...data,
          key: [...list(key), value]
        });
  }

  Future<void> toggle(String key, String id) async {
    await _commitMutation(() {
      final values = List<String>.from(data[key] ?? []);
      values.contains(id) ? values.remove(id) : values.add(id);
      return {...data, key: values};
    });
  }

  bool has(String key, String id) => (data[key] as List? ?? []).contains(id);
  Future<void> review(StudyCard card, int rating,
      {int latencyMs = 0,
      dynamic response,
      List<String>? sessionIds,
      int? nextIndex}) async {
    if ((sessionIds == null) != (nextIndex == null) ||
        (sessionIds != null &&
            (nextIndex! < 1 ||
                nextIndex > sessionIds.length ||
                sessionIds[nextIndex - 1] != card.id))) {
      throw ArgumentError('Continuación de sesión incoherente');
    }
    await _commitMutation(() {
      final current = cardById(card.id);
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
      return {
        ...data,
        'states': {
          ...(data['states'] as Map? ?? {}),
          card.id: schedule(previous, rating, at)
        },
        'reviews': [...list('reviews'), event],
        'session': sessionIds == null
            ? null
            : {'ids': List<String>.of(sessionIds), 'index': nextIndex}
      };
    });
  }

  Future<void> undoLast() async {
    await _commitMutation(() {
      final events = list('reviews');
      if (events.isEmpty) return data;
      final last = events.last;
      if (last['synced'] == true) {
        throw StateError(
            'La revisión sincronizada conserva su historial y no se puede deshacer.');
      }
      events.removeLast();
      return {
        ...data,
        'reviews': events,
        'states': {
          ...(data['states'] as Map? ?? {}),
          last['cardId']: last['previous']
        }
      };
    });
  }

  Future<void> reset() async {
    await _replaceSnapshot({});
    bundledPacks.clear();
    _packGeneration++;
  }

  Future<void> _replaceSnapshot(Json replacement) {
    final before = jsonEncode(data);
    final expected = _writeGeneration;
    return _commitMutation(() {
      if (_writeGeneration != expected || jsonEncode(data) != before) {
        throw StateError('Tus datos han cambiado. Repite la operación.');
      }
      return replacement;
    });
  }

  Future<void> _commitMutation(Json Function() mutate) {
    final operation = _write.catchError((_) {}).then((_) async {
      final previousData = data;
      final before = jsonEncode(data);
      final expected = _writeGeneration;
      // Compute against the latest committed state, not the state from when a
      // second click queued the operation. Sequential edits must not lose data.
      final candidate = mutate();
      // Freeze changed fields before any async work, so caller-owned maps
      // cannot diverge from the bytes eventually written to disk.
      final changed = <String, dynamic>{
        for (final entry in candidate.entries)
          if (!previousData.containsKey(entry.key) ||
              !identical(entry.value, previousData[entry.key]))
            entry.key: entry.value
      };
      final committed = <String, dynamic>{
        ...candidate,
        ...Json.from(jsonDecode(jsonEncode(changed)))
      };
      // Large snapshots encode outside the native UI isolate. The synchronous
      // final comparison remains necessary to catch legacy raw mutations.
      final encoded = before.length > 512 * 1024
          ? await compute(encodeStudySnapshot, committed)
          : encodeStudySnapshot(committed);
      await persistence.write(encoded);
      if (_writeGeneration != expected || jsonEncode(data) != before) {
        await persistence.write(jsonEncode(data));
        throw StateError('Tus datos han cambiado. La sustitución se canceló.');
      }
      if (['cards', 'cardHistory', 'reviews']
          .any((key) => !identical(candidate[key], previousData[key]))) {
        _progressGeneration++;
      }
      data = committed;
      _writeGeneration++;
      notifyListeners();
    });
    _write = operation;
    return operation;
  }

  Future<void> restore(String text) async {
    final restored = decodeStudyBackup(text);
    final previous = Json.from(jsonDecode(jsonEncode(data)))
      ..remove('restoreCheckpoint')
      ..remove('auth');
    // One recoverable checkpoint, rather than recursively nested full backups.
    restored['restoreCheckpoint'] = {
      'at': DateTime.now().toUtc().toIso8601String(),
      'data': previous
    };
    await _replaceSnapshot(restored);
  }

  Future<void> recoverBeforeRestore() async {
    final checkpoint = data['restoreCheckpoint'];
    if (checkpoint is! Map || checkpoint['data'] is! Map) {
      throw StateError('No hay una copia anterior a la restauración.');
    }
    await restore(jsonEncode({'schemaVersion': 1, 'data': checkpoint['data']}));
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
  for (final unit in pack['items'] as List) {
    for (final version in unit['versions'] as List) {
      version['bodyText'] = legalBodyText(version);
      version['editorialNotes'] = legalEditorialNotes(version);
      version['bodyParser'] = 'boe-editorial-2';
    }
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

List<Json> decodePreparedCards(Json input) =>
    (decodePreparedInstallation(input)['cards'] as List)
        .map((c) => Json.from(c))
        .toList();

Json decodePreparedInstallation(Json input) {
  final bytes = input['bytes'] as List<int>;
  if (sha256.convert(bytes).toString() != input['hash']) {
    throw StateError('No se ha podido verificar el mazo preparado.');
  }
  final decoded = GZipDecoder().decodeBytes(bytes);
  if (decoded.length > 32000000) throw StateError('Mazo demasiado grande.');
  final pack = Json.from(jsonDecode(utf8.decode(decoded)));
  return {
    'cards': (pack['cards'] as List)
        .map((c) => StudyCard.fromJson(Json.from(c)).toJson())
        .toList(),
    'legacyIds': pack['legacyIds'] ?? []
  };
}
