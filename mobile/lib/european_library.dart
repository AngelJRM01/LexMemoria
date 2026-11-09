import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'prepared.dart';
import 'package:flutter/material.dart';
import 'models.dart';
import 'store.dart';
import 'widgets.dart';
import 'catalogue.dart';
import 'browsing_widgets.dart';
import 'european_repository.dart';

class FullEuropeanLibraryPage extends StatefulWidget {
  final AppStore store;
  const FullEuropeanLibraryPage({super.key, required this.store});
  @override
  State<FullEuropeanLibraryPage> createState() =>
      _FullEuropeanLibraryPageState();
}

class _FullEuropeanLibraryPageState extends State<FullEuropeanLibraryPage> {
  late final repository = EuropeanRepository(widget.store);
  late Future<List<Json>> loading = repository.catalogue();
  String query = '', kind = 'Todos', year = 'Todos';
  bool saved = false, textOnly = false;
  int page = 0, size = 20;
  Timer? debounce;
  final scroll = ScrollController();
  void reset() {
    page = 0;
    if (scroll.hasClients) scroll.jumpTo(0);
  }

  @override
  void dispose() {
    debounce?.cancel();
    scroll.dispose();
    super.dispose();
  }

  Future<void> filters(List<Json> rows) async {
    var chosenKind = kind, chosenYear = year;
    var onlyText = textOnly;
    final kinds = rows.map((n) => n['kind'].toString()).toSet().toList()
      ..sort();
    final years = rows
        .map((n) => n['year'].toString())
        .where((v) => v.isNotEmpty)
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    final apply = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (sheet) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: StatefulBuilder(
                    builder: (_, update) =>
                        Column(mainAxisSize: MainAxisSize.min, children: [
                          DropdownButtonFormField<String>(
                              initialValue: chosenKind,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  labelText: 'Tipo de documento'),
                              items: ['Todos', ...kinds]
                                  .map((v) => DropdownMenuItem(
                                      value: v, child: Text(v)))
                                  .toList(),
                              onChanged: (v) => update(() => chosenKind = v!)),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                              initialValue: chosenYear,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  labelText: 'Año del acto'),
                              items: ['Todos', ...years]
                                  .map((v) => DropdownMenuItem(
                                      value: v, child: Text(v)))
                                  .toList(),
                              onChanged: (v) => update(() => chosenYear = v!)),
                          SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              title: const Text('Solo con lectura disponible'),
                              value: onlyText,
                              onChanged: (v) => update(() => onlyText = v)),
                          FilledButton(
                              onPressed: () => Navigator.pop(sheet, true),
                              child: const Text('Aplicar')),
                        ])))));
    if (apply == true && mounted) {
      setState(() {
        kind = chosenKind;
        year = chosenYear;
        textOnly = onlyText;
        reset();
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Biblioteca europea'), actions: [
        IconButton(
            tooltip: 'Actualizar catálogo europeo',
            icon: const Icon(Icons.refresh),
            onPressed: () => setState(() {
                  loading = repository.catalogue(refresh: true);
                  reset();
                }))
      ]),
      body: FutureBuilder<List<Json>>(
          future: loading,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _EuropeanRetry(
                  message: 'No se ha podido cargar la biblioteca europea.',
                  retry: () => setState(
                      () => loading = repository.catalogue(refresh: true)));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final all = snapshot.data!;
            final needle = normalize(query.trim());
            final rows = all
                .where((n) =>
                    (kind == 'Todos' || n['kind'] == kind) &&
                    (year == 'Todos' || n['year'] == year) &&
                    (!textOnly || (n['readableEditions'] as num) > 0) &&
                    (!saved || widget.store.has('bookmarks', n['id'])) &&
                    (needle.isEmpty ||
                        (n['_search'] as String).contains(needle)))
                .toList();
            final result = ResultPage(rows, page, size);
            return SearchPageBody(
                resultsController: scroll,
                header: [
                  TextField(
                      decoration: InputDecoration(
                          hintText: 'Nombre, referencia o CELEX',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: IconButton(
                              tooltip: 'Filtrar biblioteca europea',
                              icon: const Icon(Icons.tune),
                              onPressed: () => filters(all))),
                      onChanged: (v) {
                        debounce?.cancel();
                        debounce = Timer(const Duration(milliseconds: 300), () {
                          if (mounted) {
                            setState(() {
                              query = v;
                              reset();
                            });
                          }
                        });
                      }),
                  const SizedBox(height: 8),
                  Wrap(spacing: 8, children: [
                    FilterChip(
                        label: const Text('Guardadas'),
                        selected: saved,
                        onSelected: (v) => setState(() {
                              saved = v;
                              reset();
                            })),
                    if (kind != 'Todos')
                      InputChip(
                          label: Text(kind),
                          onDeleted: () => setState(() {
                                kind = 'Todos';
                                reset();
                              })),
                    if (year != 'Todos')
                      InputChip(
                          label: Text(year),
                          onDeleted: () => setState(() {
                                year = 'Todos';
                                reset();
                              })),
                    if (textOnly)
                      InputChip(
                          label: const Text('Con lectura'),
                          onDeleted: () => setState(() {
                                textOnly = false;
                                reset();
                              })),
                  ])
                ],
                footer: PageControls(
                    total: rows.length,
                    page: result.page,
                    size: size,
                    onPage: (v) => setState(() {
                          page = v;
                          if (scroll.hasClients) scroll.jumpTo(0);
                        }),
                    onSize: (v) => setState(() {
                          size = v;
                          reset();
                        })),
                resultCount: result.items.length,
                resultBuilder: (context, i) {
                  final n = result.items[i];
                  return ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 8, horizontal: 4),
                      title: Text(n['title'],
                          maxLines: 3, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${n['kind']} · ${n['celex']}\n${(n['readableEditions'] as num) > 0 ? '${n['editions']} ediciones y documentos' : 'Ficha y fuente oficial'}'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => push(
                          context,
                          FullEuropeanNormPage(
                              store: widget.store,
                              summary: n,
                              repository: repository)));
                });
          }));
}

class _EuropeanRetry extends StatelessWidget {
  final String message;
  final VoidCallback retry;
  const _EuropeanRetry({required this.message, required this.retry});
  @override
  Widget build(BuildContext context) => Center(
      child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(message),
            const SizedBox(height: 16),
            FilledButton(onPressed: retry, child: const Text('Reintentar'))
          ])));
}

class FullEuropeanNormPage extends StatefulWidget {
  final AppStore store;
  final Json summary;
  final EuropeanRepository? repository;
  const FullEuropeanNormPage(
      {super.key, required this.store, required this.summary, this.repository});
  @override
  State<FullEuropeanNormPage> createState() => _FullEuropeanNormPageState();
}

class _FullEuropeanNormPageState extends State<FullEuropeanNormPage> {
  late final repository = widget.repository ?? EuropeanRepository(widget.store);
  late Future<Json> loading = openNorm();
  Future<List<Json>>? documents;
  int selected = -1, page = 0;
  String kind = 'article_candidate', query = '';
  bool preparing = false, savingOffline = false;
  int savedPages = 0, totalPages = 0;
  final scroll = ScrollController();
  Future<Json> openNorm() async {
    final norm = Json.from(
        await repository.object(Json.from(widget.summary['manifest'])));
    if (norm['id'] != widget.summary['id'] ||
        norm['schemaVersion'] != 1 ||
        norm['versions'] is! List ||
        (norm['versions'] as List).isEmpty) {
      throw StateError('La referencia no corresponde a esta norma.');
    }
    return norm;
  }

  Future<List<Json>> openVersion(Json version) async {
    final refs =
        (version['readingDocuments'] as List).map((v) => Json.from(v)).toList();
    final result = <Json>[];
    for (var start = 0; start < refs.length; start += 4) {
      final end = (start + 4).clamp(0, refs.length);
      result.addAll(await Future.wait(refs.sublist(start, end).map(
          (ref) async => <String, dynamic>{
                ...Json.from(await repository.object(ref)),
                '_referenceHash': ref['sha256']
              })));
    }
    if (result.any((d) => d['celex'] != version['celex'])) {
      throw StateError('Edición de documento incompatible.');
    }
    return result;
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  Future<void> saveOffline(Json norm, Json version, List<Json> docs) async {
    if (savingOffline) return;
    setState(() {
      savingOffline = true;
      savedPages = 0;
      totalPages =
          docs.fold<int>(0, (sum, d) => sum + (d['pages'] as List).length);
    });
    try {
      for (final document in docs) {
        for (final ref in document['pages'] as List) {
          if (!mounted) return;
          await repository.compressed(Json.from(ref));
          if (mounted) setState(() => savedPages++);
        }
      }
      await widget.store.saveEuropeanNorm({
        ...widget.summary,
        'source': 'EUR-Lex',
        'jurisdiction': 'Unión Europea',
        'europeanManifest': widget.summary['manifest'],
        'europeanSelectedCelex': version['celex'],
        'latestVersion': version['celex'],
        'sourceUrl': version['sourceUrl'],
        'count': 0,
        'europeanOffline': true,
        'downloadedAt': DateTime.now().toUtc().toIso8601String()
      });
      if (mounted) toast(context, 'Edición guardada para leer sin conexión.');
    } finally {
      if (mounted) setState(() => savingOffline = false);
    }
  }

  Future<void> prepareStudy() async {
    if (preparing) return;
    setState(() => preparing = true);
    try {
      await perform(context, () async {
        final norm = await loading;
        final editions =
            (norm['versions'] as List).map((v) => Json.from(v)).toList();
        final chosen = selected >= 0
            ? selected
            : preferredEuropeanEdition(editions, DateTime.now());
        final edition = editions[chosen];
        final docs = await (documents ?? openVersion(edition));
        if (!europeanLiteralStudyAllowed(norm, edition, docs)) {
          throw StateError(
              'Esta edición requiere revisión antes de preparar tarjetas. Puedes consultar su texto y originales.');
        }
        final units = <Json>[];
        final titles = <String>{};
        for (var d = 0; d < docs.length; d++) {
          final document = docs[d];
          if (document['sourceParser'] != 'eu-html-leaf-paragraphs-2' ||
              (document['warnings'] as List).isNotEmpty) {
            continue;
          }
          for (final value in document['units'] as List) {
            final unit = Json.from(value);
            if (unit['kind'] != 'article_candidate') continue;
            if (!titles.add(normalize(unit['title']))) {
              throw StateError(
                  'Hay numeraciones repetidas que deben revisarse.');
            }
            final count = (unit['paragraphCount'] as num).toInt();
            if (count > 5000) continue;
            final paragraphs =
                await repository.unitParagraphs(document, unit, limit: count);
            final hiddenHeading = RegExp(
                r'^(?:art[íi]culo\s+\d+|anexo(?:\s+[ivxlcdm\d]+)?$)',
                caseSensitive: false);
            if (paragraphs.skip(1).any(
                (p) => hiddenHeading.hasMatch(p['text'].toString().trim()))) {
              continue;
            }
            final text = paragraphs.map((p) => p['text']).join('\n');
            if (text.length > 1000000) continue;
            final hash = sha256.convert(utf8.encode(text)).toString();
            units.add({
              'id': '$d:${unit['id']}',
              'title': unit['title'],
              'type': 'precepto',
              'automaticStudyEligible': true,
              'versions': [
                {'text': text, 'hash': hash}
              ]
            });
          }
        }
        final title = norm['title'].toString();
        final short = title.length > 75 ? '${title.substring(0, 74)}…' : title;
        final inputNorm = {
          ...norm,
          'short': short,
          'latestVersion': edition['celex']
        };
        final available = <String, List<Json>>{};
        for (final format in ['qa', 'cloze', 'test', 'reference']) {
          final cards = await compute(buildLiteralCards, <String, dynamic>{
            'norm': inputNorm,
            'units': units,
            'format': format,
            'deck': '$short · ${edition['celex']} · $format'
          });
          if (cards.isNotEmpty) available[format] = cards;
        }
        if (available.isEmpty) {
          throw StateError(
              'No hay fragmentos adecuados para preparar un mazo en esta edición.');
        }
        if (!mounted) return;
        const labels = {
          'qa': 'Pregunta y respuesta',
          'cloze': 'Huecos',
          'test': 'Test literal',
          'reference': 'Identificar artículos'
        };
        final format = await showModalBottomSheet<String>(
            context: context,
            builder: (sheet) => SafeArea(
                child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('Preparar mazo literal',
                              style: Theme.of(context).textTheme.titleLarge),
                          Text(europeanEditionLabel(edition)),
                          const SizedBox(height: 12),
                          const Text(
                              'Tarjetas del texto seleccionado, sin revisión editorial. Comprueba la edición que necesitas estudiar.'),
                          for (final key in available.keys)
                            ListTile(
                                title: Text(labels[key]!),
                                subtitle:
                                    Text('${available[key]!.length} tarjetas'),
                                trailing: const Icon(Icons.add),
                                onTap: () => Navigator.pop(sheet, key)),
                        ]))));
        if (format != null) {
          final count = await widget.store.addPreparedCards(available[format]!);
          if (mounted) toast(context, '$count tarjetas añadidas.');
        }
      });
    } finally {
      if (mounted) setState(() => preparing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Norma europea'), actions: [
        if ((widget.summary['literalStudyEditions'] as num? ?? 0) > 0)
          IconButton(
              tooltip: 'Preparar mazo de esta edición',
              onPressed: preparing ? null : prepareStudy,
              icon: preparing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.style_outlined)),
      ]),
      body: FutureBuilder<Json>(
          future: loading,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _EuropeanRetry(
                  message: 'No se ha podido abrir esta norma.',
                  retry: () => setState(() => loading = openNorm()));
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final norm = snapshot.data!;
            final versions =
                (norm['versions'] as List).map((v) => Json.from(v)).toList();
            if (selected < 0) {
              final saved = widget.store
                  .list('norms')
                  .where((n) => n['id'] == widget.summary['id'])
                  .firstOrNull;
              final last = widget.store.data['lastReadUnits'] is Map
                  ? widget.store.data['lastReadUnits'][norm['id']]?.toString()
                  : null;
              final previous = versions.indexWhere((v) =>
                  v['celex'] == saved?['europeanSelectedCelex'] ||
                  (last?.startsWith('${v['celex']}:') ?? false));
              selected = previous >= 0
                  ? previous
                  : preferredEuropeanEdition(versions, DateTime.now());
              documents = openVersion(versions[selected]);
            }
            final edition = versions[selected];
            return FutureBuilder<List<Json>>(
                future: documents,
                builder: (context, content) {
                  if (content.hasError) {
                    return _EuropeanRetry(
                        message:
                            'No se ha podido cargar el índice de esta edición.',
                        retry: () =>
                            setState(() => documents = openVersion(edition)));
                  }
                  if (!content.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final docs = content.data!;
                  final units = <Json>[];
                  for (var d = 0; d < docs.length; d++) {
                    for (final unit in docs[d]['units'] as List) {
                      units.add({...Json.from(unit), '_document': d});
                    }
                  }
                  final lastKey = widget.store.data['lastReadUnits'] is Map
                      ? widget.store.data['lastReadUnits'][norm['id']]
                      : null;
                  final lastUnit = units
                      .where((u) =>
                          '${edition['celex']}:${docs[u['_document'] as int]['sourceHash']}:${u['id']}' ==
                          lastKey)
                      .firstOrNull;
                  final types = units.map((u) => u['kind'].toString()).toSet();
                  if (!types.contains(kind) && types.isNotEmpty) {
                    kind = types.first;
                  }
                  final needle = normalize(query);
                  final filtered = units
                      .where((u) =>
                          u['kind'] == kind &&
                          normalize(u['title'].toString()).contains(needle))
                      .toList();
                  final results = ResultPage(filtered, page, 20);
                  const labels = {
                    'article_candidate': 'Artículos',
                    'recitals': 'Considerandos',
                    'annex': 'Anexos',
                    'preamble': 'Preámbulo',
                    'heading': 'Encabezados',
                    'signature': 'Firmas',
                    'notes': 'Notas',
                    'adoption': 'Adopción',
                    'embedded_document': 'Documentos incorporados'
                  };
                  return SearchPageBody(
                      resultsController: scroll,
                      header: [
                        Text(norm['title'],
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleLarge),
                        if (lastUnit != null)
                          TextButton.icon(
                              onPressed: () => push(
                                  context,
                                  EuropeanUnitPage(
                                      store: widget.store,
                                      repository: repository,
                                      norm: norm,
                                      summary: widget.summary,
                                      edition: edition,
                                      document:
                                          docs[lastUnit['_document'] as int],
                                      unit: lastUnit)),
                              icon: const Icon(Icons.history),
                              label: const Text('Continuar lectura')),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<int>(
                            initialValue: selected,
                            isExpanded: true,
                            decoration: const InputDecoration(
                                labelText: 'Edición o documento'),
                            items: List.generate(
                                versions.length,
                                (i) => DropdownMenuItem(
                                    value: i,
                                    child: Text(
                                        europeanEditionLabel(versions[i]),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis))),
                            onChanged: (v) => setState(() {
                                  selected = v!;
                                  documents = openVersion(versions[selected]);
                                  page = 0;
                                  query = '';
                                })),
                        const SizedBox(height: 8),
                        Text(
                            'Consulta la edición aplicable en la fuente oficial. Los textos históricos y las correcciones no equivalen a una norma vigente.',
                            style: Theme.of(context).textTheme.bodySmall),
                        const SizedBox(height: 8),
                        if (types.isNotEmpty)
                          Row(children: [
                            Expanded(
                                child: TextField(
                                    decoration: const InputDecoration(
                                        hintText: 'Buscar en el índice',
                                        prefixIcon: Icon(Icons.search)),
                                    onChanged: (v) => setState(() {
                                          query = v;
                                          page = 0;
                                        }))),
                            PopupMenuButton<String>(
                                tooltip: 'Partes del documento',
                                icon: const Icon(Icons.toc),
                                onSelected: (v) => setState(() {
                                      kind = v;
                                      page = 0;
                                      query = '';
                                    }),
                                itemBuilder: (_) => types
                                    .map((v) => PopupMenuItem(
                                        value: v,
                                        child: Text(
                                            labels[v] ?? 'Otros apartados')))
                                    .toList())
                          ]),
                      ],
                      footer: filtered.isEmpty
                          ? null
                          : PageControls(
                              total: filtered.length,
                              page: results.page,
                              size: 20,
                              onPage: (v) => setState(() {
                                    page = v;
                                    if (scroll.hasClients) scroll.jumpTo(0);
                                  }),
                              onSize: (_) {}),
                      resultCount: results.items.length + 1,
                      resultBuilder: (context, i) {
                        if (i < results.items.length) {
                          final unit = results.items[i];
                          final document = docs[unit['_document'] as int];
                          return ListTile(
                              title: Text(unit['title'].toString().isEmpty
                                  ? (labels[unit['kind']] ?? 'Texto')
                                  : unit['title']),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: () => push(
                                  context,
                                  EuropeanUnitPage(
                                      store: widget.store,
                                      repository: repository,
                                      norm: norm,
                                      summary: widget.summary,
                                      edition: edition,
                                      document: document,
                                      unit: unit)));
                        }
                        return Details('Fuente y opciones', children: [
                          Text(norm['title']),
                          Text(edition['celex']),
                          TextButton.icon(
                              onPressed: () =>
                                  openSource(context, edition['sourceUrl']),
                              icon: const Icon(Icons.open_in_new),
                              label: const Text('Publicación oficial')),
                          if (docs.isEmpty)
                            const Text(
                                'Esta ficha no tiene texto de lectura preparado. Puedes consultar los archivos originales disponibles.'),
                          if ((edition['resources'] as List).isNotEmpty)
                            TextButton.icon(
                                onPressed: () => push(
                                    context,
                                    EuropeanResourcesPage(
                                        resources:
                                            (edition['resources'] as List)
                                                .map((r) => Json.from(r))
                                                .toList())),
                                icon: const Icon(Icons.description_outlined),
                                label: const Text('Archivos originales')),
                          if (docs.isNotEmpty)
                            OutlinedButton.icon(
                                onPressed: savingOffline
                                    ? null
                                    : () => perform(context,
                                        () => saveOffline(norm, edition, docs)),
                                icon: const Icon(Icons.download_outlined),
                                label: Text(savingOffline
                                    ? 'Guardando $savedPages/$totalPages'
                                    : 'Guardar texto sin conexión')),
                          OutlinedButton.icon(
                              onPressed: () => perform(context, () async {
                                    await widget.store.saveEuropeanNorm({
                                      ...widget.summary,
                                      'source': 'EUR-Lex',
                                      'jurisdiction': 'Unión Europea',
                                      'europeanManifest':
                                          widget.summary['manifest'],
                                      'sourceUrl': edition['sourceUrl'],
                                      'latestVersion': edition['celex'],
                                      'count': 0
                                    });
                                    await widget.store
                                        .toggle('bookmarks', norm['id']);
                                  }),
                              icon: const Icon(Icons.bookmark_outline),
                              label: Text(
                                  widget.store.has('bookmarks', norm['id'])
                                      ? 'Quitar referencia'
                                      : 'Guardar referencia')),
                        ]);
                      });
                });
          }));
}

class EuropeanUnitPage extends StatefulWidget {
  final AppStore store;
  final EuropeanRepository repository;
  final Json norm, summary, edition, document, unit;
  const EuropeanUnitPage(
      {super.key,
      required this.store,
      required this.repository,
      required this.norm,
      required this.summary,
      required this.edition,
      required this.document,
      required this.unit});
  @override
  State<EuropeanUnitPage> createState() => _EuropeanUnitPageState();
}

class _EuropeanUnitPageState extends State<EuropeanUnitPage> {
  int offset = 0, pageSize = 20;
  String get readingKey =>
      '${widget.edition['celex']}:${widget.document['sourceHash']}:${widget.unit['id']}';
  @override
  void initState() {
    super.initState();
    final saved = widget.store.readingPosition(widget.norm['id'], readingKey);
    if (saved['unitVersionHash'] == widget.document['_referenceHash']) {
      final value = saved['fragment'];
      if (value is int &&
          value >= 0 &&
          value < (widget.unit['paragraphCount'] as num)) {
        offset = (value ~/ pageSize) * pageSize;
      }
    }
  }

  late Future<List<Json>> loading = load();
  final scroll = ScrollController();
  Future<List<Json>> load() async {
    final result = await widget.repository.unitParagraphs(
        widget.document, widget.unit,
        offset: offset, limit: pageSize);
    try {
      await widget.store.rememberEuropeanReading({
        ...widget.summary,
        'source': 'EUR-Lex',
        'jurisdiction': 'Unión Europea',
        'europeanManifest': widget.summary['manifest'],
        'europeanSelectedCelex': widget.edition['celex'],
        'sourceUrl': widget.edition['sourceUrl'],
        'latestVersion': widget.edition['celex'],
        'count': 0
      }, readingKey, widget.document['_referenceHash'], offset);
    } catch (_) {
      if (mounted) toast(context, 'No se pudo guardar la posición de lectura.');
    }
    return result;
  }

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = (widget.unit['paragraphCount'] as num).toInt();
    return Scaffold(
        appBar: AppBar(title: Text(widget.unit['title'].toString()), actions: [
          IconButton(
              tooltip: 'Fuente oficial',
              onPressed: () => openSource(context, widget.edition['sourceUrl']),
              icon: const Icon(Icons.open_in_new))
        ]),
        body: FutureBuilder<List<Json>>(
            future: loading,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _EuropeanRetry(
                    message: 'No se ha podido abrir este fragmento.',
                    retry: () => setState(() => loading = load()));
              }
              if (!snapshot.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              final rows = snapshot.data!;
              return SearchPageBody(
                  resultsController: scroll,
                  header: [
                    Text(europeanEditionLabel(widget.edition),
                        style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    if (widget.document['sourceParser']
                        .toString()
                        .startsWith('eu-pdf-ocr'))
                      const Text(
                          'Texto obtenido por OCR; comprueba el original.',
                          style: TextStyle(fontSize: 12)),
                    const Text(
                        'Extracción de la fuente, sin revisión editorial. Consulta el original si hay dudas.',
                        style: TextStyle(fontSize: 12))
                  ],
                  footer: PageControls(
                      total: count,
                      page: offset ~/ pageSize,
                      size: pageSize,
                      onPage: (v) => setState(() {
                            offset = v * pageSize;
                            loading = load();
                            if (scroll.hasClients) scroll.jumpTo(0);
                          }),
                      onSize: (v) => setState(() {
                            pageSize = v;
                            offset = (offset ~/ v) * v;
                            loading = load();
                          })),
                  resultCount: rows.length,
                  resultBuilder: (context, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: SelectableText(rows[i]['text'],
                          style: const TextStyle(fontSize: 19, height: 1.55))));
            }));
  }
}

class EuropeanResourcesPage extends StatefulWidget {
  final List<Json> resources;
  const EuropeanResourcesPage({super.key, required this.resources});
  @override
  State<EuropeanResourcesPage> createState() => _EuropeanResourcesPageState();
}

class _EuropeanResourcesPageState extends State<EuropeanResourcesPage> {
  int page = 0, size = 20;
  @override
  Widget build(BuildContext context) {
    final result = ResultPage(widget.resources, page, size);
    return Scaffold(
        appBar: AppBar(title: const Text('Archivos originales')),
        body: SearchPageBody(
            header: const [
              Text('Documentos y figuras de la edición seleccionada.')
            ],
            footer: PageControls(
                total: widget.resources.length,
                page: result.page,
                size: size,
                onPage: (v) => setState(() => page = v),
                onSize: (v) => setState(() {
                      size = v;
                      page = 0;
                    })),
            resultCount: result.items.length,
            resultBuilder: (context, i) {
              final resource = result.items[i];
              final mime = resource['mime'].toString().split(';').first;
              return ListTile(
                  title: Text('Original ${result.page * size + i + 1}'),
                  subtitle: Text(mime.startsWith('image/')
                      ? 'Imagen de la fuente'
                      : mime.contains('pdf')
                          ? 'Documento PDF'
                          : 'Documento de la fuente'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => openSource(context, resource['url']));
            }));
  }
}
