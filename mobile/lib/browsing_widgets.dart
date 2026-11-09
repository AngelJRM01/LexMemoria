import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'catalogue.dart';
import 'models.dart';

Future<CatalogueFilters?> showCatalogueFilters(
    BuildContext context, List<Json> norms, CatalogueFilters current) async {
  var subject = current.subject,
      scope = current.scope,
      community = current.community;
  return showModalBottomSheet<CatalogueFilters>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
          child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
              child: StatefulBuilder(
                  builder: (context, update) => Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text('Filtrar contenido',
                                style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: 20),
                            DropdownButtonFormField<String>(
                                initialValue: subject,
                                isExpanded: true,
                                decoration:
                                    const InputDecoration(labelText: 'Materia'),
                                items: ['Todas', ...catalogueSubjects(norms)]
                                    .map((v) => DropdownMenuItem(
                                        value: v, child: Text(v)))
                                    .toList(),
                                onChanged: (v) => subject = v!),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                                key: ValueKey(scope),
                                initialValue: scope,
                                isExpanded: true,
                                decoration:
                                    const InputDecoration(labelText: 'Ámbito'),
                                items: [
                                  'Todos',
                                  'Estatal',
                                  'Autonómico',
                                  'Europeo'
                                ]
                                    .map((v) => DropdownMenuItem(
                                        value: v, child: Text(v)))
                                    .toList(),
                                onChanged: (v) => update(() {
                                      scope = v!;
                                      if (scope != 'Autonómico') {
                                        community = 'Todas';
                                      }
                                    })),
                            const SizedBox(height: 16),
                            DropdownButtonFormField<String>(
                                key: ValueKey(community),
                                initialValue: community,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                    labelText: 'Comunidad autónoma'),
                                items: ['Todas', ...catalogueCommunities(norms)]
                                    .map((v) => DropdownMenuItem(
                                        value: v, child: Text(v)))
                                    .toList(),
                                onChanged: (v) => update(() {
                                      community = v!;
                                      if (community != 'Todas') {
                                        scope = 'Autonómico';
                                      }
                                    })),
                            const SizedBox(height: 24),
                            FilledButton(
                                onPressed: () => Navigator.pop(
                                    sheet,
                                    CatalogueFilters(
                                        subject: subject,
                                        scope: scope,
                                        community: community)),
                                child: const Text('Aplicar filtros')),
                          ])))));
}

class PageControls extends StatelessWidget {
  final int total, page, size;
  final ValueChanged<int> onPage, onSize;
  const PageControls(
      {super.key,
      required this.total,
      required this.page,
      required this.size,
      required this.onPage,
      required this.onSize});
  @override
  Widget build(BuildContext context) {
    final pages = total == 0 ? 1 : (total / size).ceil();
    return Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(children: [
          IconButton(
              tooltip: 'Página anterior',
              onPressed: page == 0 ? null : () => onPage(page - 1),
              icon: const Icon(Icons.chevron_left)),
          Expanded(
              child: TextButton(
                  onPressed: pages < 2
                      ? null
                      : () async {
                          final value = await showDialog<int>(
                              context: context,
                              builder: (_) =>
                                  _PageJumpDialog(page: page, pages: pages));
                          if (value != null && context.mounted) onPage(value);
                        },
                  child: Text('Página ${page + 1} de $pages',
                      textAlign: TextAlign.center))),
          IconButton(
              tooltip: 'Página siguiente',
              onPressed: page + 1 >= pages ? null : () => onPage(page + 1),
              icon: const Icon(Icons.chevron_right)),
          PopupMenuButton<int>(
              tooltip: 'Resultados por página',
              initialValue: size,
              onSelected: onSize,
              itemBuilder: (_) => [20, 50, 100]
                  .map((n) =>
                      PopupMenuItem(value: n, child: Text('$n por página')))
                  .toList(),
              icon: const Icon(Icons.format_list_numbered)),
        ]));
  }
}

class _PageJumpDialog extends StatefulWidget {
  final int page, pages;
  const _PageJumpDialog({required this.page, required this.pages});
  @override
  State<_PageJumpDialog> createState() => _PageJumpDialogState();
}

class _PageJumpDialogState extends State<_PageJumpDialog> {
  late final TextEditingController controller =
      TextEditingController(text: '${widget.page + 1}');
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('Ir a página'),
          content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                  labelText: 'Página entre 1 y ${widget.pages}')),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () {
                  final n = int.tryParse(controller.text);
                  if (n != null && n >= 1 && n <= widget.pages) {
                    Navigator.pop(context, n - 1);
                  }
                },
                child: const Text('Ir'))
          ]);
}
