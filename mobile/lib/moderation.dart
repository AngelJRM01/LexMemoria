import 'package:flutter/material.dart';
import 'models.dart';
import 'store.dart';
import 'remote.dart';
import 'widgets.dart';
import 'collaboration.dart' show collaborationText, SharedDeckPage;

class ModerationPage extends StatefulWidget {
  final AppStore store;
  const ModerationPage({super.key, required this.store});
  @override
  State<ModerationPage> createState() => _ModerationPageState();
}

class _ModerationPageState extends State<ModerationPage> {
  List<Json>? rows;
  bool busy = false;
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    await perform(context, action);
    if (mounted) setState(() => busy = false);
  }

  Future<void> load() async {
    final result = await RemoteSync(widget.store)
        .request('GET', '/v1/admin/collaboration');
    if (mounted) {
      setState(() =>
          rows = (result['items'] as List).map((r) => Json.from(r)).toList());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Revisión de materiales')),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              const Text(
                  'La moderación de uso no certifica la corrección jurídica. El servidor exige rol editorial y pasarela MFA configurada.'),
              OutlinedButton(
                  onPressed: busy ? null : () => run(load),
                  child: const Text('Consultar incidencias')),
            ])),
        Expanded(
            child: rows == null
                ? const Center(child: Text('Consulta protegida'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                    itemCount: rows!.length,
                    itemBuilder: (context, index) {
                      final row = rows![index];
                      final report = row['kind'] == 'collaboration_report';
                      return Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(report
                                        ? 'Reporte · ${row['severity'] ?? 'normal'}'
                                        : 'Solicitud de publicación'),
                                    Text(row['reason'] ?? row['subject'] ?? ''),
                                    Text(
                                        'Estado: ${row['status'] ?? row['state']}'),
                                    if (!report)
                                      TextButton(
                                          onPressed: busy
                                              ? null
                                              : () => run(() async {
                                                    await Navigator.of(context)
                                                        .push(MaterialPageRoute<
                                                                void>(
                                                            builder: (_) =>
                                                                SharedDeckPage(
                                                                    store: widget
                                                                        .store,
                                                                    id: row[
                                                                        'deckId'],
                                                                    moderation:
                                                                        true)));
                                                  }),
                                          child: const Text(
                                              'Previsualizar contenido')),
                                    Wrap(spacing: 8, children: [
                                      for (final action in report
                                          ? {
                                              'triaged': 'Clasificar',
                                              'resolved': 'Resolver',
                                              'dismissed': 'Desestimar'
                                            }.entries
                                          : {
                                              'allow': 'Admitir publicación',
                                              'hide': 'Ocultar'
                                            }.entries)
                                        TextButton(
                                            onPressed: busy
                                                ? null
                                                : () => run(() async {
                                                      final reason =
                                                          await collaborationText(
                                                              context,
                                                              'Motivo (mínimo 20 caracteres)',
                                                              maxLength: 2000);
                                                      if (reason == null) {
                                                        return;
                                                      }
                                                      await RemoteSync(
                                                              widget.store)
                                                          .send(
                                                              report
                                                                  ? '/v1/admin/collaboration/reports/${row['id']}/decision'
                                                                  : '/v1/admin/collaboration/${row['deckId']}/decision',
                                                              body:
                                                                  report
                                                                      ? {
                                                                          'status':
                                                                              action.key,
                                                                          'reason':
                                                                              reason
                                                                        }
                                                                      : {
                                                                          'action':
                                                                              action.key,
                                                                          'reason':
                                                                              reason
                                                                        });
                                                      await load();
                                                    }),
                                            child: Text(action.value)),
                                    ]),
                                  ])));
                    })),
      ]));
}
