import 'dart:convert';
import 'package:flutter/material.dart';
import 'models.dart';
import 'store.dart';
import 'remote.dart';
import 'widgets.dart' hide Badge;

const workspaceKeys = ['profile', 'notes', 'courses', 'follows'];
Json localWorkspace(AppStore store) => {
  'profile': store.profile, 'notes': store.data['notes'] ?? {},
  'courses': store.data['courses'] ?? [], 'follows': store.data['follows'] ?? [],
};
// Canonical order makes comparison independent of JSON map insertion order.
dynamic canonical(dynamic value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: canonical(value[key])};
  }
  if (value is List) return value.map(canonical).toList();
  return value;
}
bool equalWorkspace(dynamic a, dynamic b) => jsonEncode(canonical(a)) == jsonEncode(canonical(b));
Json mergeWorkspace(Json local, Json remote, Json base) {
  final merged = <String, dynamic>{}; final conflicts = <String>[];
  for (final key in workspaceKeys) {
    if (equalWorkspace(local[key], remote[key]) || equalWorkspace(remote[key], base[key])) {
      merged[key] = local[key];
    } else if (equalWorkspace(local[key], base[key])) {
      merged[key] = remote[key];
    } else { conflicts.add(key); merged[key] = local[key]; }
  }
  return {'merged': merged, 'conflicts': conflicts};
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
  List<String> conflicts = [];
  final choices = <String, String>{};
  static const labels = {'profile': 'Perfil y planificación', 'notes': 'Notas jurídicas privadas', 'courses': 'Asignaturas, temas y evaluaciones', 'follows': 'Normas seguidas'};
  Future<void> prepare() async {
    setState(() => busy = true);
    await perform(context, () async {
      final result = await RemoteSync(widget.store).request('GET', '/v1/workspace');
      local = localWorkspace(widget.store);
      remote = result['data'] == null ? null : Json.from(result['data']);
      revision = result['revision'];
      if (remote == null) { merged = local; conflicts = []; }
      else {
        final base = Json.from(widget.store.data['workspaceBase'] ?? {'profile': {}, 'notes': {}, 'courses': [], 'follows': []});
        final merge = mergeWorkspace(local!, remote!, base);
        merged = Json.from(merge['merged']); conflicts = List<String>.from(merge['conflicts']); choices.clear();
      }
    });
    if (mounted) setState(() => busy = false);
  }
  Future<void> commit() async {
    setState(() => busy = true);
    await perform(context, () async {
      if (!equalWorkspace(localWorkspace(widget.store), local)) {
        throw StateError('Los datos locales han cambiado durante la comparación. Compara de nuevo.');
      }
      final chosen = {...merged!};
      for (final key in conflicts) { chosen[key] = choices[key] == 'remote' ? remote![key] : local![key]; }
      final result = await RemoteSync(widget.store).request('PUT', '/v1/workspace', body: chosen, extraHeaders: {'If-Match': '$revision'});
      // Keep the previous local copy even when the user selects remote content.
      widget.store.data['workspaceHistory'] = [...widget.store.list('workspaceHistory'), {'at': DateTime.now().toUtc().toIso8601String(), 'data': local}];
      for (final key in workspaceKeys) { widget.store.data[key] = chosen[key]; }
      widget.store.data['workspaceBase'] = result['data'];
      widget.store.data['lastWorkspaceSync'] = DateTime.now().toUtc().toIso8601String();
      await widget.store.save();
      if (mounted) { setState(() { merged = null; conflicts = []; }); toast(context, 'Espacio de estudio sincronizado. La copia anterior se conserva en tu exportación.'); }
    });
    if (mounted) setState(() => busy = false);
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Sincronizar notas y plan')), body: PageBody(children: [
    const Text('Compara perfil, notas, asignaturas y normas seguidas antes de guardarlos en tu servidor configurado. Los conflictos requieren elegir una versión; la copia local anterior se conserva.'),
    const SizedBox(height: 20), FilledButton.icon(onPressed: busy ? null : prepare, icon: const Icon(Icons.compare_arrows), label: const Text('Comparar con el servidor')),
    if (busy) const LinearProgressIndicator(),
    if (merged != null) ...[
      const Section('Resultado de la comparación'),
      if (conflicts.isEmpty) const Text('No hay conflictos. Los cambios independientes pueden combinarse.'),
      ...conflicts.map((key) => Padding(padding: const EdgeInsets.only(bottom: 20), child: Paper(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(labels[key]!, style: Theme.of(context).textTheme.titleLarge),
        const Text('Esta sección cambió en ambos dispositivos.'),
        Wrap(spacing: 8, children: [
          ChoiceChip(label: const Text('Conservar local'), selected: choices[key] == 'local', onSelected: busy ? null : (_) => setState(() => choices[key] = 'local')),
          ChoiceChip(label: const Text('Usar servidor'), selected: choices[key] == 'remote', onSelected: busy ? null : (_) => setState(() => choices[key] = 'remote')),
          TextButton(onPressed: () => showDialog<void>(context: context, builder: (ctx) => AlertDialog(title: Text(labels[key]!), content: SingleChildScrollView(child: SelectableText('LOCAL\n${const JsonEncoder.withIndent('  ').convert(local![key])}\n\nSERVIDOR\n${const JsonEncoder.withIndent('  ').convert(remote![key])}')), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cerrar'))])), child: const Text('Comparar contenido')),
        ]),
      ])))),
      FilledButton(onPressed: busy || conflicts.any((key) => !choices.containsKey(key)) ? null : commit, child: const Text('Guardar la combinación elegida')),
    ],
  ]));
}
