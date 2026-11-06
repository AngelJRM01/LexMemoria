import 'dart:convert';
import 'package:flutter/material.dart';
import 'models.dart';
import 'store.dart';
import 'remote.dart';
import 'widgets.dart' hide Badge;

const workspaceKeys = [
  'profile',
  'notes',
  'courses',
  'follows',
  'bookmarks',
  'favoriteCards',
  'readerPositions',
  'examHistory',
  'activeExam'
];
Json studyProfile(Json profile) => Json.from(profile)
  ..remove('account')
  ..remove('theme');
Json localWorkspace(AppStore store) => {
      'profile': studyProfile(store.profile),
      'notes': store.data['notes'] ?? {},
      'courses': store.data['courses'] ?? [],
      'follows': store.data['follows'] ?? [],
      'bookmarks': store.data['bookmarks'] ?? [],
      'favoriteCards': store.data['favoriteCards'] ?? [],
      'readerPositions': store.data['readerPositions'] ?? {},
      'examHistory': store.data['examHistory'] ?? [],
      'activeExam': store.data['activeExam'],
    };
Json normalizedWorkspace(Json value) => {
      ...value,
      'profile': studyProfile(Json.from(value['profile'] ?? {})),
      'notes': value['notes'] ?? {},
      'courses': value['courses'] ?? [],
      'follows': value['follows'] ?? [],
      'bookmarks': value['bookmarks'] ?? [],
      'favoriteCards': value['favoriteCards'] ?? [],
      'readerPositions': value['readerPositions'] ?? {},
      'examHistory': value['examHistory'] ?? [],
      'activeExam': value['activeExam'],
    };

bool equalWorkspace(dynamic a, dynamic b) =>
    jsonEncode(canonicalJsonValue(a)) == jsonEncode(canonicalJsonValue(b));
Json mergeWorkspace(Json local, Json remote, Json base) {
  final merged = <String, dynamic>{
    for (final entry in remote.entries)
      if (!workspaceKeys.contains(entry.key)) entry.key: entry.value
  };
  final conflicts = <String>[];
  for (final key in workspaceKeys) {
    if (equalWorkspace(local[key], remote[key]) ||
        equalWorkspace(remote[key], base[key])) {
      merged[key] = local[key];
    } else if (equalWorkspace(local[key], base[key])) {
      merged[key] = remote[key];
    } else {
      conflicts.add(key);
      merged[key] = local[key];
    }
  }
  return {'merged': merged, 'conflicts': conflicts};
}

class WorkspaceSynchronizer {
  final AppStore store;
  final RemoteSync remote;
  WorkspaceSynchronizer(this.store, {RemoteSync? remote})
      : remote = remote ?? RemoteSync(store);
  Future<void> synchronizeProfile({Json? legacy}) async {
    final owner = store.data['remoteUserId'] as String?;
    final server = store.apiBase;
    if (owner == null) {
      throw StateError('Conecta una cuenta para sincronizar el perfil.');
    }
    final result = await remote.request('GET', '/v1/account/profile');
    final expected = Json.from(store.profile['account'] ?? {});
    final local = {
      ...accountProfileDefaults,
      ...expected,
      if (store.profile['theme'] != null) 'theme': store.profile['theme']
    };
    final base = {
      ...accountProfileDefaults,
      ...Json.from(store.data['accountProfileBase'] ?? {})
    };
    var other = {...accountProfileDefaults, ...Json.from(result['data'])};
    if (result['revision'] == 0 && legacy != null) {
      other = {...other, ...legacy};
    }
    final merged = <String, dynamic>{};
    for (final key in {...local.keys, ...base.keys, ...other.keys}) {
      if (equalWorkspace(local[key], other[key]) ||
          equalWorkspace(other[key], base[key])) {
        merged[key] = local[key];
      } else if (equalWorkspace(local[key], base[key])) {
        merged[key] = other[key];
      } else {
        throw RemoteSyncFailure(409,
            'Tu perfil cambió en dos dispositivos. Revisa Mi perfil; se conservan los valores locales.');
      }
    }
    var revision = result['revision'] as int;
    if (!equalWorkspace(merged, result['data'])) {
      final saved = await remote.request('PUT', '/v1/account/profile',
          body: merged, extraHeaders: {'If-Match': '$revision'});
      if (!equalWorkspace(saved['data'], merged)) {
        throw StateError('El servidor no confirmó todas las preferencias.');
      }
      revision = saved['revision'];
    }
    if (equalWorkspace(expected, merged) &&
        store.data['accountProfileRevision'] == revision &&
        equalWorkspace(store.data['accountProfileBase'], merged)) {
      return;
    }
    await store.commitAccountProfile(expected, merged, revision, owner, server);
  }

  Future<void> synchronize({Json? status}) async {
    final owner = store.data['remoteUserId'] as String?;
    final server = store.apiBase;
    if (owner == null) throw StateError('Conecta una cuenta para sincronizar.');
    final localBefore = localWorkspace(store);
    final baseBefore =
        normalizedWorkspace(Json.from(store.data['workspaceBase'] ?? {}));
    final dirty = !equalWorkspace(localBefore, baseBefore);
    Json? result;
    if (dirty ||
        status == null ||
        store.data['workspaceRevision'] != status['workspaceRevision']) {
      result = await remote.request('GET', '/v1/workspace');
    }
    final legacy = (result?['data'] as Map?)?['profile'] as Map?;
    await synchronizeProfile(
        legacy:
            legacy?['account'] is Map ? Json.from(legacy!['account']) : null);
    if (result == null) return;
    final local = localWorkspace(store);
    final other = normalizedWorkspace(Json.from(result['data'] ?? {}));
    final base =
        normalizedWorkspace(Json.from(store.data['workspaceBase'] ?? {}));
    final comparison = mergeWorkspace(local, other, base);
    if ((comparison['conflicts'] as List).isNotEmpty) {
      throw RemoteSyncFailure(409,
          'Hay secciones cambiadas en ambos dispositivos. Compara notas y plan antes de continuar.');
    }
    final chosen = Json.from(comparison['merged']);
    final saved = await remote.request('PUT', '/v1/workspace',
        body: chosen, extraHeaders: {'If-Match': '${result['revision']}'});
    if (!equalWorkspace(
        normalizedWorkspace(Json.from(saved['data'])), chosen)) {
      throw StateError(
          'El servidor no confirmó todas las secciones; se conserva el espacio local.');
    }
    await store.commitWorkspace(local, chosen, saved['data'], owner, server,
        revision: saved['revision']);
  }
}

class WorkspacePage extends StatefulWidget {
  final AppStore store;
  const WorkspacePage({super.key, required this.store});
  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  Json? local, remote, merged;
  int revision = 0;
  bool busy = false;
  String? ownerScope;
  String? serverScope;
  List<String> conflicts = [];
  final choices = <String, String>{};
  static const labels = {
    'profile': 'Perfil y planificación',
    'notes': 'Notas jurídicas privadas',
    'courses': 'Asignaturas, temas y evaluaciones',
    'follows': 'Normas seguidas',
    'bookmarks': 'Marcadores',
    'favoriteCards': 'Tarjetas favoritas',
    'readerPositions': 'Puntos de lectura',
    'examHistory': 'Historial de simulacros',
    'activeExam': 'Simulacro en curso',
  };
  Future<void> prepare() async {
    setState(() => busy = true);
    await perform(context, () async {
      final result =
          await RemoteSync(widget.store).request('GET', '/v1/workspace');
      ownerScope = widget.store.data['remoteUserId'];
      serverScope = widget.store.apiBase;
      local = localWorkspace(widget.store);
      remote = result['data'] == null
          ? null
          : normalizedWorkspace(Json.from(result['data']));
      revision = result['revision'];
      if (remote == null) {
        merged = local;
        conflicts = [];
      } else {
        final base = normalizedWorkspace(
            Json.from(widget.store.data['workspaceBase'] ?? {}));
        final merge = mergeWorkspace(local!, remote!, base);
        merged = Json.from(merge['merged']);
        conflicts = List<String>.from(merge['conflicts']);
        choices.clear();
      }
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> commit() async {
    setState(() => busy = true);
    await perform(context, () async {
      if (!equalWorkspace(localWorkspace(widget.store), local)) {
        throw StateError(
            'Los datos locales han cambiado durante la comparación. Compara de nuevo.');
      }
      if (widget.store.data['remoteUserId'] != ownerScope ||
          widget.store.apiBase != serverScope) {
        throw StateError(
            'La cuenta cambió. Compara de nuevo antes de sincronizar.');
      }
      final chosen = {...merged!};
      for (final key in conflicts) {
        chosen[key] = choices[key] == 'remote' ? remote![key] : local![key];
      }
      await WorkspaceSynchronizer(widget.store).synchronizeProfile();
      final result = await RemoteSync(widget.store).request(
          'PUT', '/v1/workspace',
          body: chosen, extraHeaders: {'If-Match': '$revision'});
      if (!equalWorkspace(
          normalizedWorkspace(Json.from(result['data'])), chosen)) {
        throw StateError(
            'El servidor no confirmó todas las secciones. Actualiza el servidor antes de reintentar. Tus datos locales se conservan.');
      }
      await widget.store.commitWorkspace(
          local!, chosen, result['data'], ownerScope, serverScope!,
          revision: result['revision']);
      if (mounted) {
        setState(() {
          merged = null;
          conflicts = [];
        });
        toast(context,
            'Espacio de estudio sincronizado. La copia anterior se conserva en tu exportación.');
      }
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Sincronizar notas y plan')),
      body: PageBody(children: [
        const Text(
            'Compara perfil, notas, asignaturas y normas seguidas antes de guardarlos en tu servidor configurado. Los conflictos requieren elegir una versión; la copia local anterior se conserva.'),
        const SizedBox(height: 20),
        FilledButton.icon(
            onPressed: busy ? null : prepare,
            icon: const Icon(Icons.compare_arrows),
            label: const Text('Comparar con el servidor')),
        if (busy) const LinearProgressIndicator(),
        if (merged != null) ...[
          const Section('Resultado de la comparación'),
          if (conflicts.isEmpty)
            const Text(
                'No hay conflictos. Los cambios independientes pueden combinarse.'),
          ...conflicts.map((key) => Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Paper(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(labels[key]!,
                        style: Theme.of(context).textTheme.titleLarge),
                    const Text('Esta sección cambió en ambos dispositivos.'),
                    Wrap(spacing: 8, children: [
                      ChoiceChip(
                          label: const Text('Conservar local'),
                          selected: choices[key] == 'local',
                          onSelected: busy
                              ? null
                              : (_) => setState(() => choices[key] = 'local')),
                      ChoiceChip(
                          label: const Text('Usar servidor'),
                          selected: choices[key] == 'remote',
                          onSelected: busy
                              ? null
                              : (_) => setState(() => choices[key] = 'remote')),
                      TextButton(
                          onPressed: () => showDialog<void>(
                              context: context,
                              builder: (ctx) => AlertDialog(
                                      title: Text(labels[key]!),
                                      content: SingleChildScrollView(
                                          child: SelectableText(
                                              'LOCAL\n${const JsonEncoder.withIndent('  ').convert(local![key])}\n\nSERVIDOR\n${const JsonEncoder.withIndent('  ').convert(remote![key])}')),
                                      actions: [
                                        TextButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: const Text('Cerrar'))
                                      ])),
                          child: const Text('Comparar contenido')),
                    ]),
                  ])))),
          FilledButton(
              onPressed:
                  busy || conflicts.any((key) => !choices.containsKey(key))
                      ? null
                      : commit,
              child: const Text('Guardar la combinación elegida')),
        ],
      ]));
}
