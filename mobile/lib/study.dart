import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'store.dart';
import 'widgets.dart';

class StudyPage extends StatefulWidget {
  final AppStore store;
  const StudyPage({super.key, required this.store});
  @override
  State<StudyPage> createState() => _StudyPageState();
}
class _StudyPageState extends State<StudyPage> {
  String query = '';
  Future<void> importCsv() async {
    await perform(context, () async {
      final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['csv'], withData: true);
      if (picked == null) return;
      final bytes = picked.files.single.bytes;
      if (bytes == null || bytes.length > 2000000) throw const FormatException('CSV máximo: 2 MB.');
      final rows = const CsvToListConverter(shouldParseNumbers: false).convert(utf8.decode(bytes));
      if (rows.isEmpty || rows.length > 2001) throw const FormatException('Importa entre 1 y 2000 tarjetas.');
      final header = rows.first.map((v) => v.toString().trim().toLowerCase()).toList();
      final front = header.indexOf('pregunta'), back = header.indexOf('respuesta');
      if (front < 0 || back < 0) throw const FormatException('El CSV necesita columnas pregunta y respuesta.');
      final cards = <StudyCard>[];
      for (final row in rows.skip(1)) {
        if (row.length <= front || row.length <= back) throw const FormatException('Fila incompleta. No se ha importado nada.');
        final f = row[front].toString().trim(), b = row[back].toString().trim();
        if (f.isEmpty || b.isEmpty || f.length > 4000 || b.length > 8000) throw const FormatException('Pregunta o respuesta vacía o demasiado larga.');
        cards.add(StudyCard(id: const Uuid().v4(), deck: picked.files.single.name.replaceAll('.csv', ''), front: f, back: b));
      }
      if (cards.isEmpty) throw const FormatException('El CSV contiene encabezados pero no tarjetas.');
      if (!mounted) return;
      final approved = await confirm(context, 'Importar ${cards.length} tarjetas privadas',
        'Primera pregunta: ${cards.first.front}\n\nSe etiquetarán como contenido del usuario sin revisión jurídica. Confirma que puedes reutilizar este material.');
      if (!approved) return;
      widget.store.data['cards'] = [...widget.store.cards.map((c) => c.toJson()), ...cards.map((c) => c.toJson())];
      await widget.store.save();
    });
  }
  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final session = s.data['session'];
    final resumeIds = session is Map ? List<String>.from(session['ids'] ?? []) : <String>[];
    final resumeCards = resumeIds.map((id) => s.cards.where((c) => c.id == id && !c.blocked).firstOrNull).whereType<StudyCard>().toList();
    final decks = s.cards.map((c) => c.deck).toSet().where((d) => normalize(d).contains(normalize(query))).toList();
    return PageBody(children: [Text('Aprender. Recordar. Avanzar.', style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 8),
      const Text('Sesiones breves, referencias claras y un ritmo sostenible.'), const SizedBox(height: 20),
      Wrap(spacing: 8, runSpacing: 8, children: [FilledButton.icon(onPressed: () => push(context, CardEditor(store: s)), icon: const Icon(Icons.add), label: const Text('Crear tarjeta')),
        OutlinedButton.icon(onPressed: importCsv, icon: const Icon(Icons.upload_file_outlined), label: const Text('Importar CSV'))]),
      const SizedBox(height: 20), TextField(decoration: const InputDecoration(hintText: 'Buscar un mazo', prefixIcon: Icon(Icons.search)), onChanged: (v) => setState(() => query = v)),
      if (resumeCards.length == resumeIds.length && resumeCards.isNotEmpty && (session['index'] as int? ?? 0) < resumeCards.length) ...[const SizedBox(height: 16), FilledButton.icon(onPressed: () => push(context, ReviewPage(store: s, queue: resumeCards)), icon: const Icon(Icons.play_arrow), label: const Text('Continuar sesión guardada'))],
      const Section('Tus mazos'),
      if (decks.isEmpty) EmptyState(icon: Icons.style_outlined, title: 'Tu primer recuerdo empieza aquí', detail: 'Crea tarjetas propias o importa un CSV. Las tarjetas personales no llevan sello editorial.',
        action: FilledButton(onPressed: () => push(context, CardEditor(store: s)), child: const Text('Crear mi primera tarjeta'))),
      ...decks.map((deck) {
        final cards = s.cards.where((c) => c.deck == deck).toList();
        final due = s.due(deck: deck);
        return Padding(padding: const EdgeInsets.only(bottom: 14), child: Paper(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.layers_outlined, color: teal), const SizedBox(height: 14), Text(deck, style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8),
          Text('${cards.length} tarjetas · ${due.length} pendientes · ${cards.where((c) => c.blocked).length} bloqueadas'),
          const SizedBox(height: 16), const Badge('Contenido del usuario · no verificado', warning: true), const SizedBox(height: 16),
          Wrap(spacing: 8, children: [FilledButton.icon(onPressed: due.isEmpty ? null : () => push(context, ReviewPage(store: s, queue: due)), icon: const Icon(Icons.play_arrow), label: const Text('Repasar')),
            TextButton(onPressed: () => push(context, CardEditor(store: s, deck: deck)), child: const Text('Añadir tarjeta'))]),
        ])));
      }),
      const SizedBox(height: 16), const Text('Programación de repasos: SM-2 adaptado, versión sm2-1. No es una implementación de FSRS. Los intervalos estiman práctica, no una nota de examen.', style: TextStyle(fontSize: 12)),
    ]);
  }
}

class CardEditor extends StatefulWidget {
  final AppStore store;
  final Json? norm, unit;
  final String? deck;
  const CardEditor({super.key, required this.store, this.norm, this.unit, this.deck});
  @override
  State<CardEditor> createState() => _CardEditorState();
}
class _CardEditorState extends State<CardEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController deck;
  final front = TextEditingController(), back = TextEditingController(), explanation = TextEditingController(), options = TextEditingController();
  String type = 'qa';
  int correct = 0;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    final draft = Json.from(widget.store.data['draftCard'] ?? {});
    deck = TextEditingController(text: widget.deck ?? widget.norm?['short'] ?? draft['deck'] ?? 'Mi mazo');
    if (widget.norm == null) {
      front.text = draft['front'] ?? ''; back.text = draft['back'] ?? '';
      explanation.text = draft['explanation'] ?? ''; options.text = draft['options'] ?? '';
      type = draft['type'] ?? 'qa'; correct = draft['correct'] ?? 0;
    }
    for (final controller in [deck, front, back, explanation, options]) { controller.addListener(saveDraft); }
  }
  void saveDraft() {
    widget.store.data['draftCard'] = {'deck': deck.text, 'front': front.text, 'back': back.text,
      'explanation': explanation.text, 'options': options.text, 'type': type, 'correct': correct};
    widget.store.save();
  }
  @override
  void dispose() { for (final c in [deck, front, back, explanation, options]) { c.dispose(); } super.dispose(); }
  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (type == 'cloze' && !RegExp(r'\{\{c\d+::.+?\}\}').hasMatch(front.text)) {
      toast(context, 'Añade al menos un hueco: {{c1::respuesta}}'); return;
    }
    final choices = options.text.split('\n').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    if (type == 'test' && (choices.length < 2 || choices.length > 6 || correct >= choices.length)) {
      toast(context, 'Introduce de 2 a 6 opciones y un índice correcto válido.'); return;
    }
    setState(() => saving = true);
    await perform(context, () async {
      await widget.store.addCard(StudyCard(id: const Uuid().v4(), deck: deck.text.trim(), front: front.text.trim(), back: back.text.trim(),
        explanation: explanation.text.trim(), type: type, normId: widget.norm?['id'] ?? '', unitId: widget.unit?['id'] ?? '',
        versionId: widget.norm?['latestVersion'] ?? '', options: type == 'test' ? choices : [], correct: type == 'test' ? correct : null));
      widget.store.data['draftCard'] = null; await widget.store.save();
      if (mounted) Navigator.pop(context);
    });
    if (mounted) setState(() => saving = false);
  }
  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label, {int lines = 1, bool required = true, int max = 4000}) => Padding(padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(controller: c, minLines: lines, maxLines: lines + 3, maxLength: max, decoration: InputDecoration(labelText: label),
        validator: required ? (v) => v == null || v.trim().isEmpty ? 'Completa este campo' : null : null));
    return Scaffold(appBar: AppBar(title: const Text('Nueva tarjeta privada')), body: Form(key: form, child: PageBody(children: [
      const Badge('Creada por el usuario · sin revisión jurídica', warning: true), const SizedBox(height: 20),
      field(deck, 'Mazo', max: 160), DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'Tipo de ejercicio'),
        items: const [DropdownMenuItem(value: 'qa', child: Text('Pregunta y respuesta')), DropdownMenuItem(value: 'cloze', child: Text('Completar huecos')),
          DropdownMenuItem(value: 'truefalse', child: Text('Verdadero / falso')), DropdownMenuItem(value: 'order', child: Text('Ordenar una lista')),
          DropdownMenuItem(value: 'case', child: Text('Caso práctico')), DropdownMenuItem(value: 'test', child: Text('Pregunta tipo test'))], onChanged: (v) { setState(() => type = v!); saveDraft(); }),
      const SizedBox(height: 20), field(front, type == 'cloze' ? 'Enunciado con {{c1::respuesta}}' : 'Pregunta / hechos del caso', lines: 3),
      field(back, 'Respuesta y excepciones relevantes', lines: 3, max: 8000), field(explanation, 'Explicación y contexto', lines: 3, required: false, max: 8000),
      if (type == 'test') ...[field(options, 'Opciones · una por línea', lines: 4), DropdownButtonFormField<int>(initialValue: correct,
        decoration: const InputDecoration(labelText: 'Opción correcta'), items: List.generate(6, (i) => DropdownMenuItem(value: i, child: Text('Opción ${i + 1}'))), onChanged: (v) => correct = v!), const SizedBox(height: 20)],
      Paper(child: Text(widget.norm == null ? 'Sin fuente jurídica anclada. Puedes crear una tarjeta desde un artículo descargado para conservar norma, versión y bloque.' : 'Fuente: ${widget.norm!['id']} · ${widget.unit!['title']}\nVersión: ${widget.norm!['latestVersion']}')),
      const SizedBox(height: 24), FilledButton(onPressed: saving ? null : save, child: Text(saving ? 'Guardando…' : 'Guardar tarjeta')),
    ])));
  }
}

class ReviewPage extends StatefulWidget {
  final AppStore store;
  final List<StudyCard> queue;
  const ReviewPage({super.key, required this.store, required this.queue});
  @override
  State<ReviewPage> createState() => _ReviewPageState();
}
class _ReviewPageState extends State<ReviewPage> {
  int index = 0;
  bool revealed = false, saving = false;
  DateTime shown = DateTime.now();
  @override
  void initState() {
    super.initState();
    final saved = widget.store.data['session'];
    if (saved is Map && saved['ids'].toString() == widget.queue.map((c) => c.id).toList().toString()) {
      index = saved['index'] ?? 0;
    }
  }
  Future<void> rate(int rating) async {
    setState(() => saving = true);
    await perform(context, () async {
      await widget.store.review(widget.queue[index], rating, latencyMs: DateTime.now().difference(shown).inMilliseconds);
      index++; revealed = false; shown = DateTime.now();
      widget.store.data['session'] = {'ids': widget.queue.map((c) => c.id).toList(), 'index': index}; await widget.store.save();
    });
    if (mounted) setState(() => saving = false);
  }
  @override
  Widget build(BuildContext context) {
    if (index >= widget.queue.length) return Scaffold(appBar: AppBar(title: const Text('Sesión completada')), body: PageBody(children: [const SizedBox(height: 50),
      EmptyState(icon: Icons.check_circle_outline, title: 'Un paso más en tu camino', detail: '${widget.queue.length} tarjetas repasadas. El progreso está guardado en este dispositivo.',
        action: FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Volver a mis mazos')))]));
    final c = widget.queue[index];
    final question = c.type == 'cloze' ? c.front.replaceAllMapped(RegExp(r'\{\{c\d+::(.+?)\}\}'), (_) => '[…]') : c.front;
    return Scaffold(appBar: AppBar(title: const Text('Repaso activo'), actions: [IconButton(tooltip: 'Informar de un error', icon: const Icon(Icons.flag_outlined), onPressed: () async {
      final controller = TextEditingController();
      final reason = await showDialog<String>(context: context, builder: (ctx) => AlertDialog(title: const Text('Informar de un error'), content: TextField(controller: controller, decoration: const InputDecoration(labelText: 'Describe el problema'), maxLines: 4),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')), FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: const Text('Guardar reporte'))]));
      controller.dispose();
      if (reason != null && reason.trim().isNotEmpty && context.mounted) await perform(context, () => widget.store.add('reports', {'id': const Uuid().v4(), 'cardId': c.id, 'reason': reason, 'status': 'local_pending'}), success: 'Reporte guardado localmente; pendiente de envío');
    })]), body: PageBody(children: [
      Row(children: [Text('${index + 1} / ${widget.queue.length}'), const Spacer(), const Badge('Repaso · sin cronómetro')]), const SizedBox(height: 14),
      LinearProgressIndicator(value: index / widget.queue.length, color: teal), const SizedBox(height: 28),
      Text(c.deck, style: const TextStyle(fontSize: 12, letterSpacing: 1)), const SizedBox(height: 16),
      Paper(padding: const EdgeInsets.all(28), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Badge('PREGUNTA'), const SizedBox(height: 28),
        Text(question, style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 32),
        if (revealed) ...[const Divider(), const SizedBox(height: 20), const Badge('RESPUESTA'), const SizedBox(height: 20),
          SelectableText(c.back, style: const TextStyle(fontSize: 21, height: 1.6)), if (c.explanation.isNotEmpty) ...[const SizedBox(height: 20), Text(c.explanation)],
          const SizedBox(height: 24), Text(c.normId.isEmpty ? 'Contenido personal sin fuente anclada' : '${c.normId} · ${c.unitId}\nVersión ${c.versionId}', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 10), Badge(c.blocked ? 'Bloqueada por revisión normativa' : 'Contenido del usuario · no verificado', warning: true)]
        else const Text('Recuerda la respuesta antes de mostrarla.', style: TextStyle(fontSize: 14)),
      ])), const SizedBox(height: 24),
      if (!revealed) FilledButton(onPressed: () => setState(() => revealed = true), child: const Text('Mostrar respuesta'))
      else Wrap(spacing: 8, runSpacing: 8, children: List.generate(4, (i) => OutlinedButton(onPressed: saving || c.blocked ? null : () => rate(i + 1),
        child: Text(['Otra vez', 'Difícil', 'Bien', 'Fácil'][i])))),
      const SizedBox(height: 20), TextButton.icon(onPressed: index == 0 || saving ? null : () async {
        await perform(context, widget.store.undoLast); if (mounted) setState(() { index--; revealed = false; });
      }, icon: const Icon(Icons.undo), label: const Text('Deshacer última revisión local')),
    ]));
  }
}
