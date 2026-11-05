import 'dart:convert';
import 'package:flutter/material.dart' hide Badge;
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'store.dart';
import 'widgets.dart';
import 'exercises.dart';

class StudyPage extends StatefulWidget {
  final AppStore store;
  const StudyPage({super.key, required this.store});
  @override
  State<StudyPage> createState() => _StudyPageState();
}

class _StudyPageState extends State<StudyPage> {
  String query = '';
  bool favoritesOnly = false, weakOnly = false;
  Future<void> importCsv() async {
    await perform(context, () async {
      final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom, allowedExtensions: ['csv'], withData: true);
      if (picked == null) return;
      final bytes = picked.files.single.bytes;
      if (bytes == null || bytes.length > 2000000) {
        throw const FormatException('CSV máximo: 2 MB.');
      }
      final rows = const CsvToListConverter(shouldParseNumbers: false)
          .convert(utf8.decode(bytes));
      if (rows.isEmpty || rows.length > 2001) {
        throw const FormatException('Importa entre 1 y 2000 tarjetas.');
      }
      final header =
          rows.first.map((v) => v.toString().trim().toLowerCase()).toList();
      final front = header.indexOf('pregunta'),
          back = header.indexOf('respuesta');
      if (front < 0 || back < 0) {
        throw const FormatException(
            'El CSV necesita columnas pregunta y respuesta.');
      }
      final cards = <StudyCard>[];
      for (final row in rows.skip(1)) {
        if (row.length <= front || row.length <= back) {
          throw const FormatException(
              'Fila incompleta. No se ha importado nada.');
        }
        final f = row[front].toString().trim(), b = row[back].toString().trim();
        if (f.isEmpty || b.isEmpty || f.length > 4000 || b.length > 8000) {
          throw const FormatException(
              'Pregunta o respuesta vacía o demasiado larga.');
        }
        cards.add(StudyCard(
            id: const Uuid().v4(),
            deck: picked.files.single.name.replaceAll('.csv', ''),
            front: f,
            back: b));
      }
      if (cards.isEmpty) {
        throw const FormatException(
            'El CSV contiene encabezados pero no tarjetas.');
      }
      if (!mounted) return;
      final approved = await confirm(
          context,
          'Importar ${cards.length} tarjetas privadas',
          'Primera pregunta: ${cards.first.front}\n\nSe etiquetarán como contenido del usuario sin revisión jurídica. Confirma que puedes reutilizar este material.');
      if (!approved) return;
      widget.store.data['cards'] = [
        ...widget.store.cards.map((c) => c.toJson()),
        ...cards.map((c) => c.toJson())
      ];
      await widget.store.save();
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final session = s.data['session'];
    final resumeIds =
        session is Map ? List<String>.from(session['ids'] ?? []) : <String>[];
    final resumeCards = resumeIds
        .map((id) => s.cards.where((c) => c.id == id && !c.blocked).firstOrNull)
        .whereType<StudyCard>()
        .toList();
    final eligible = s.cards
        .where((c) =>
            (!favoritesOnly || s.has('favoriteCards', c.id)) &&
            (!weakOnly || (s.state(c.id)['lapses'] as num? ?? 0) > 0) &&
            normalize(
                    '${c.deck} ${c.front} ${c.back} ${c.explanation} ${c.normId} ${c.unitId}')
                .contains(normalize(query)))
        .toList();
    final eligibleIds = eligible.map((c) => c.id).toSet();
    final decks = eligible.map((c) => c.deck).toSet().toList();
    return SearchPageBody(header: [
      Text('Estudiar', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
            child: FilledButton.icon(
                onPressed: () => push(context, PreparedDecksPage(store: s)),
                icon: const Icon(Icons.library_add_outlined),
                label: const Text('Mazos preparados'))),
        PopupMenuButton<String>(
            tooltip: 'Más opciones',
            onSelected: (v) =>
                v == 'csv' ? importCsv() : push(context, CardEditor(store: s)),
            itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'new', child: Text('Crear tarjeta propia')),
                  PopupMenuItem(value: 'csv', child: Text('Importar CSV'))
                ])
      ]),
      const SizedBox(height: 20),
      TextField(
          decoration: const InputDecoration(
              hintText: 'Buscar mazo, pregunta, concepto o artículo',
              prefixIcon: Icon(Icons.search)),
          onChanged: (v) => setState(() => query = v)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, children: [
        FilterChip(
            label: const Text('Favoritas'),
            selected: favoritesOnly,
            onSelected: (v) => setState(() => favoritesOnly = v)),
        FilterChip(
            label: const Text('Con fallos anteriores'),
            selected: weakOnly,
            onSelected: (v) => setState(() => weakOnly = v)),
      ]),
    ], children: [
      if (resumeCards.length == resumeIds.length &&
          resumeCards.isNotEmpty &&
          (session['index'] as int? ?? 0) < resumeCards.length) ...[
        const SizedBox(height: 16),
        FilledButton.icon(
            onPressed: () =>
                push(context, ReviewPage(store: s, queue: resumeCards)),
            icon: const Icon(Icons.play_arrow),
            label: const Text('Continuar sesión guardada'))
      ],
      const Section('Tus mazos'),
      if (decks.isEmpty)
        EmptyState(
            icon: Icons.style_outlined,
            title: 'Tu primer recuerdo empieza aquí',
            detail: 'Elige un mazo preparado para empezar a repasar.',
            action: FilledButton(
                onPressed: () => push(context, PreparedDecksPage(store: s)),
                child: const Text('Elegir mazo'))),
      ...decks.map((deck) {
        final cards = eligible.where((c) => c.deck == deck).toList();
        final due =
            s.due(deck: deck).where((c) => eligibleIds.contains(c.id)).toList();
        return Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Paper(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(deck, style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('${cards.length} tarjetas · ${due.length} pendientes'),
                  const SizedBox(height: 16),
                  Wrap(spacing: 8, children: [
                    FilledButton.icon(
                        onPressed: due.isEmpty
                            ? null
                            : () =>
                                push(context, ReviewPage(store: s, queue: due)),
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Repasar')),
                    TextButton(
                        onPressed: () =>
                            push(context, CardEditor(store: s, deck: deck)),
                        child: const Text('Añadir tarjeta')),
                    TextButton(
                        onPressed: () =>
                            push(context, CardListPage(store: s, deck: deck)),
                        child: const Text('Ver y editar'))
                  ]),
                ])));
      }),
      const Details('Sobre las tarjetas y el repaso', children: [
        Text(
            'Los mazos preparados usan texto literal del BOE y conservan su referencia. No tienen revisión editorial. Puedes editar tus tarjetas. El repaso espaciado adapta los intervalos a tus respuestas.')
      ]),
    ]);
  }
}

class CardEditor extends StatefulWidget {
  final AppStore store;
  final Json? norm, unit, sourceVersion;
  final String? deck;
  final StudyCard? existing;
  const CardEditor(
      {super.key,
      required this.store,
      this.norm,
      this.unit,
      this.sourceVersion,
      this.deck,
      this.existing});
  @override
  State<CardEditor> createState() => _CardEditorState();
}

class _CardEditorState extends State<CardEditor> {
  final form = GlobalKey<FormState>();
  late final TextEditingController deck;
  final front = TextEditingController(),
      back = TextEditingController(),
      explanation = TextEditingController(),
      options = TextEditingController();
  String type = 'qa';
  int correct = 0;
  bool saving = false;
  @override
  void initState() {
    super.initState();
    final draft = Json.from(widget.store.data['draftCard'] ?? {});
    deck = TextEditingController(
        text:
            widget.deck ?? widget.norm?['short'] ?? draft['deck'] ?? 'Mi mazo');
    if (widget.norm == null) {
      front.text = draft['front'] ?? '';
      back.text = draft['back'] ?? '';
      explanation.text = draft['explanation'] ?? '';
      options.text = draft['options'] ?? '';
      type = draft['type'] ?? 'qa';
      correct = draft['correct'] ?? 0;
    }
    if (widget.unit != null && widget.sourceVersion != null) {
      front.text =
          '¿Qué establece ${widget.unit!['title']} de ${widget.norm!['short'] ?? widget.norm!['title']}?';
      final literal = widget.sourceVersion!['text'] as String? ?? '';
      if (literal.length <= 8000) back.text = literal;
      explanation.text =
          'Lectura literal de la fuente; tarjeta personal sin revisión jurídica. Fecha de efecto según fuente: ${displayDate(widget.sourceVersion!['effectiveFrom'])}.';
    }
    final existing = widget.existing;
    if (existing != null) {
      deck.text = existing.deck;
      front.text = existing.front;
      back.text = existing.back;
      explanation.text = existing.explanation;
      options.text = existing.options.join('\n');
      type = existing.type;
      correct = existing.correct ?? 0;
      final draft =
          (widget.store.data['editDrafts'] as Map? ?? {})[existing.id] as Map?;
      if (draft != null) {
        deck.text = draft['deck'];
        front.text = draft['front'];
        back.text = draft['back'];
        explanation.text = draft['explanation'];
        options.text = draft['options'];
        type = draft['type'];
        correct = draft['correct'];
      }
    }
    for (final controller in [deck, front, back, explanation, options]) {
      controller.addListener(saveDraft);
    }
  }

  void saveDraft() {
    final draft = {
      'deck': deck.text,
      'front': front.text,
      'back': back.text,
      'explanation': explanation.text,
      'options': options.text,
      'type': type,
      'correct': correct
    };
    if (widget.existing != null) {
      widget.store.data['editDrafts'] = {
        ...(widget.store.data['editDrafts'] as Map? ?? {}),
        widget.existing!.id: draft
      };
    } else {
      widget.store.data['draftCard'] = draft;
    }
    widget.store.save();
  }

  @override
  void dispose() {
    for (final c in [deck, front, back, explanation, options]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (type == 'cloze' && !RegExp(r'\{\{c\d+::.+?\}\}').hasMatch(front.text)) {
      toast(context, 'Añade al menos un hueco: {{c1::respuesta}}');
      return;
    }
    final choices = type == 'truefalse'
        ? ['Verdadero', 'Falso']
        : options.text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList();
    if (['test', 'case'].contains(type) &&
        (choices.length < 2 ||
            choices.length > 6 ||
            correct >= choices.length)) {
      toast(
          context, 'Introduce de 2 a 6 opciones y un índice correcto válido.');
      return;
    }
    if (type == 'order' &&
        (choices.length < 2 ||
            choices.length > 12 ||
            choices.toSet().length != choices.length)) {
      toast(
          context, 'Añade entre 2 y 12 elementos distintos en orden correcto.');
      return;
    }
    setState(() => saving = true);
    await perform(context, () async {
      final card = StudyCard(
          id: widget.existing?.id ?? const Uuid().v4(),
          deck: deck.text.trim(),
          front: front.text.trim(),
          back: back.text.trim(),
          explanation: explanation.text.trim(),
          type: type,
          normId: widget.existing?.normId ?? widget.norm?['id'] ?? '',
          unitId: widget.existing?.unitId ?? widget.unit?['id'] ?? '',
          versionId:
              widget.existing?.versionId ?? widget.norm?['latestVersion'] ?? '',
          unitVersionHash: widget.existing?.unitVersionHash ??
              widget.sourceVersion?['hash'] ??
              '',
          revision: (widget.existing?.revision ?? 0) + 1,
          blocked: widget.existing?.blocked ?? false,
          options: ['test', 'case', 'order', 'truefalse'].contains(type)
              ? choices
              : [],
          correct:
              ['test', 'case', 'truefalse'].contains(type) ? correct : null);
      if (widget.existing == null) {
        await widget.store.addCard(card);
      } else {
        await widget.store
            .editCard(card, expectedRevision: widget.existing!.revision);
      }
      if (widget.existing != null) {
        (widget.store.data['editDrafts'] as Map?)?.remove(widget.existing!.id);
      } else {
        widget.store.data['draftCard'] = null;
      }
      await widget.store.save();
      if (mounted) Navigator.pop(context);
    });
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label,
            {int lines = 1, bool required = true, int max = 4000}) =>
        Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: TextFormField(
                controller: c,
                minLines: lines,
                maxLines: lines + 3,
                maxLength: max,
                decoration: InputDecoration(labelText: label),
                validator: required
                    ? (v) => v == null || v.trim().isEmpty
                        ? 'Completa este campo'
                        : null
                    : null));
    return Scaffold(
        appBar: AppBar(
            title: Text(widget.existing == null
                ? 'Nueva tarjeta privada'
                : 'Editar tarjeta privada')),
        body: Form(
            key: form,
            child: PageBody(children: [
              const Badge('Creada por el usuario · sin revisión jurídica',
                  warning: true),
              const SizedBox(height: 20),
              field(deck, 'Mazo', max: 160),
              DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration:
                      const InputDecoration(labelText: 'Tipo de ejercicio'),
                  items: const [
                    DropdownMenuItem(
                        value: 'qa', child: Text('Pregunta y respuesta')),
                    DropdownMenuItem(
                        value: 'cloze', child: Text('Completar huecos')),
                    DropdownMenuItem(
                        value: 'truefalse', child: Text('Verdadero / falso')),
                    DropdownMenuItem(
                        value: 'order', child: Text('Ordenar una lista')),
                    DropdownMenuItem(
                        value: 'case', child: Text('Caso práctico')),
                    DropdownMenuItem(
                        value: 'test', child: Text('Pregunta tipo test'))
                  ],
                  onChanged: (v) {
                    setState(() {
                      type = v!;
                      correct = 0;
                    });
                    saveDraft();
                  }),
              const SizedBox(height: 20),
              field(
                  front,
                  type == 'cloze'
                      ? 'Enunciado con {{c1::respuesta}}'
                      : 'Pregunta / hechos del caso',
                  lines: 3),
              field(back, 'Respuesta y excepciones relevantes',
                  lines: 3, max: 8000),
              field(explanation, 'Explicación y contexto',
                  lines: 3, required: false, max: 8000),
              if (['test', 'case', 'order'].contains(type))
                field(
                    options,
                    type == 'order'
                        ? 'Elementos en orden correcto · uno por línea'
                        : 'Opciones · una por línea',
                    lines: 4),
              if (['test', 'case', 'truefalse'].contains(type)) ...[
                DropdownButtonFormField<int>(
                    initialValue: correct,
                    decoration:
                        const InputDecoration(labelText: 'Respuesta correcta'),
                    items: List.generate(
                        type == 'truefalse' ? 2 : 6,
                        (i) => DropdownMenuItem(
                            value: i,
                            child: Text(type == 'truefalse'
                                ? ['Verdadero', 'Falso'][i]
                                : 'Opción ${i + 1}'))),
                    onChanged: (v) {
                      correct = v!;
                      saveDraft();
                    }),
                const SizedBox(height: 20)
              ],
              Paper(
                  child: Text(widget.norm == null
                      ? 'Sin fuente jurídica anclada. Puedes crear una tarjeta desde un artículo descargado para conservar norma, versión y bloque.'
                      : 'Fuente: ${widget.norm!['id']} · ${widget.unit!['title']}\nVersión: ${widget.norm!['latestVersion']}')),
              const SizedBox(height: 24),
              FilledButton(
                  onPressed: saving ? null : save,
                  child: Text(saving ? 'Guardando…' : 'Guardar tarjeta')),
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
  dynamic response;
  DateTime shown = DateTime.now();
  @override
  void initState() {
    super.initState();
    final saved = widget.store.data['session'];
    if (saved is Map &&
        saved['ids'].toString() ==
            widget.queue.map((c) => c.id).toList().toString()) {
      index = saved['index'] ?? 0;
    }
  }

  Future<void> rate(int rating) async {
    setState(() => saving = true);
    await perform(context, () async {
      await widget.store.review(widget.queue[index], rating,
          latencyMs: DateTime.now().difference(shown).inMilliseconds,
          response: response);
      index++;
      revealed = false;
      response = null;
      shown = DateTime.now();
      widget.store.data['session'] = {
        'ids': widget.queue.map((c) => c.id).toList(),
        'index': index
      };
      await widget.store.save();
    });
    if (mounted) setState(() => saving = false);
  }

  @override
  Widget build(BuildContext context) {
    if (index >= widget.queue.length) {
      return Scaffold(
          appBar: AppBar(title: const Text('Sesión completada')),
          body: PageBody(children: [
            const SizedBox(height: 50),
            EmptyState(
                icon: Icons.check_circle_outline,
                title: 'Un paso más en tu camino',
                detail:
                    '${widget.queue.length} tarjetas repasadas. El progreso está guardado en este dispositivo.',
                action: FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Volver a mis mazos')))
          ]));
    }
    final c = widget.queue[index];
    final question = c.type == 'cloze'
        ? c.front.replaceAllMapped(RegExp(r'\{\{c\d+::(.+?)\}\}'), (_) => '[…]')
        : c.front;
    return Scaffold(
        appBar: AppBar(title: const Text('Repaso activo'), actions: [
          IconButton(
              tooltip: 'Informar de un error',
              icon: const Icon(Icons.flag_outlined),
              onPressed: () async {
                final controller = TextEditingController();
                final reason = await showDialog<String>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                            title: const Text('Informar de un error'),
                            content: TextField(
                                controller: controller,
                                decoration: const InputDecoration(
                                    labelText:
                                        'Describe el problema (mínimo 5 caracteres)'),
                                maxLength: 4000,
                                maxLines: 4),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(ctx),
                                  child: const Text('Cancelar')),
                              FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, controller.text),
                                  child: const Text('Guardar reporte'))
                            ]));
                controller.dispose();
                if (reason != null &&
                    reason.trim().length >= 5 &&
                    context.mounted) {
                  await perform(
                      context,
                      () => widget.store.add('reports', {
                            'id': const Uuid().v4(),
                            'cardId': c.id,
                            'reason': reason,
                            'status': 'local_pending'
                          }),
                      success:
                          'Reporte guardado localmente; pendiente de envío');
                }
              })
        ]),
        body: PageBody(children: [
          Row(children: [
            Text('${index + 1} / ${widget.queue.length}'),
            const Spacer(),
            const Badge('Repaso · sin cronómetro')
          ]),
          const SizedBox(height: 14),
          LinearProgressIndicator(
              value: index / widget.queue.length, color: teal),
          const SizedBox(height: 28),
          Text(c.deck, style: const TextStyle(fontSize: 12, letterSpacing: 1)),
          const SizedBox(height: 16),
          Paper(
              padding: const EdgeInsets.all(28),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Badge('PREGUNTA'),
                    const SizedBox(height: 28),
                    Text(question,
                        style: Theme.of(context).textTheme.headlineMedium),
                    const SizedBox(height: 32),
                    ExerciseInput(
                        key: ValueKey(c.id),
                        card: c,
                        revealed: revealed,
                        onChanged: (v) => response = v),
                    if (revealed) ...[
                      const Divider(),
                      const SizedBox(height: 20),
                      const Badge('RESPUESTA'),
                      const SizedBox(height: 20),
                      SelectableText(c.back,
                          style: const TextStyle(fontSize: 21, height: 1.6)),
                      const SizedBox(height: 20),
                      Details('Fuente y explicación', children: [
                        if (c.explanation.isNotEmpty) Text(c.explanation),
                        Text(c.normId.isEmpty
                            ? 'Tarjeta personal sin fuente anclada'
                            : '${c.normId} · ${c.unitId}'),
                        if (c.versionId.isNotEmpty)
                          SelectableText(
                              'Referencia de versión: ${c.versionId}',
                              style: const TextStyle(fontSize: 12)),
                        Text(c.editorialState == 'source_literal'
                            ? 'Tarjeta preparada con texto literal del BOE. Sin revisión editorial.'
                            : 'Tarjeta personal sin revisión editorial.'),
                      ]),
                    ] else
                      const Text('Recuerda la respuesta antes de mostrarla.',
                          style: TextStyle(fontSize: 14)),
                  ])),
          const SizedBox(height: 24),
          if (!revealed)
            FilledButton(
                onPressed: () => setState(() => revealed = true),
                child: const Text('Mostrar respuesta'))
          else
            Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(
                    4,
                    (i) => OutlinedButton(
                        onPressed:
                            saving || c.blocked ? null : () => rate(i + 1),
                        child: Text(
                            ['Otra vez', 'Difícil', 'Bien', 'Fácil'][i])))),
          const SizedBox(height: 20),
          TextButton.icon(
              onPressed: index == 0 || saving
                  ? null
                  : () async {
                      await perform(context, () async {
                        await widget.store.undoLast();
                        if (mounted) {
                          setState(() {
                            index--;
                            revealed = false;
                            response = null;
                          });
                        }
                      });
                    },
              icon: const Icon(Icons.undo),
              label: const Text('Deshacer última revisión local')),
        ]));
  }
}

class CardListPage extends StatefulWidget {
  final AppStore store;
  final String deck;
  const CardListPage({super.key, required this.store, required this.deck});
  @override
  State<CardListPage> createState() => _CardListPageState();
}

class _CardListPageState extends State<CardListPage> {
  String query = '';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final store = widget.store;
        final cards = store.cards
            .where((c) =>
                c.deck == widget.deck &&
                normalize('${c.front} ${c.back}').contains(normalize(query)))
            .toList();
        return Scaffold(
            appBar: AppBar(title: Text(widget.deck)),
            body: SearchPageBody(header: [
              TextField(
                  decoration: const InputDecoration(
                      hintText: 'Buscar entre mis tarjetas',
                      prefixIcon: Icon(Icons.search)),
                  onChanged: (value) => setState(() => query = value)),
            ], children: [
              if (cards.isEmpty)
                const EmptyState(
                    title: 'Sin coincidencias',
                    detail: 'Prueba otro término o vacía la búsqueda.'),
              ...cards.map((c) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Paper(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(c.front,
                            maxLines: 3, overflow: TextOverflow.ellipsis),
                        subtitle: c.blocked
                            ? const Text('Pendiente de revisión')
                            : store.has('favoriteCards', c.id)
                                ? const Text('Favorita')
                                : null,
                        onTap: () => push(
                            context, CardEditor(store: store, existing: c)),
                        trailing: PopupMenuButton<String>(
                            tooltip: 'Opciones de tarjeta',
                            onSelected: (value) {
                              if (value == 'edit') {
                                push(context,
                                    CardEditor(store: store, existing: c));
                              }
                              if (value == 'favorite') {
                                perform(context,
                                    () => store.toggle('favoriteCards', c.id));
                              }
                              if (value == 'history') {
                                push(context,
                                    CardHistoryPage(store: store, card: c));
                              }
                            },
                            itemBuilder: (_) => [
                                  const PopupMenuItem(
                                      value: 'edit',
                                      child: Text('Editar tarjeta')),
                                  PopupMenuItem(
                                      value: 'favorite',
                                      child: Text(
                                          store.has('favoriteCards', c.id)
                                              ? 'Quitar de favoritas'
                                              : 'Marcar favorita')),
                                  const PopupMenuItem(
                                      value: 'history',
                                      child: Text('Ver historial')),
                                ]),
                      )))),
            ]));
      });
}

class CardHistoryPage extends StatelessWidget {
  final AppStore store;
  final StudyCard card;
  const CardHistoryPage({super.key, required this.store, required this.card});
  @override
  Widget build(BuildContext context) {
    final history = [
      ...store.list('cardHistory').where((c) => c['id'] == card.id),
      card.toJson()
    ];
    return Scaffold(
        appBar: AppBar(title: const Text('Historial de la tarjeta')),
        body: PageBody(children: [
          const Text(
              'Las ediciones conservan las respuestas anteriores y el progreso de repaso.'),
          ...history.reversed.map((c) => Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Paper(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Revisión ${c['revision']}',
                      style: Theme.of(context).textTheme.titleMedium),
                  SelectableText(c['front']),
                  const Divider(),
                  SelectableText(c['back']),
                  if ((c['versionId'] as String? ?? '').isNotEmpty)
                    Text(
                        'Fuente: ${c['normId']} · ${c['unitId']} · ${c['versionId']}'),
                ],
              )))),
        ]));
  }
}

class PreparedDecksPage extends StatefulWidget {
  final AppStore store;
  final String initialQuery;
  const PreparedDecksPage(
      {super.key, required this.store, this.initialQuery = ''});
  @override
  State<PreparedDecksPage> createState() => _PreparedDecksPageState();
}

class _PreparedDecksPageState extends State<PreparedDecksPage> {
  late String query;
  late final TextEditingController search;
  String? busy;
  @override
  void initState() {
    super.initState();
    query = widget.initialQuery;
    search = TextEditingController(text: query);
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> prepare(Json deck) async {
    var format = 'qa';
    final name = TextEditingController();
    final chosen = await showModalBottomSheet<bool>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (sheet) => SafeArea(
            child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                    24, 0, 24, MediaQuery.viewInsetsOf(sheet).bottom + 28),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Preparar mi mazo',
                          style: Theme.of(sheet).textTheme.titleLarge),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                          initialValue: format,
                          isExpanded: true,
                          decoration: const InputDecoration(
                              labelText: 'Cómo quiero practicar'),
                          items: const [
                            DropdownMenuItem(
                                value: 'qa', child: Text('Recuerdo literal')),
                            DropdownMenuItem(
                                value: 'cloze',
                                child: Text('Completar huecos')),
                            DropdownMenuItem(
                                value: 'test',
                                child: Text('Test de recuerdo literal')),
                            DropdownMenuItem(
                                value: 'reference',
                                child: Text('Identificar artículo')),
                          ],
                          onChanged: (v) => format = v!),
                      const SizedBox(height: 16),
                      TextField(
                          controller: name,
                          maxLength: 160,
                          decoration: const InputDecoration(
                              labelText: 'Nombre del mazo (opcional)',
                              hintText: 'Mi tema de Administrativo')),
                      const SizedBox(height: 12),
                      const Text(
                          'Usa el mismo nombre para reunir tarjetas de varias normas en un tema propio.'),
                      const SizedBox(height: 20),
                      FilledButton(
                          onPressed: () => Navigator.pop(sheet, true),
                          child: const Text('Añadir tarjetas preparadas')),
                    ]))));
    final group = name.text.trim();
    name.dispose();
    if (chosen != true || !mounted) return;
    setState(() => busy = deck['id']);
    await perform(context, () async {
      final count = await widget.store
          .installPreparedDeck(deck, format: format, group: group);
      if (mounted) {
        toast(
            context,
            count == 0
                ? 'No hay tarjetas nuevas para esta selección. Tu progreso se conserva.'
                : '$count tarjetas añadidas a tus mazos.');
      }
    });
    if (mounted) setState(() => busy = null);
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.store.preparedDecks
        .where((d) => normalize('${d['title']} ${d['subject']} ${d['id']}')
            .contains(normalize(query)))
        .toList();
    return Scaffold(
        appBar: AppBar(title: const Text('Mazos preparados')),
        body: SearchPageBody(
            header: [
              const Text('Elige una norma y cómo quieres practicar.'),
              const SizedBox(height: 12),
              TextField(
                  controller: search,
                  decoration: const InputDecoration(
                      hintText: 'Buscar norma, referencia o materia',
                      prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => setState(() => query = v)),
              const SizedBox(height: 8),
              Text('${rows.length} normas con material preparado',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
            resultCount: rows.length,
            resultBuilder: (context, i) {
              final deck = rows[i];
              return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Paper(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text(deck['title'],
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 8),
                        Text('${deck['count']} fragmentos de referencia'),
                        if (deck['exhausted'] == true)
                          const Text('Vigencia agotada según la fuente',
                              style: TextStyle(color: Color(0xff946017))),
                        const SizedBox(height: 16),
                        FilledButton(
                            onPressed:
                                busy == null ? () => prepare(deck) : null,
                            child: Text(busy == deck['id']
                                ? 'Preparando…'
                                : 'Elegir ejercicio')),
                      ])));
            },
            children: [
              if (rows.isEmpty)
                const EmptyState(
                    title: 'Sin coincidencias',
                    detail: 'Prueba con otra norma o referencia.'),
            ]));
  }
}
