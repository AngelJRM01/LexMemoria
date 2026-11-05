import 'package:flutter/material.dart' hide Badge;
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'models.dart';
import 'store.dart';
import 'widgets.dart';
import 'study.dart';
import 'remote.dart';

class LibraryPage extends StatefulWidget {
  final AppStore store;
  const LibraryPage({super.key, required this.store});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}
class _LibraryPageState extends State<LibraryPage> {
  String query = '', subject = 'Todas';
  bool saved = false;
  @override
  Widget build(BuildContext context) {
    final rows = widget.store.catalogue.where((n) => (subject == 'Todas' || n['subject'] == subject) &&
      (!saved || widget.store.has('bookmarks', n['id'])) && normalize('${n['title']} ${n['id']}').contains(normalize(query))).toList();
    return PageBody(children: [
      Text('Tu biblioteca jurídica', style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 8),
      const Text('La fuente, la versión y su estado. Siempre a la vista.'), const SizedBox(height: 24),
      TextField(decoration: const InputDecoration(hintText: 'Título, referencia BOE o concepto', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => query = v)),
      const SizedBox(height: 12), SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: ['Todas', ...subjects].map((s) => Padding(padding: const EdgeInsets.only(right: 8),
        child: ChoiceChip(label: Text(s), selected: subject == s, onSelected: (_) => setState(() => subject = s)))).toList())),
      Row(children: [FilterChip(label: const Text('Guardadas'), selected: saved, onSelected: (v) => setState(() => saved = v)), const Spacer(),
        TextButton.icon(onPressed: widget.store.syncing ? null : () => perform(context, widget.store.fetchCatalogue, success: 'Metadatos sincronizados'), icon: const Icon(Icons.sync), label: const Text('Sincronizar'))]),
      if (widget.store.syncing) const LinearProgressIndicator(),
      if (widget.store.error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(widget.store.error!, style: const TextStyle(color: Color(0xffbb3545)))),
      const SizedBox(height: 12), Text('${rows.length} referencias · Estado · Fuente BOE', style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 12),
      if (rows.isEmpty) const EmptyState(title: 'Sin coincidencias', detail: 'Prueba otro término o elimina los filtros.'),
      ...rows.map((n) => Padding(padding: const EdgeInsets.only(bottom: 12), child: Paper(child: InkWell(onTap: () => push(context, NormPage(store: widget.store, id: n['id'])),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [const Icon(Icons.description_outlined, color: teal), const SizedBox(width: 10), Expanded(child: Text(n['subject'] ?? 'Normativa', style: const TextStyle(fontSize: 12, letterSpacing: .8))),
          if (n['units'] != null) const Icon(Icons.offline_pin_outlined, color: teal, semanticLabel: 'Disponible offline')]),
          const SizedBox(height: 12), Text(n['short'] ?? n['title'], style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8),
          Text(n['id'], style: const TextStyle(fontSize: 12)), const SizedBox(height: 12),
          Badge(n['units'] != null ? 'Disponible offline · revisión pendiente' : n['bundledAsset'] != null ? 'Incluida · lista para guardar' : n['latestVersion'] != null ? 'Importada · pendiente de descarga' : 'Texto pendiente de importar', warning: true)]))))),
      if (widget.store.data['catalogueCursor'] != null) OutlinedButton.icon(
        onPressed: widget.store.syncing ? null : () => perform(context, () => widget.store.fetchCatalogue(nextPage: true)),
        icon: const Icon(Icons.expand_more), label: const Text('Cargar más normas')),
    ]);
  }
}

class NormPage extends StatefulWidget {
  final AppStore store;
  final String id;
  const NormPage({super.key, required this.store, required this.id});
  @override
  State<NormPage> createState() => _NormPageState();
}
class _NormPageState extends State<NormPage> {
  String query = '';
  bool downloading = false;
  @override
  Widget build(BuildContext context) {
    final n = widget.store.catalogue.firstWhere((n) => n['id'] == widget.id);
    final units = (n['units'] as List? ?? []).map((u) => Json.from(u)).where((u) => normalize('${u['title']}').contains(normalize(query))).toList();
    return Scaffold(appBar: AppBar(title: const Text('Ficha de norma')), body: PageBody(children: [
      Badge(n['subject'] ?? 'Normativa'), const SizedBox(height: 16), Text(n['title'], style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 12), SelectableText(n['id']), const SizedBox(height: 20),
      const Paper(child: Text('El texto consolidado es informativo. Comprueba la publicación oficial y las disposiciones transitorias. La importación no equivale a revisión jurídica.')),
      const SizedBox(height: 16), Wrap(spacing: 8, runSpacing: 8, children: [
        OutlinedButton.icon(onPressed: () => openSource(context, n['sourceUrl']), icon: const Icon(Icons.open_in_new), label: const Text('Fuente oficial')),
        OutlinedButton.icon(onPressed: () => perform(context, () => widget.store.toggle('follows', widget.id), success: 'Preferencia guardada'), icon: Icon(widget.store.has('follows', widget.id) ? Icons.notifications_active : Icons.notifications_none), label: const Text('Seguir')),
        OutlinedButton.icon(onPressed: () => perform(context, () => widget.store.toggle('bookmarks', widget.id), success: 'Marcador guardado'), icon: Icon(widget.store.has('bookmarks', widget.id) ? Icons.bookmark : Icons.bookmark_outline), label: const Text('Guardar')),
        FilledButton.icon(onPressed: downloading ? null : () async {
          setState(() => downloading = true);
          await perform(context, () => widget.store.downloadNorm(n), success: 'Texto guardado para lectura offline');
          if (mounted) setState(() => downloading = false);
        }, icon: const Icon(Icons.download_outlined), label: Text(downloading ? 'Descargando…' : 'Descargar texto')),
      ]),
      const Section('Procedencia y disponibilidad'),
      Paper(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Ámbito: ${n['jurisdiction']}'), Text('Estado: ${n['coverage']} · revisión pendiente'),
        Text('Publicación: ${n['publicationDate'] ?? 'no comprobada'}'), Text('Fecha de efecto: ${n['effectiveFrom'] ?? 'no comprobada'}'),
        Text('Actualización en la fuente: ${n['sourceUpdatedAt'] ?? 'no indicada'}'),
        Text('Último cotejo: ${n['checkedAt'] ?? 'sin cotejo'}'), Text('Descarga local: ${n['downloadedAt'] ?? 'no descargada'}'),
      ])),
      const SizedBox(height: 12), const Text('Basado en datos de la Agencia Estatal Boletín Oficial del Estado. Extracción estructurada para lectura; el texto consolidado tiene carácter meramente informativo.'),
      TextButton(onPressed: () => openSource(context, 'https://www.boe.es'), child: const Text('Agencia Estatal Boletín Oficial del Estado')),
      TextButton(onPressed: () => openSource(context, 'https://www.boe.es/informacion/aviso_legal/index.php#reutilizacion'), child: const Text('Condiciones de reutilización')),
      const Section('Índice de lectura'),
      if (units.isNotEmpty) TextField(decoration: const InputDecoration(labelText: 'Buscar dentro del índice', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => query = v)),
      const SizedBox(height: 12),
      if (units.isEmpty) const EmptyState(title: 'Texto no disponible en este dispositivo', detail: 'Consulta la fuente oficial o descarga la norma cuando esté importada en el servidor.'),
      ...units.map((u) => ListTile(title: Text(u['title']), subtitle: Text('${(u['versions'] as List).length} versiones de bloque'), trailing: const Icon(Icons.chevron_right),
        onTap: () => push(context, ReaderPage(store: widget.store, norm: n, unit: u)))),
    ]));
  }
}

class ReaderPage extends StatefulWidget {
  final AppStore store;
  final Json norm, unit;
  const ReaderPage({super.key, required this.store, required this.norm, required this.unit});
  @override
  State<ReaderPage> createState() => _ReaderPageState();
}
class _ReaderPageState extends State<ReaderPage> {
  int version = 0;
  DateTime? studyDate;
  final tts = FlutterTts();
  @override
  void initState() { super.initState(); version = (widget.unit['versions'] as List).length - 1; }
  @override
  void dispose() { tts.stop(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final versions = widget.unit['versions'] as List;
    final selection = studyDate == null ? null : resolveLegalVersions(versions.map((v) => Json.from(v)).toList(), studyDate!);
    final unavailable = selection != null && selection['selectedIndex'] == null;
    final selectedIndex = selection?['selectedIndex'] as int? ?? version;
    final v = Json.from(versions[selectedIndex]);
    final reference = unavailable ? 'Sin redacción seleccionable para ${civilDate(studyDate!)}' : '${widget.norm['id']} · ${widget.unit['title']} · fecha de efecto ${v['effectiveFrom'] ?? 'no determinada'}';
    return Scaffold(appBar: AppBar(title: const Text('Lector jurídico'), actions: [IconButton(tooltip: 'Copiar referencia', icon: const Icon(Icons.copy), onPressed: unavailable ? null : () => perform(context, () => Clipboard.setData(ClipboardData(text: reference)), success: 'Referencia copiada'))]),
      body: PageBody(children: [Badge(widget.norm['short'] ?? widget.norm['id']), const SizedBox(height: 18),
        Text(widget.unit['title'], style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 20),
        DropdownButtonFormField<int>(key: ValueKey('version:$version:$studyDate'), initialValue: selectedIndex, isExpanded: true, decoration: const InputDecoration(labelText: 'Versión histórica · fecha de efecto según fuente'),
          items: List.generate(versions.length, (i) => DropdownMenuItem(value: i, child: Text(versions[i]['effectiveFrom'] ?? 'Fecha no determinada'))), onChanged: (i) => setState(() { version = i!; studyDate = null; })),
        const SizedBox(height: 12), OutlinedButton.icon(onPressed: () async {
          final date = await showDatePicker(context: context, initialDate: studyDate ?? DateTime.now(), firstDate: DateTime(1800), lastDate: DateTime.now().add(const Duration(days: 3650)));
          if (date != null) setState(() => studyDate = date);
        }, icon: const Icon(Icons.history), label: Text(studyDate == null ? 'Consultar una fecha de estudio' : 'Fecha de estudio: ${civilDate(studyDate!)}')),
        if (selection != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(selection['reason'])),
        const SizedBox(height: 16), const Badge('Consolidación informativa · sin revisión editorial', warning: true), const SizedBox(height: 24),
        unavailable ? const EmptyState(title: 'Redacción no resoluble para esta fecha', detail: 'Consulta la fuente oficial o elige manualmente una versión histórica. No se ha inferido una respuesta.') : Paper(child: SelectableText(v['text'] ?? '', style: const TextStyle(fontSize: 18, height: 1.85))), const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, children: [
          OutlinedButton.icon(onPressed: unavailable ? null : () => perform(context, () async { await tts.setLanguage('es-ES'); await tts.speak(v['text']); }), icon: const Icon(Icons.volume_up_outlined), label: const Text('Escuchar')),
          OutlinedButton.icon(onPressed: () => tts.stop(), icon: const Icon(Icons.stop), label: const Text('Detener')),
          OutlinedButton.icon(onPressed: () => push(context, ComparePage(unit: widget.unit)), icon: const Icon(Icons.compare_arrows), label: const Text('Comparar')),
          FilledButton.icon(onPressed: unavailable ? null : () => push(context, CardEditor(store: widget.store, norm: widget.norm, unit: widget.unit, sourceVersion: v)), icon: const Icon(Icons.add), label: const Text('Crear tarjeta')),
        ]), const Section('Notas privadas'),
        TextFormField(initialValue: (widget.store.data['notes'] as Map? ?? {})['${widget.norm['id']}:${widget.unit['id']}'] ?? '', minLines: 3, maxLines: 10,
          decoration: const InputDecoration(labelText: 'Tus notas se guardan solo en este dispositivo'), onChanged: (text) {
            widget.store.data['notes'] = {...(widget.store.data['notes'] as Map? ?? {}), '${widget.norm['id']}:${widget.unit['id']}': text}; widget.store.save();
          }),
        const SizedBox(height: 20), SelectableText(reference, style: const TextStyle(fontSize: 12)),
        const Text('Basado en datos de la Agencia Estatal Boletín Oficial del Estado · extracción estructurada. Texto consolidado meramente informativo.'),
        Text('Actualización de la fuente: ${widget.norm['sourceUpdatedAt'] ?? 'no indicada'} · cotejo: ${widget.norm['checkedAt'] ?? 'no indicado'}'),
        TextButton(onPressed: () => openSource(context, widget.norm['sourceUrl']), child: const Text('Abrir publicación oficial')),
      ]));
  }
}
class ComparePage extends StatefulWidget {
  final Json unit;
  const ComparePage({super.key, required this.unit});
  @override
  State<ComparePage> createState() => _ComparePageState();
}
class _ComparePageState extends State<ComparePage> {
  int old = 0, newer = 0;
  @override
  void initState() { super.initState(); newer = (widget.unit['versions'] as List).length - 1; }
  @override
  Widget build(BuildContext context) {
    final versions = widget.unit['versions'] as List;
    final a = (versions[old]['text'] as String).split('\n');
    final b = (versions[newer]['text'] as String).split('\n');
    Widget selector(String label, int value, ValueChanged<int> change) => DropdownButtonFormField<int>(initialValue: value, isExpanded: true,
      decoration: InputDecoration(labelText: label), items: List.generate(versions.length, (i) => DropdownMenuItem(value: i, child: Text(versions[i]['effectiveFrom'] ?? 'Sin fecha'))), onChanged: (v) => change(v!));
    return Scaffold(appBar: AppBar(title: const Text('Comparar versiones')), body: PageBody(children: [
      Text(widget.unit['title'], style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 20),
      selector('Versión anterior', old, (v) => setState(() => old = v)), const SizedBox(height: 12), selector('Versión posterior', newer, (v) => setState(() => newer = v)),
      const SizedBox(height: 20), const Text('Comparación textual por párrafos. No determina por sí sola la vigencia ni la interpretación jurídica.'),
      const Section('Anterior · párrafos ausentes en la nueva versión'),
      ...a.map((line) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Paper(child: Text('${b.contains(line) ? '= ' : '− '}$line', style: TextStyle(decoration: b.contains(line) ? null : TextDecoration.lineThrough))))),
      const Section('Posterior · párrafos añadidos'),
      ...b.map((line) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Paper(child: Text('${a.contains(line) ? '= ' : '+ '}$line', style: TextStyle(fontWeight: a.contains(line) ? FontWeight.normal : FontWeight.bold))))),
    ]));
  }
}

class UpdatesPage extends StatefulWidget {
  final AppStore store;
  const UpdatesPage({super.key, required this.store});
  @override
  State<UpdatesPage> createState() => _UpdatesPageState();
}
class _UpdatesPageState extends State<UpdatesPage> {
  bool loading = false, followedOnly = false;
  String filter = 'Todos';
  Future<void> refresh({bool next = false}) async {
    if (loading) return;
    setState(() => loading = true);
    await perform(context, () => widget.store.fetchUpdates(nextPage: next), success: 'Novedades guardadas para consulta offline');
    if (mounted) setState(() => loading = false);
  }
  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final events = store.list('legalUpdates').where((e) =>
      (!followedOnly || store.has('follows', e['normId'] ?? e['officialId'] ?? '')) &&
      (filter == 'Todos' || (filter == 'Pendientes' ? e['editorialState'] != 'approved' : e['type'] == 'consolidation_available'))).toList();
    events.sort((a, b) => (b['detectedAt'] ?? '').toString().compareTo((a['detectedAt'] ?? '').toString()));
    return PageBody(children: [
      Text('Legislación viva', style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 8),
      const Text('Publicación, vigencia y revisión son momentos distintos.'), const SizedBox(height: 16),
      Wrap(spacing: 8, runSpacing: 8, children: ['Todos', 'Pendientes', 'Consolidados'].map((v) => ChoiceChip(label: Text(v), selected: filter == v,
        onSelected: (_) => setState(() => filter = v))).toList()),
      Row(children: [FilterChip(label: const Text('Normas seguidas'), selected: followedOnly, onSelected: (v) => setState(() => followedOnly = v)),
        const Spacer(), IconButton(tooltip: 'Actualizar novedades', onPressed: loading ? null : refresh, icon: const Icon(Icons.sync))]),
      if (loading) const LinearProgressIndicator(),
      if (store.data['lastUpdatesSync'] != null) Text('Última descarga: ${store.data['lastUpdatesSync']}', style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 20),
      if (events.isEmpty) const EmptyState(icon: Icons.notifications_none, title: 'Sin novedades para estos filtros', detail: 'Sincroniza con el servidor o cambia los filtros. La ausencia de avisos no acredita que todas tus normas estén actualizadas.'),
      ...events.map((event) => Padding(padding: const EdgeInsets.only(bottom: 16), child: Paper(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Badge(event['type'] == 'consolidation_available' ? 'Consolidación disponible' : 'Documento publicado', warning: true), const SizedBox(height: 12),
        Text(event['title'] ?? event['normId'] ?? event['officialId'] ?? 'Evento normativo', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8), Text('Impacto: ${event['impact']} · revisión: ${event['editorialState']}'),
        Text('Publicación: ${event['publicationDate'] ?? 'no determinada'}'), Text('Efecto: ${event['effectiveFrom'] ?? 'pendiente de análisis'}'),
        const SizedBox(height: 12), const Text('No se ha inferido automáticamente la vigencia ni la afectación jurídica.'),
        if (event['sourceUrl'] != null) TextButton.icon(onPressed: () => openSource(context, event['sourceUrl']), icon: const Icon(Icons.open_in_new), label: const Text('Consultar fuente')),
      ])))),
      if (store.data['updatesCursor'] != null) OutlinedButton(onPressed: loading ? null : () => refresh(next: true), child: const Text('Cargar más novedades')),
      const Section('Normas que sigues'),
      ...store.catalogue.where((n) => store.has('follows', n['id'])).map((n) => ListTile(leading: const Icon(Icons.bookmark_outline), title: Text(n['short'] ?? n['title']),
        subtitle: const Text('Seguimiento local'), onTap: () => push(context, NormPage(store: store, id: n['id'])))),
      const Section('Preferencias de avisos'),
      SwitchListTile(value: store.data['internalAlerts'] ?? true, title: const Text('Avisos dentro de la aplicación'), onChanged: (v) { store.data['internalAlerts'] = v; store.save(); }),
      if (store.data['remoteUserId'] != null) ...[
        OutlinedButton.icon(onPressed: () => perform(context, RemoteSync(store).syncNotifications, success: 'Suscripciones y bandeja sincronizadas'), icon: const Icon(Icons.sync), label: const Text('Sincronizar mis avisos')),
        ...store.list('notifications').map((n) => ListTile(leading: Icon(n['read'] == true ? Icons.drafts_outlined : Icons.markunread_outlined), title: Text('Actualización de ${n['normId']}'), subtitle: Text('Disponible desde ${n['createdAt']}'), onTap: () => perform(context, () async {
          await RemoteSync(store).send('/v1/notifications/${n['id']}/read'); await RemoteSync(store).syncNotifications();
        }))),
      ],
      const Text('Las notificaciones push requieren Firebase/APNs y consentimiento del sistema.', style: TextStyle(fontSize: 12)),
    ]);
  }
}
