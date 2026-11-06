import 'package:flutter/material.dart' hide Badge;
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'models.dart';
import 'store.dart';
import 'widgets.dart';
import 'study.dart';
import 'remote.dart';
import 'reading.dart';
import 'catalogue.dart';
import 'browsing_widgets.dart';
import 'account_pages.dart' show PersonalProfilePage;

class LibraryPage extends StatefulWidget {
  final AppStore store;
  const LibraryPage({super.key, required this.store});
  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  String query = '', subject = 'Todas', scope = 'Todos', community = 'Todas';
  int page = 0, pageSize = 20;
  final pagingController = ScrollController();
  void resetPage() {
    page = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && pagingController.hasClients) pagingController.jumpTo(0);
    });
  }

  void pageChanged(int value) {
    setState(() => page = value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && pagingController.hasClients) pagingController.jumpTo(0);
    });
  }

  @override
  void dispose() {
    pagingController.dispose();
    super.dispose();
  }

  bool saved = false;
  Future<void> filters() async {
    final result = await showCatalogueFilters(context, widget.store.catalogue,
        CatalogueFilters(subject: subject, scope: scope, community: community));
    if (result != null && mounted) {
      setState(() {
        subject = result.subject;
        scope = result.scope;
        community = result.community;
        resetPage();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = widget.store.catalogue
        .where((n) =>
            CatalogueFilters(
                    subject: subject, scope: scope, community: community)
                .matches(n) &&
            (!saved || widget.store.has('bookmarks', n['id'])) &&
            normalize('${n['title']} ${n['id']} ${n['authority'] ?? ''}')
                .contains(normalize(query)))
        .toList();
    final slice = ResultPage(rows, page, pageSize);
    final shown = slice.items;
    return SearchPageBody(
        resultsController: pagingController,
        footer: PageControls(
            total: rows.length,
            page: slice.page,
            size: pageSize,
            onPage: pageChanged,
            onSize: (v) {
              setState(() {
                pageSize = v;
                resetPage();
              });
              pageChanged(0);
            }),
        header: [
          Text('Tu biblioteca jurídica',
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          TextField(
              decoration: InputDecoration(
                  hintText: 'Título o referencia de norma',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: IconButton(
                      tooltip: 'Filtros de biblioteca',
                      onPressed: filters,
                      icon: const Icon(Icons.tune))),
              onChanged: (v) => setState(() {
                    query = v;
                    resetPage();
                  })),
          const SizedBox(height: 10),
          Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChip(
                    label: const Text('Guardadas'),
                    selected: saved,
                    onSelected: (v) => setState(() {
                          saved = v;
                          resetPage();
                        })),
                if (subject != 'Todas')
                  InputChip(
                      label: Text(subject),
                      onDeleted: () => setState(() {
                            subject = 'Todas';
                            resetPage();
                          })),
                if (scope != 'Todos')
                  InputChip(
                      label: Text(scope),
                      onDeleted: () => setState(() {
                            scope = 'Todos';
                            resetPage();
                          })),
                if (community != 'Todas')
                  InputChip(
                      label: Text(community),
                      onDeleted: () => setState(() {
                            community = 'Todas';
                            resetPage();
                          })),
                if (widget.store.hasRemoteServer)
                  IconButton(
                      tooltip: 'Sincronizar biblioteca',
                      onPressed: widget.store.syncing
                          ? null
                          : () => perform(context, widget.store.fetchCatalogue),
                      icon: const Icon(Icons.sync)),
              ]),
          if (widget.store.syncing) const LinearProgressIndicator(),
        ],
        resultCount: shown.length,
        resultBuilder: (context, i) {
          final n = shown[i];
          return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Paper(
                  child: InkWell(
                      onTap: () => push(
                          context, NormPage(store: widget.store, id: n['id'])),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n['short'] ?? n['title'],
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium),
                            const SizedBox(height: 8),
                            Text(n['id'],
                                style: Theme.of(context).textTheme.bodySmall),
                            if (n['exhausted'] == true)
                              const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text(
                                      'Vigencia agotada según la fuente',
                                      style:
                                          TextStyle(color: Color(0xff946017)))),
                            if (n['units'] != null || n['packReady'] == true)
                              const Padding(
                                  padding: EdgeInsets.only(top: 8),
                                  child: Text('Disponible sin conexión')),
                          ]))));
        },
        children: [
          Text('${rows.length} normas',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 12),
          if (rows.isEmpty)
            const EmptyState(
                title: 'Sin coincidencias',
                detail: 'Prueba otro término o elimina los filtros.'),
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
  int indexPage = 0, indexSize = 50;
  final indexScroll = ScrollController();
  void resetIndex() {
    indexPage = 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && indexScroll.hasClients) indexScroll.jumpTo(0);
    });
  }

  void indexPageChanged(int value) {
    setState(() => indexPage = value);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && indexScroll.hasClients) indexScroll.jumpTo(0);
    });
  }

  @override
  void dispose() {
    indexScroll.dispose();
    super.dispose();
  }

  bool downloading = false;
  bool fullText = false, indexing = false;
  Map<String, String>? textIndex;
  String? indexedVersion;

  Future<void> searchText(Json norm, List<Json> units) async {
    setState(() {
      fullText = true;
      resetIndex();
    });
    if (indexedVersion == norm['latestVersion'] && textIndex != null) return;
    setState(() => indexing = true);
    try {
      final rows = units
          .map((u) => <String, dynamic>{
                'id': u['id'],
                'title': u['title'],
                'text':
                    (u['versions'] as List? ?? []).lastOrNull?['text'] ?? '',
              })
          .toList();
      final result = await compute(buildReadingIndex, rows);
      if (mounted) {
        setState(() {
          textIndex = result;
          indexedVersion = norm['latestVersion'];
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          fullText = false;
          resetIndex();
        });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text(
                'No se pudo preparar la búsqueda. Puedes seguir usando el índice.')));
      }
    } finally {
      if (mounted) setState(() => indexing = false);
    }
  }

  Future<void> read(Json norm, Json unit) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ReaderPage(
            store: widget.store,
            norm: norm,
            unit: unit,
            initialQuery: fullText &&
                    !normalize(unit['title']).contains(normalize(query.trim()))
                ? query.trim()
                : '')));
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final norm =
          widget.store.catalogue.firstWhere((n) => n['id'] == widget.id);
      if (norm['units'] == null &&
          (norm['packReady'] == true || norm['bundledReady'] == true) &&
          mounted) {
        setState(() => downloading = true);
        await perform(context, () async {
          if (norm['bundledReady'] == true) {
            await widget.store.loadBundledPack(norm);
          } else {
            await widget.store.loadCachedNorm(norm);
          }
        });
        if (mounted) setState(() => downloading = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.store.catalogue.firstWhere((n) => n['id'] == widget.id);
    final all = (n['units'] as List? ?? []).map((u) => Json.from(u)).toList();
    final needle = normalize(query.trim());
    final units = all
        .where((u) =>
            (!fullText || !indexing) &&
            (fullText
                    ? (textIndex?[u['id']] ?? '')
                    : normalize('${u['title']}'))
                .contains(needle))
        .toList();
    final slice = ResultPage(units, indexPage, indexSize);
    final shown = slice.items;
    final last = widget.store.data['lastReadUnits'];
    final lastId = last is Map ? last[widget.id] : null;
    final lastUnit = all.where((u) => u['id'] == lastId).firstOrNull;
    final canResume = lastUnit != null &&
        savedReadingVersion(
                n, lastUnit, widget.store.readingPosition(widget.id, lastId)) !=
            null;
    return Scaffold(
        appBar: AppBar(title: const Text('Leer norma'), actions: [
          IconButton(
              tooltip: 'Tarjetas de esta norma',
              onPressed: () => push(
                  context,
                  PreparedDecksPage(
                      store: widget.store, initialQuery: widget.id)),
              icon: const Icon(Icons.style_outlined)),
          IconButton(
              tooltip: 'Fuente oficial',
              onPressed: () => openSource(context, n['sourceUrl']),
              icon: const Icon(Icons.open_in_new)),
          IconButton(
              tooltip: 'Guardar norma',
              onPressed: () => perform(
                  context, () => widget.store.toggle('bookmarks', widget.id)),
              icon: Icon(widget.store.has('bookmarks', widget.id)
                  ? Icons.bookmark
                  : Icons.bookmark_outline)),
        ]),
        body: SearchPageBody(
            resultsController: indexScroll,
            footer: all.isEmpty
                ? null
                : PageControls(
                    total: units.length,
                    page: slice.page,
                    size: indexSize,
                    onPage: indexPageChanged,
                    onSize: (v) {
                      setState(() {
                        indexSize = v;
                        resetIndex();
                      });
                      indexPageChanged(0);
                    }),
            header: [
              Text(n['short'] ?? n['title'],
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 12),
              if (n['exhausted'] == true)
                const Padding(
                    padding: EdgeInsets.only(bottom: 12),
                    child: Text(
                        'Vigencia agotada según la fuente. Consulta las fechas antes de estudiar.')),
              if (all.isNotEmpty) ...[
                if (canResume) ...[
                  OutlinedButton.icon(
                      onPressed: () => read(n, lastUnit),
                      icon: const Icon(Icons.bookmark_added_outlined),
                      label: Text('Continuar: ${lastUnit['title']}',
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                  const SizedBox(height: 12),
                ],
                TextField(
                    decoration: InputDecoration(
                        hintText: fullText
                            ? 'Buscar en el texto de esta norma'
                            : 'Buscar artículo en el índice',
                        prefixIcon: Icon(Icons.search)),
                    onChanged: (v) => setState(() {
                          query = v;
                          resetIndex();
                        })),
                const SizedBox(height: 8),
                Wrap(spacing: 8, children: [
                  ChoiceChip(
                      label: const Text('Índice'),
                      selected: !fullText,
                      onSelected: (_) => setState(() {
                            fullText = false;
                            resetIndex();
                          })),
                  ChoiceChip(
                      label: const Text('Texto'),
                      selected: fullText,
                      onSelected: indexing ? null : (_) => searchText(n, all)),
                ]),
                if (indexing) const LinearProgressIndicator(),
              ],
            ],
            resultCount: shown.length + 1,
            resultBuilder: (context, i) {
              if (i < shown.length) {
                final u = shown[i];
                return ListTile(
                    contentPadding: const EdgeInsets.symmetric(vertical: 6),
                    title: Text(u['title']),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => read(n, u));
              }
              return Details('Fuente, fechas y seguimiento', children: [
                Text(n['title']),
                Text(n['id']),
                Text('Ámbito: ${n['jurisdiction'] ?? 'No indicado'}'),
                Text('Publicación: ${displayDate(n['publicationDate'])}'),
                Text('Actualización: ${displayDate(n['sourceUpdatedAt'])}'),
                Text('Guardado: ${displayDate(n['downloadedAt'], time: true)}'),
                const Text(
                    'Fuente: Agencia Estatal Boletín Oficial del Estado. Texto consolidado informativo; comprueba la publicación oficial y las disposiciones transitorias.'),
                TextButton.icon(
                    onPressed: () => perform(context,
                        () => widget.store.toggle('follows', widget.id),
                        success: 'Seguimiento actualizado'),
                    icon: const Icon(Icons.notifications_outlined),
                    label: Text(widget.store.has('follows', widget.id)
                        ? 'Dejar de seguir'
                        : 'Seguir cambios de esta norma')),
                TextButton(
                    onPressed: () => openSource(context,
                        'https://www.boe.es/informacion/aviso_legal/index.php#reutilizacion'),
                    child: const Text('Condiciones de reutilización')),
              ]);
            },
            children: [
              if (all.isEmpty) ...[
                const Text('Guarda el texto para leerlo sin conexión.'),
                const SizedBox(height: 16),
                FilledButton.icon(
                    onPressed: downloading
                        ? null
                        : () async {
                            setState(() => downloading = true);
                            await perform(
                                context, () => widget.store.downloadNorm(n),
                                success: 'Texto disponible para leer');
                            if (mounted) setState(() => downloading = false);
                          },
                    icon: const Icon(Icons.download_outlined),
                    label: Text(downloading
                        ? 'Preparando texto…'
                        : 'Abrir y guardar texto')),
              ],
              if (all.isNotEmpty && units.isEmpty && !indexing)
                const EmptyState(
                    title: 'Sin coincidencias',
                    detail:
                        'Prueba otro término, número o título de artículo.'),
            ]));
  }
}

List<String> articleParagraphs(String text, String title) {
  final paragraphs =
      text.split('\n').where((line) => line.trim().isNotEmpty).toList();
  if (paragraphs.isNotEmpty && paragraphs.first.trim() == title.trim()) {
    paragraphs.removeAt(0);
  }
  return paragraphs;
}

class LegalParagraph extends StatelessWidget {
  final String text, query;
  final double fontSize;
  const LegalParagraph(
      {super.key, required this.text, this.query = '', this.fontSize = 19});
  @override
  Widget build(BuildContext context) {
    final marker =
        RegExp(r'^(\s*(?:\d+[.)]|[a-z]\))\s+)').firstMatch(text)?.end ?? 0;
    final needle = normalize(query.trim());
    final normalized = normalize(text);
    final spans = <TextSpan>[];
    var offset = 0;
    while (offset < text.length) {
      final match = needle.isEmpty ? -1 : normalized.indexOf(needle, offset);
      var end = match >= 0 ? match : text.length;
      if (end > offset) {
        if (offset < marker && end > marker) end = marker;
        spans.add(TextSpan(
            text: text.substring(offset, end),
            style: TextStyle(
                fontWeight:
                    offset < marker ? FontWeight.w700 : FontWeight.normal)));
        offset = end;
      } else {
        end = offset + needle.length;
        spans.add(TextSpan(
            text: text.substring(offset, end),
            style: const TextStyle(
                backgroundColor: Color(0xffffe4a0), color: Color(0xff302500))));
        offset = end;
      }
    }
    return Padding(
        padding: const EdgeInsets.only(bottom: 24),
        child: SelectableText.rich(TextSpan(children: spans),
            style: TextStyle(
                fontSize: fontSize, height: 1.65, letterSpacing: .1)));
  }
}

class ReaderPage extends StatefulWidget {
  final AppStore store;
  final Json norm, unit;
  final String initialQuery;
  const ReaderPage(
      {super.key,
      required this.store,
      required this.norm,
      required this.unit,
      this.initialQuery = ''});
  @override
  State<ReaderPage> createState() => _ReaderPageState();
}

class _ReaderPageState extends State<ReaderPage> {
  int version = 0, paragraph = 0;
  bool focus = true;
  String query = '';
  double fontSize = 19;
  DateTime? studyDate;
  final tts = FlutterTts();
  final resultsController = ScrollController();
  late final TextEditingController searchController;
  int naturalParagraph = 0;
  @override
  void initState() {
    super.initState();
    query = widget.initialQuery;
    searchController = TextEditingController(text: query);
    version = (widget.unit['versions'] as List).length - 1;
    final saved =
        widget.store.readingPosition(widget.norm['id'], widget.unit['id']);
    final restored = savedReadingVersion(widget.norm, widget.unit, saved);
    if (restored != null && query.isEmpty) {
      version = restored;
      final fragment = saved['fragment'];
      if (fragment is int && fragment >= 0) paragraph = fragment;
      naturalParagraph = paragraph;
    }
    if (query.isNotEmpty) paragraph = 0;
    fontSize = (widget.store.data['readerFontSize'] as num? ?? 19)
        .toDouble()
        .clamp(16, 28);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && version >= 0) {
        if (query.isEmpty) {
          rememberParagraph(paragraph);
        } else {
          final selected = (widget.unit['versions'] as List)[version];
          final fragments =
              articleParagraphs(selected['text'] ?? '', widget.unit['title']);
          final first = fragments
              .indexWhere((p) => normalize(p).contains(normalize(query)));
          if (first >= 0) rememberParagraph(first);
        }
      }
    });
  }

  void rememberParagraph(int index) {
    final versions = widget.unit['versions'] as List;
    if (studyDate != null || version < 0 || version >= versions.length) return;
    final selected = Json.from(versions[version]);
    final count =
        articleParagraphs(selected['text'] ?? '', widget.unit['title']).length;
    if (count == 0) return;
    naturalParagraph = index.clamp(0, count - 1);
    perform(
        context,
        () => widget.store.rememberReading(
            widget.norm, widget.unit, selected, naturalParagraph));
  }

  void resetScroll() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && resultsController.hasClients) {
          resultsController.jumpTo(0);
        }
      });

  void moveFragment(int index, int absoluteIndex) {
    setState(() => paragraph = index);
    rememberParagraph(absoluteIndex);
    resetScroll();
  }

  @override
  void dispose() {
    searchController.dispose();
    resultsController.dispose();
    tts.stop();
    super.dispose();
  }

  void options(List versions, int selectedIndex) => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
              child: StatefulBuilder(
                  builder: (context, update) => Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Opciones de lectura',
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 20),
                            Text('Tamaño del texto: ${fontSize.round()}'),
                            Slider(
                                value: fontSize,
                                min: 16,
                                max: 28,
                                divisions: 12,
                                onChanged: (value) {
                                  setState(() => fontSize = value);
                                  update(() {});
                                  widget.store.data['readerFontSize'] = value;
                                  widget.store.save();
                                }),
                            const SizedBox(height: 12),
                            DropdownButtonFormField<int>(
                                initialValue: selectedIndex,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText:
                                        'Redacción histórica · fecha de efecto'),
                                items: List.generate(
                                    versions.length,
                                    (i) => DropdownMenuItem(
                                        value: i,
                                        child: Text(displayDate(
                                            versions[i]['effectiveFrom'])))),
                                onChanged: (i) {
                                  setState(() {
                                    version = i!;
                                    studyDate = null;
                                    paragraph = 0;
                                    naturalParagraph = 0;
                                  });
                                  rememberParagraph(0);
                                  resetScroll();
                                  Navigator.pop(sheet);
                                }),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                                onPressed: () async {
                                  final date = await showDatePicker(
                                      context: sheet,
                                      initialDate: studyDate ?? DateTime.now(),
                                      firstDate: DateTime(1800),
                                      lastDate: DateTime.now()
                                          .add(const Duration(days: 3650)));
                                  if (date != null && mounted) {
                                    setState(() {
                                      studyDate = date;
                                      paragraph = 0;
                                    });
                                    resetScroll();
                                    if (sheet.mounted) Navigator.pop(sheet);
                                  }
                                },
                                icon: const Icon(Icons.history),
                                label: const Text(
                                    'Consultar una fecha de estudio')),
                            const SizedBox(height: 16),
                            const Text(
                                'Texto consolidado informativo del BOE, sin revisión editorial. La selección por fechas no sustituye comprobar vigencias parciales y disposiciones transitorias.'),
                            Text(
                                'Fuente actualizada: ${displayDate(widget.norm['sourceUpdatedAt'])}'),
                            TextButton(
                                onPressed: () => openSource(
                                    context, widget.norm['sourceUrl']),
                                child: const Text('Abrir fuente oficial')),
                          ])))));
  void notes() {
    final key = '${widget.norm['id']}:${widget.unit['id']}';
    final expected = (widget.store.data['notes'] as Map? ?? {})[key] as String?;
    final controller = TextEditingController(text: expected ?? '');
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (sheet) => SafeArea(
            child: Padding(
                padding: EdgeInsets.fromLTRB(
                    24, 0, 24, MediaQuery.viewInsetsOf(sheet).bottom + 28),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('Mis notas',
                          style: Theme.of(sheet).textTheme.titleLarge),
                      const SizedBox(height: 16),
                      TextField(
                          controller: controller,
                          minLines: 3,
                          maxLines: 7,
                          decoration: const InputDecoration(
                              hintText:
                                  'Escribe una nota sobre este artículo')),
                      const SizedBox(height: 16),
                      FilledButton(
                          onPressed: () => perform(sheet, () async {
                                await widget.store.updateNote(
                                    key, controller.text,
                                    expected: expected);
                                if (sheet.mounted) Navigator.pop(sheet);
                              }),
                          child: const Text('Guardar nota')),
                    ])))).whenComplete(controller.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final versions = widget.unit['versions'] as List;
    if (versions.isEmpty) {
      return Scaffold(
          appBar: AppBar(title: const Text('Leer artículo')),
          body: const PageBody(children: [
            EmptyState(
                title: 'Texto no disponible',
                detail: 'Vuelve al índice y consulta la fuente oficial.')
          ]));
    }
    final selection = studyDate == null
        ? null
        : resolveLegalVersions(
            versions.map((v) => Json.from(v)).toList(), studyDate!);
    final unavailable = selection != null && selection['selectedIndex'] == null;
    final selectedIndex = selection?['selectedIndex'] as int? ?? version;
    final v = Json.from(versions[selectedIndex]);
    final paragraphs = articleParagraphs(v['text'] ?? '', widget.unit['title']);
    final matches = <int>[
      for (var i = 0; i < paragraphs.length; i++)
        if (normalize(paragraphs[i]).contains(normalize(query))) i
    ];
    final current =
        matches.isEmpty ? 0 : paragraph.clamp(0, matches.length - 1);
    final reference =
        '${widget.norm['id']} · ${widget.unit['title']} · efecto ${displayDate(v['effectiveFrom'])}';
    return Scaffold(
        appBar: AppBar(title: const Text('Leer artículo'), actions: [
          IconButton(
              tooltip: 'Mis notas',
              onPressed: notes,
              icon: const Icon(Icons.edit_note)),
          IconButton(
              tooltip: 'Opciones de lectura',
              onPressed: () => options(versions, selectedIndex),
              icon: const Icon(Icons.tune)),
          PopupMenuButton<String>(
              tooltip: 'Más acciones',
              onSelected: (action) {
                if (action == 'source') {
                  openSource(context, widget.norm['sourceUrl']);
                }
                if (action == 'compare') {
                  push(context, ComparePage(unit: widget.unit));
                }
                if (unavailable) return;
                if (action == 'copy') {
                  Clipboard.setData(ClipboardData(text: reference));
                }
                if (action == 'listen') {
                  perform(context, () async {
                    await tts.setLanguage('es-ES');
                    await tts.speak(v['text']);
                  });
                }
                if (action == 'stop') tts.stop();
                if (action == 'card') {
                  push(
                      context,
                      CardEditor(
                          store: widget.store,
                          norm: widget.norm,
                          unit: widget.unit,
                          sourceVersion: v));
                }
              },
              itemBuilder: (_) => [
                    const PopupMenuItem(
                        value: 'source', child: Text('Fuente oficial')),
                    const PopupMenuItem(
                        value: 'compare', child: Text('Comparar versiones')),
                    if (!unavailable) ...[
                      const PopupMenuItem(
                          value: 'listen', child: Text('Escuchar artículo')),
                      const PopupMenuItem(
                          value: 'stop', child: Text('Detener lectura')),
                      const PopupMenuItem(
                          value: 'copy', child: Text('Copiar referencia')),
                      const PopupMenuItem(
                          value: 'card', child: Text('Crear tarjeta propia'))
                    ],
                  ]),
        ]),
        bottomNavigationBar: unavailable || !focus || matches.isEmpty
            ? null
            : SafeArea(
                minimum: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Row(children: [
                  IconButton(
                      tooltip: 'Apartado anterior',
                      onPressed: current == 0
                          ? null
                          : () =>
                              moveFragment(current - 1, matches[current - 1]),
                      icon: const Icon(Icons.chevron_left)),
                  Expanded(
                      child: Text(
                          'Fragmento ${current + 1} de ${matches.length}',
                          textAlign: TextAlign.center)),
                  IconButton(
                      tooltip: 'Apartado siguiente',
                      onPressed: current + 1 >= matches.length
                          ? null
                          : () =>
                              moveFragment(current + 1, matches[current + 1]),
                      icon: const Icon(Icons.chevron_right)),
                ])),
        body: SearchPageBody(
            resultsController: resultsController,
            header: [
              Text(widget.unit['title'],
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text('BOE · redacción de ${displayDate(v['effectiveFrom'])}',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              TextField(
                  controller: searchController,
                  decoration: const InputDecoration(
                      hintText: 'Buscar en este artículo',
                      prefixIcon: Icon(Icons.search),
                      isDense: true),
                  onChanged: (value) => setState(() {
                        paragraph = value.isEmpty ? naturalParagraph : 0;
                        query = value;
                        resetScroll();
                      })),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                ChoiceChip(
                    label: const Text('Por fragmentos'),
                    selected: focus,
                    onSelected: (_) {
                      setState(() => focus = true);
                      resetScroll();
                    }),
                ChoiceChip(
                    label: const Text('Artículo completo'),
                    selected: !focus,
                    onSelected: (_) {
                      setState(() => focus = false);
                      resetScroll();
                    }),
              ]),
            ],
            resultCount: unavailable || matches.isEmpty
                ? 0
                : focus
                    ? 1
                    : matches.length,
            resultBuilder: (context, i) {
              final index = focus ? matches[current] : matches[i];
              return LegalParagraph(
                  key: ValueKey('${v['hash']}:$index'),
                  text: paragraphs[index],
                  query: query,
                  fontSize: fontSize);
            },
            children: [
              if (selection != null)
                Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(selection['reason'])),
              if (unavailable)
                const EmptyState(
                    title: 'Redacción no resoluble para esta fecha',
                    detail:
                        'Consulta la fuente oficial o elige otra redacción en las opciones de lectura.')
              else if (matches.isEmpty)
                const EmptyState(
                    title: 'Sin coincidencias',
                    detail: 'Prueba otro término o vacía la búsqueda.')
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
  void initState() {
    super.initState();
    newer = (widget.unit['versions'] as List).length - 1;
  }

  @override
  Widget build(BuildContext context) {
    final versions = widget.unit['versions'] as List;
    final a = (versions[old]['text'] as String).split('\n');
    final b = (versions[newer]['text'] as String).split('\n');
    Widget selector(String label, int value, ValueChanged<int> change) =>
        DropdownButtonFormField<int>(
            initialValue: value,
            isExpanded: true,
            decoration: InputDecoration(labelText: label),
            items: List.generate(
                versions.length,
                (i) => DropdownMenuItem(
                    value: i,
                    child: Text(displayDate(versions[i]['effectiveFrom'])))),
            onChanged: (v) => change(v!));
    return Scaffold(
        appBar: AppBar(title: const Text('Comparar versiones')),
        body: PageBody(children: [
          Text(widget.unit['title'],
              style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 20),
          selector('Versión anterior', old, (v) => setState(() => old = v)),
          const SizedBox(height: 12),
          selector(
              'Versión posterior', newer, (v) => setState(() => newer = v)),
          const SizedBox(height: 20),
          const Text(
              'Comparación textual por párrafos. No determina por sí sola la vigencia ni la interpretación jurídica.'),
          const Section('Anterior · párrafos ausentes en la nueva versión'),
          ...a.map((line) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Paper(
                  child: Text('${b.contains(line) ? '= ' : '− '}$line',
                      style: TextStyle(
                          decoration: b.contains(line)
                              ? null
                              : TextDecoration.lineThrough))))),
          const Section('Posterior · párrafos añadidos'),
          ...b.map((line) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Paper(
                  child: Text('${a.contains(line) ? '= ' : '+ '}$line',
                      style: TextStyle(
                          fontWeight: a.contains(line)
                              ? FontWeight.normal
                              : FontWeight.bold))))),
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
    await perform(context, () => widget.store.fetchUpdates(nextPage: next),
        success: 'Novedades guardadas para consulta offline');
    if (mounted) setState(() => loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final events = store
        .list('legalUpdates')
        .where((e) =>
            (!followedOnly ||
                store.has('follows', e['normId'] ?? e['officialId'] ?? '')) &&
            (filter == 'Todos' ||
                (filter == 'Pendientes'
                    ? e['editorialState'] != 'approved'
                    : e['type'] == 'consolidation_available')))
        .toList();
    events.sort((a, b) => (b['detectedAt'] ?? '')
        .toString()
        .compareTo((a['detectedAt'] ?? '').toString()));
    return SearchPageBody(header: [
      Text('Legislación viva',
          style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 8),
      const SizedBox(height: 12),
      Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['Todos', 'Pendientes', 'Consolidados']
              .map((v) => ChoiceChip(
                  label: Text(v),
                  selected: filter == v,
                  onSelected: (_) => setState(() => filter = v)))
              .toList()),
      Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            FilterChip(
                label: const Text('Normas seguidas'),
                selected: followedOnly,
                onSelected: (v) => setState(() => followedOnly = v)),
            IconButton(
                tooltip: 'Actualizar novedades',
                onPressed: loading ? null : refresh,
                icon: const Icon(Icons.sync))
          ]),
      if (loading) const LinearProgressIndicator(),
      if (store.data['lastUpdatesSync'] != null)
        Text(
            'Última descarga: ${displayDate(store.data['lastUpdatesSync'], time: true)}',
            style: const TextStyle(fontSize: 12)),
      const SizedBox(height: 20),
    ], children: [
      if (events.isEmpty)
        const EmptyState(
            icon: Icons.notifications_none,
            title: 'Sin novedades para estos filtros',
            detail:
                'Sincroniza con el servidor o cambia los filtros. La ausencia de avisos no acredita que todas tus normas estén actualizadas.'),
      ...events.map((event) => Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Paper(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Badge(
                    event['type'] == 'consolidation_available'
                        ? 'Consolidación disponible'
                        : 'Documento publicado',
                    warning: true),
                const SizedBox(height: 12),
                Text(
                    event['title'] ??
                        event['normId'] ??
                        event['officialId'] ??
                        'Evento normativo',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                Text(
                    'Impacto: ${event['impact']} · revisión: ${event['editorialState']}'),
                Text('Publicación: ${displayDate(event['publicationDate'])}'),
                Text(
                    'Efecto: ${displayDate(event['effectiveFrom'], empty: 'Pendiente de análisis')}'),
                const SizedBox(height: 12),
                const Text(
                    'No se ha inferido automáticamente la vigencia ni la afectación jurídica.'),
                if (event['sourceUrl'] != null)
                  TextButton.icon(
                      onPressed: () => openSource(context, event['sourceUrl']),
                      icon: const Icon(Icons.open_in_new),
                      label: const Text('Consultar fuente')),
              ])))),
      if (store.data['updatesCursor'] != null)
        OutlinedButton(
            onPressed: loading ? null : () => refresh(next: true),
            child: const Text('Cargar más novedades')),
      Details('Normas que sigues', children: [
        ...store.catalogue.where((n) => store.has('follows', n['id'])).map(
            (n) => ListTile(
                leading: const Icon(Icons.bookmark_outline),
                title: Text(n['short'] ?? n['title']),
                subtitle: const Text('Seguimiento local'),
                onTap: () =>
                    push(context, NormPage(store: store, id: n['id'])))),
      ]),
      Details('Preferencias de avisos', children: [
        if ((store.profile['account'] as Map?)
                ?.containsKey('legalNotifications') ==
            true)
          ListTile(
              title: const Text('Configurar avisos jurídicos'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => push(context, PersonalProfilePage(store: store)))
        else
          SwitchListTile(
              value: store.data['internalAlerts'] ?? true,
              title: const Text('Avisos dentro de la aplicación'),
              onChanged: (v) {
                store.data['internalAlerts'] = v;
                store.save();
              }),
        if (store.data['remoteUserId'] != null) ...[
          OutlinedButton.icon(
              onPressed: () => perform(
                  context, RemoteSync(store).syncNotifications,
                  success: 'Suscripciones y bandeja sincronizadas'),
              icon: const Icon(Icons.sync),
              label: const Text('Sincronizar mis avisos')),
          ...store
              .list('notifications')
              .where((n) => n['category'] == null || n['category'] == 'legal')
              .map((n) => ListTile(
                  leading: Icon(n['read'] == true
                      ? Icons.drafts_outlined
                      : Icons.markunread_outlined),
                  title: Text('Actualización de ${n['normId']}'),
                  subtitle: Text(
                      'Disponible desde ${displayDate(n['createdAt'], time: true)}'),
                  onTap: () => perform(context, () async {
                        await RemoteSync(store)
                            .send('/v1/notifications/${n['id']}/read');
                        await RemoteSync(store).syncNotifications();
                      }))),
        ],
        const Text(
            'Las notificaciones push requieren Firebase/APNs y consentimiento del sistema.',
            style: TextStyle(fontSize: 12)),
      ]),
    ]);
  }
}
