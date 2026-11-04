import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'models.dart';
import 'store.dart';
import 'widgets.dart';
import 'study.dart';

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
          Badge(n['units'] != null ? 'Importada · revisión pendiente' : 'Texto pendiente de importar', warning: true)]))))),
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
        Text('Último cotejo: ${n['checkedAt'] ?? 'sin cotejo'}'), Text('Descarga local: ${n['downloadedAt'] ?? 'no descargada'}'),
      ])),
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
          FilledButton.icon(onPressed: unavailable ? null : () => push(context, CardEditor(store: widget.store, norm: widget.norm, unit: widget.unit)), icon: const Icon(Icons.add), label: const Text('Crear tarjeta')),
        ]), const Section('Notas privadas'),
        TextFormField(initialValue: (widget.store.data['notes'] as Map? ?? {})['${widget.norm['id']}:${widget.unit['id']}'] ?? '', minLines: 3, maxLines: 10,
          decoration: const InputDecoration(labelText: 'Tus notas se guardan solo en este dispositivo'), onChanged: (text) {
            widget.store.data['notes'] = {...(widget.store.data['notes'] as Map? ?? {}), '${widget.norm['id']}:${widget.unit['id']}': text}; widget.store.save();
          }),
        const SizedBox(height: 20), SelectableText(reference, style: const TextStyle(fontSize: 12)),
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

class UpdatesPage extends StatelessWidget {
  final AppStore store;
  const UpdatesPage({super.key, required this.store});
  @override
  Widget build(BuildContext context) => PageBody(children: [Text('Legislación viva', style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 8),
    const Text('Publicación, vigencia y revisión son momentos distintos.'), const SizedBox(height: 24),
    const EmptyState(icon: Icons.notifications_none, title: 'Sin eventos normativos descargados', detail: 'La vigilancia requiere el servicio BOE configurado. No se afirma que tus normas estén actualizadas por ausencia de avisos.'),
    const Section('Normas que sigues'),
    ...store.catalogue.where((n) => store.has('follows', n['id'])).map((n) => ListTile(leading: const Icon(Icons.bookmark_outline), title: Text(n['short'] ?? n['title']),
      subtitle: const Text('Seguimiento local · notificaciones remotas pendientes'), onTap: () => push(context, NormPage(store: store, id: n['id'])))),
    const Section('Preferencias de avisos'),
    SwitchListTile(value: store.data['internalAlerts'] ?? true, title: const Text('Avisos dentro de la aplicación'), onChanged: (v) { store.data['internalAlerts'] = v; store.save(); }),
    const Text('Las notificaciones push no están activadas. Requieren Firebase/APNs y consentimiento del sistema.', style: TextStyle(fontSize: 12)),
  ]);
}
