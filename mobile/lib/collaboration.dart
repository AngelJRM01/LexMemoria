import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'remote.dart';
import 'store.dart';
import 'widgets.dart';
import 'study.dart' show CardEditor;

// V1 is private-only even when connecting to an older server.
const publicDeckPublicationEnabled = false;

Future<String?> collaborationText(BuildContext context, String title,
    {String initial = '', int maxLength = 120}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
              title: Text(title),
              content: TextField(
                  controller: controller,
                  maxLength: maxLength,
                  autofocus: true),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar')),
                FilledButton(
                    onPressed: () =>
                        Navigator.pop(context, controller.text.trim()),
                    child: const Text('Continuar'))
              ]));
  // Dialog animation may still reference its controller until the next frame.
  WidgetsBinding.instance.addPostFrameCallback((_) => controller.dispose());
  return result;
}

Future<String?> pickOwnDeck(BuildContext context, AppStore store) async {
  final remote = RemoteSync(store);
  var result = await remote.request('GET', '/v1/decks?limit=20');
  if (!context.mounted) return null;
  var query = '', cursor = '';
  var busy = false;
  final previous = <String>[];
  return showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(builder: (context, state) {
            Future<void> load(String nextCursor) async {
              if (busy) return;
              state(() => busy = true);
              await perform(context, () async {
                final value = await remote.request('GET',
                    '/v1/decks?limit=20&cursor=${Uri.encodeQueryComponent(nextCursor)}&q=${Uri.encodeQueryComponent(query)}');
                if (context.mounted) {
                  state(() {
                    result = value;
                    cursor = nextCursor;
                  });
                }
              });
              if (context.mounted) state(() => busy = false);
            }

            return Dialog(
                child: SizedBox(
                    width: 500,
                    height: MediaQuery.sizeOf(context).height * .75,
                    child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(children: [
                          const Text('Seleccionar un mazo propio'),
                          TextField(
                              decoration: const InputDecoration(
                                  labelText: 'Buscar título'),
                              onChanged: (v) => query = v,
                              onSubmitted: (_) {
                                previous.clear();
                                load('');
                              }),
                          TextButton(
                              onPressed: busy
                                  ? null
                                  : () {
                                      previous.clear();
                                      load('');
                                    },
                              child: Text(busy ? 'Cargando…' : 'Buscar')),
                          Expanded(
                              child: ListView(children: [
                            for (final deck in result['items'] as List)
                              ListTile(
                                  title: Text(deck['title']),
                                  onTap: () =>
                                      Navigator.pop(context, deck['id']))
                          ])),
                          Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton(
                                    onPressed: busy || previous.isEmpty
                                        ? null
                                        : () => load(previous.removeLast()),
                                    child: const Text('Anterior')),
                                TextButton(
                                    onPressed:
                                        busy || result['nextCursor'] == null
                                            ? null
                                            : () {
                                                previous.add(cursor);
                                                load(result['nextCursor']);
                                              },
                                    child: const Text('Siguiente')),
                              ]),
                        ]))));
          }));
}

Future<Json?> invitationSettings(BuildContext context,
    {required bool group, bool allowAdmin = false}) async {
  var role = group ? 'member' : 'reader';
  int? days = 7;
  var uses = 1;
  return showDialog<Json>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, state) => AlertDialog(
                title: const Text('Compartir por invitación'),
                content: SingleChildScrollView(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: const InputDecoration(labelText: 'Permiso'),
                      items: (group
                              ? {
                                  'member': 'Miembro',
                                  'collaborator': 'Colaborador',
                                  if (allowAdmin) 'admin': 'Administrador'
                                }
                              : {'reader': 'Lector', 'editor': 'Editor'})
                          .entries
                          .map((e) => DropdownMenuItem(
                              value: e.key, child: Text(e.value)))
                          .toList(),
                      onChanged: (v) => state(() => role = v!)),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<int>(
                      initialValue: 7,
                      decoration: const InputDecoration(labelText: 'Caducidad'),
                      items: const [
                        DropdownMenuItem(value: 1, child: Text('Un día')),
                        DropdownMenuItem(value: 7, child: Text('Una semana')),
                        DropdownMenuItem(value: 30, child: Text('30 días')),
                        DropdownMenuItem(value: 0, child: Text('Sin caducidad'))
                      ],
                      onChanged: (v) => state(() => days = v == 0 ? null : v)),
                  DropdownButtonFormField<int>(
                      initialValue: 1,
                      decoration:
                          const InputDecoration(labelText: 'Usos máximos'),
                      items: [1, 5, 20, 100]
                          .map((v) =>
                              DropdownMenuItem(value: v, child: Text('$v')))
                          .toList(),
                      onChanged: (v) => state(() => uses = v!)),
                  const Text(
                      'Puedes revocar el enlace. No se comparten notas ni progreso.'),
                ])),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () => Navigator.pop(
                          context, {'role': role, 'days': days, 'uses': uses}),
                      child: const Text('Crear enlace'))
                ],
              )));
}

Future<Json?> groupForm(BuildContext context, {Json? initial}) async {
  final name = TextEditingController(text: initial?['name'] ?? '');
  final description =
      TextEditingController(text: initial?['description'] ?? '');
  final topic = TextEditingController(text: initial?['topic'] ?? '');
  var type = initial?['type'] as String? ?? 'general';
  var icon = initial?['icon'] as String? ?? 'book';
  final form = GlobalKey<FormState>();
  final result = await showDialog<Json>(
      context: context,
      builder: (context) => StatefulBuilder(
          builder: (context, state) => AlertDialog(
                title: Text(
                    initial == null ? 'Crear grupo privado' : 'Editar grupo'),
                content: SingleChildScrollView(
                    child: Form(
                        key: form,
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                          TextFormField(
                              controller: name,
                              maxLength: 120,
                              decoration:
                                  const InputDecoration(labelText: 'Nombre'),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'Escribe un nombre'
                                  : null),
                          TextFormField(
                              controller: description,
                              maxLength: 1000,
                              decoration: const InputDecoration(
                                  labelText: 'Descripción opcional')),
                          TextFormField(
                              controller: topic,
                              maxLength: 120,
                              decoration: const InputDecoration(
                                  labelText: 'Temática opcional')),
                          DropdownButtonFormField<String>(
                              initialValue: type,
                              decoration:
                                  const InputDecoration(labelText: 'Tipo'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'general', child: Text('General')),
                                DropdownMenuItem(
                                    value: 'university',
                                    child: Text('Universidad')),
                                DropdownMenuItem(
                                    value: 'exam', child: Text('Oposiciones'))
                              ],
                              onChanged: (v) => state(() => type = v!)),
                          DropdownButtonFormField<String>(
                              initialValue: icon,
                              decoration:
                                  const InputDecoration(labelText: 'Icono'),
                              items: const [
                                DropdownMenuItem(
                                    value: 'book', child: Text('Libro')),
                                DropdownMenuItem(
                                    value: 'balance', child: Text('Balanza')),
                                DropdownMenuItem(
                                    value: 'school', child: Text('Estudio'))
                              ],
                              onChanged: (v) => state(() => icon = v!)),
                          const Text(
                              'Privado: sin notas, calificaciones ni historial de estudio compartidos.'),
                        ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () {
                        if (form.currentState!.validate()) {
                          Navigator.pop(context, {
                            'name': name.text.trim(),
                            'description': description.text.trim(),
                            'topic': topic.text.trim(),
                            'type': type,
                            'icon': icon
                          });
                        }
                      },
                      child: const Text('Guardar'))
                ],
              )));
  WidgetsBinding.instance.addPostFrameCallback((_) {
    name.dispose();
    description.dispose();
    topic.dispose();
  });
  return result;
}

class CollaborationPage extends StatelessWidget {
  final AppStore store;
  const CollaborationPage({super.key, required this.store});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Materiales compartidos')),
      body: PageBody(children: [
        const Text(
            'Colabora cuando te resulte útil. Tus notas, calificaciones y repasos siguen siendo privados.'),
        if (store.data['remoteUserId'] == null)
          const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Text(
                  'Conecta tu cuenta desde Perfil → Cuenta y copias para compartir. Puedes seguir estudiando sin cuenta.')),
        for (final item in {
          'mine': 'Compartir mis mazos',
          'shared': 'Mazos compartidos conmigo',
          'groups': 'Grupos privados',
          if (publicDeckPublicationEnabled)
            'catalogue': 'Explorar mazos públicos'
        }.entries)
          ListTile(
              title: Text(item.value),
              trailing: const Icon(Icons.chevron_right),
              onTap: store.data['remoteUserId'] == null
                  ? null
                  : () => push(context,
                      CollaborationListPage(store: store, kind: item.key))),
      ]));
}

class CollaborationListPage extends StatefulWidget {
  final AppStore store;
  final String kind;
  const CollaborationListPage(
      {super.key, required this.store, required this.kind});
  @override
  State<CollaborationListPage> createState() => _CollaborationListPageState();
}

class _CollaborationListPageState extends State<CollaborationListPage> {
  List<Json>? items;
  bool busy = false;
  String query = '', cursor = '', subject = '', norm = '';
  String? next;
  final history = <String>[];
  String get title => {
        'mine': 'Mis mazos en la cuenta',
        'shared': 'Compartidos conmigo',
        'groups': 'Grupos privados',
        'catalogue': 'Mazos públicos',
        'contacts': 'Compañeros',
        'invitations': 'Invitaciones',
        'notices': 'Mis avisos',
        'reports': 'Mis incidencias'
      }[widget.kind]!;
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    await perform(context, action);
    if (mounted) setState(() => busy = false);
  }

  Future<void> load() async {
    final path = switch (widget.kind) {
      'mine' =>
        '/v1/decks?cursor=${Uri.encodeQueryComponent(cursor)}&limit=20&q=${Uri.encodeQueryComponent(query)}',
      'shared' =>
        '/v1/collaboration/decks?cursor=${Uri.encodeQueryComponent(cursor)}&limit=20',
      'groups' =>
        '/v1/collaboration/groups?cursor=${Uri.encodeQueryComponent(cursor)}&limit=20',
      'contacts' =>
        '/v1/collaboration/contacts?cursor=${Uri.encodeQueryComponent(cursor)}&limit=20',
      'invitations' =>
        '/v1/collaboration/invitations?cursor=${Uri.encodeQueryComponent(cursor)}&limit=20',
      'notices' =>
        '/v1/notifications?cursor=${Uri.encodeQueryComponent(cursor)}&limit=20',
      'reports' =>
        '/v1/collaboration/reports?cursor=${Uri.encodeQueryComponent(cursor)}&limit=20',
      _ =>
        '/v1/collaboration/catalogue?q=${Uri.encodeQueryComponent(query)}&cursor=${Uri.encodeQueryComponent(cursor)}&limit=20&subject=${Uri.encodeQueryComponent(subject)}&normId=${Uri.encodeQueryComponent(norm)}',
    };
    if (widget.kind == 'catalogue' && !publicDeckPublicationEnabled) {
      throw StateError(
          'El catálogo público no está disponible en esta versión.');
    }
    final result = await RemoteSync(widget.store).request('GET', path);
    if (!mounted) return;
    setState(() {
      items = (result['items'] as List).map((r) => Json.from(r)).toList();
      next = result['nextCursor'];
    });
  }

  Future<void> invite(String id, bool group) async {
    final settings = await invitationSettings(context, group: group);
    if (settings == null) return;
    final result = await RemoteSync(widget.store)
        .send('/v1/collaboration/$id/invitations', body: settings);
    final link = '${widget.store.apiBase}${result['path']}';
    if (!mounted) return;
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
                title: const Text('Invitación privada'),
                content: Text(
                    'Usos: ${result['remaining']}. Caducidad: ${displayDate(result['expiresAt'], empty: 'Sin caducidad')}. Quien tenga el enlace podrá solicitar el permiso elegido. Puedes revocarlo desde Invitaciones.'),
                actions: [
                  TextButton(
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: link)),
                      child: const Text('Copiar enlace')),
                  TextButton(
                      onPressed: () =>
                          SharePlus.instance.share(ShareParams(text: link)),
                      child: const Text('Compartir')),
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cerrar'))
                ]));
  }

  Future<void> acceptLink() async {
    final text = await collaborationText(context, 'Pegar enlace de invitación',
        maxLength: 500);
    if (text == null || text.isEmpty) return;
    final uri = Uri.tryParse(text);
    final token = uri != null && uri.fragment.isNotEmpty ? uri.fragment : text;
    final result = await RemoteSync(widget.store)
        .send('/v1/collaboration/invitations/accept', body: {'token': token});
    if (mounted) {
      toast(context, 'Invitación aceptada. Material: ${result['targetId']}');
    }
    await load();
  }

  Widget resultItem(BuildContext context, int index) {
    final item = items![index];
    if (widget.kind == 'notices') {
      return Card(
          child: ListTile(
              title: Text(item['message'] ?? 'Novedad de una norma seguida'),
              subtitle: Text(displayDate(item['createdAt'], time: true)),
              trailing: item['read'] == true
                  ? const Icon(Icons.done)
                  : IconButton(
                      tooltip: 'Marcar leído',
                      icon: const Icon(Icons.mark_email_read_outlined),
                      onPressed: busy
                          ? null
                          : () => run(() async {
                                await RemoteSync(widget.store).send(
                                    '/v1/notifications/${item['id']}/read');
                                await load();
                              }))));
    }
    if (widget.kind == 'reports') {
      return Card(
          child: ListTile(
              title: Text(item['reason']),
              subtitle: Text(
                  'Estado: ${item['status']}\n${item['resolution'] ?? ''}'),
              trailing: TextButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                            final reason = await collaborationText(
                                context, 'Reclamación (mínimo 10 caracteres)',
                                maxLength: 2000);
                            if (reason == null) return;
                            await RemoteSync(widget.store)
                                .send('/v1/collaboration/reports', body: {
                              'targetId': item['targetId'],
                              'reason': reason,
                              'appealOf': item['id']
                            });
                            await load();
                          }),
                  child: const Text('Reclamar'))));
    }
    if (widget.kind == 'contacts') {
      final person = Json.from(item['person']);
      return Card(
          child: ListTile(
              title: Text(person['displayName'] ?? 'Usuario bloqueado'),
              subtitle: Text('${person['alias'] ?? ''} · ${item['status']}'),
              trailing: PopupMenuButton<String>(
                  onSelected: (action) => run(() async {
                        if (action == 'share') {
                          final deckId =
                              await pickOwnDeck(context, widget.store);
                          if (deckId == null) return;
                          await RemoteSync(widget.store).send(
                              '/v1/collaboration/$deckId/invitations',
                              body: {
                                'role': 'reader',
                                'recipientId': person['id']
                              });
                        } else if (action == 'accept') {
                          await RemoteSync(widget.store).send(
                              '/v1/collaboration/contacts/${item['id']}/accept');
                        } else if (action == 'block') {
                          await RemoteSync(widget.store)
                              .send('/v1/collaboration/blocks/${person['id']}');
                        } else {
                          await RemoteSync(widget.store).request('DELETE',
                              '/v1/collaboration/contacts/${item['id']}');
                        }
                        await load();
                      }),
                  itemBuilder: (_) => [
                        if (item['status'] == 'contact')
                          const PopupMenuItem(
                              value: 'share', child: Text('Compartir un mazo')),
                        if (item['incoming'] == true &&
                            item['status'] == 'request')
                          const PopupMenuItem(
                              value: 'accept', child: Text('Aceptar')),
                        PopupMenuItem(
                            value: 'remove',
                            child: Text(item['status'] == 'blocked'
                                ? 'Desbloquear'
                                : 'Rechazar o eliminar')),
                        if (item['status'] != 'blocked')
                          const PopupMenuItem(
                              value: 'block', child: Text('Bloquear')),
                      ])));
    }
    if (widget.kind == 'invitations') {
      return Card(
          child: ListTile(
        title: Text(item['sent'] == true
            ? 'Invitación enviada'
            : 'Invitación recibida'),
        subtitle: Text(
            '${item['role']} · ${item['revoked'] == true ? 'Revocada' : displayDate(item['expiresAt'])}'),
        trailing: PopupMenuButton<String>(
            onSelected: (action) => run(() async {
                  if (action == 'accept') {
                    await RemoteSync(widget.store).send(
                        '/v1/collaboration/invitations/${item['id']}/accept');
                  } else {
                    await RemoteSync(widget.store).request('DELETE',
                        '/v1/collaboration/invitations/${item['id']}');
                  }
                  await load();
                }),
            itemBuilder: (_) => [
                  if (item['sent'] != true && item['revoked'] != true)
                    const PopupMenuItem(
                        value: 'accept', child: Text('Aceptar')),
                  const PopupMenuItem(
                      value: 'reject', child: Text('Revocar o rechazar')),
                ]),
      ));
    }
    return Card(
        child: ListTile(
            title: Text(item['title'] ?? item['name'] ?? 'Material'),
            subtitle: Text(widget.kind == 'catalogue'
                ? '${item['cards']} tarjetas · ${item['author']?['displayName'] ?? 'Autor'} · ${displayDate(item['updatedAt'])}\nContenido de usuario sin revisión jurídica'
                : item['role'] ?? 'Privado'),
            onTap: () => push(
                context,
                widget.kind == 'groups'
                    ? StudyGroupPage(store: widget.store, id: item['id'])
                    : SharedDeckPage(store: widget.store, id: item['id'])),
            trailing: widget.kind == 'mine'
                ? IconButton(
                    tooltip: 'Crear invitación',
                    icon: const Icon(Icons.share_outlined),
                    onPressed: busy
                        ? null
                        : () => run(() => invite(item['id'], false)))
                : null));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SearchPageBody(
          header: [
            Padding(
                padding: const EdgeInsets.all(16),
                child: Column(children: [
                  if (['catalogue', 'mine'].contains(widget.kind))
                    TextField(
                        decoration:
                            const InputDecoration(labelText: 'Buscar título'),
                        onChanged: (v) => setState(() {
                              query = v;
                              cursor = '';
                              history.clear();
                              next = null;
                            })),
                  if (widget.kind == 'catalogue')
                    Details('Filtros', children: [
                      TextField(
                          decoration:
                              const InputDecoration(labelText: 'Materia'),
                          onChanged: (v) => setState(() {
                                subject = v;
                                cursor = '';
                                history.clear();
                                next = null;
                              })),
                      TextField(
                          decoration: const InputDecoration(
                              labelText:
                                  'Referencia de norma (por ejemplo BOE-A-1978-31229)'),
                          onChanged: (v) => setState(() {
                                norm = v;
                                cursor = '';
                                history.clear();
                                next = null;
                              })),
                    ]),
                  Wrap(spacing: 8, children: [
                    OutlinedButton(
                        onPressed: busy ? null : () => run(load),
                        child: Text(busy ? 'Cargando…' : 'Consultar')),
                    if (widget.kind == 'groups')
                      TextButton(
                          onPressed: busy
                              ? null
                              : () => run(() async {
                                    final values = await groupForm(context);
                                    if (values == null) return;
                                    await RemoteSync(widget.store).send(
                                        '/v1/collaboration/groups',
                                        body: values);
                                    await load();
                                  }),
                          child: const Text('Crear grupo')),
                    if (widget.kind == 'contacts')
                      TextButton(
                          onPressed: busy
                              ? null
                              : () => run(() async {
                                    final alias = await collaborationText(
                                        context, 'Alias exacto del compañero',
                                        maxLength: 30);
                                    if (alias == null || alias.isEmpty) return;
                                    await RemoteSync(widget.store).send(
                                        '/v1/collaboration/contacts/requests',
                                        body: {'alias': alias});
                                    await load();
                                  }),
                          child: const Text('Invitar por alias')),
                    if (widget.kind == 'contacts')
                      TextButton(
                          onPressed: busy
                              ? null
                              : () => run(() async {
                                    final result =
                                        await RemoteSync(widget.store).send(
                                            '/v1/collaboration/contacts/link');
                                    await SharePlus.instance.share(ShareParams(
                                        text:
                                            '${widget.store.apiBase}${result['path']}'));
                                  }),
                          child: const Text('Invitar por enlace')),
                    if (widget.kind == 'invitations')
                      TextButton(
                          onPressed: busy ? null : () => run(acceptLink),
                          child: const Text('Aceptar un enlace')),
                  ]),
                  if (widget.kind == 'mine')
                    const Text(
                        'Primero guarda tus tarjetas desde Cuenta y copias. Aquí solo se comparten los mazos de tu cuenta.'),
                ])),
          ],
          resultCount: items?.length ?? 0,
          resultBuilder: resultItem,
          footer: SafeArea(
              top: false,
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                TextButton(
                    onPressed: busy || history.isEmpty
                        ? null
                        : () => run(() async {
                              cursor = history.removeLast();
                              await load();
                            }),
                    child: const Text('Anterior')),
                TextButton(
                    onPressed: busy || next == null
                        ? null
                        : () => run(() async {
                              history.add(cursor);
                              cursor = next!;
                              await load();
                            }),
                    child: const Text('Siguiente')),
              ])),
          children: items == null
              ? [
                  const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Pulsa Consultar para cargar.'))
                ]
              : items!.isEmpty
                  ? [
                      const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('No hay resultados.'))
                    ]
                  : []));
}

class SharedDeckPage extends StatefulWidget {
  final AppStore store;
  final String id;
  final bool moderation;
  const SharedDeckPage(
      {super.key,
      required this.store,
      required this.id,
      this.moderation = false});
  @override
  State<SharedDeckPage> createState() => _SharedDeckPageState();
}

class _SharedDeckPageState extends State<SharedDeckPage> {
  String copyRequestId = const Uuid().v4();
  Json? data;
  bool busy = false;
  String cursor = '';
  final history = <String>[];
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    await perform(context, action);
    if (mounted) setState(() => busy = false);
  }

  Future<void> load() async {
    final route = widget.moderation
        ? '/v1/admin/collaboration/decks'
        : '/v1/collaboration/decks';
    final result = await RemoteSync(widget.store).request('GET',
        '$route/${widget.id}?cursor=${Uri.encodeQueryComponent(cursor)}&limit=20');
    if (mounted) setState(() => data = result);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(data?['title'] ?? 'Mazo compartido')),
      body: Column(children: [
        Padding(
            padding: const EdgeInsets.all(16),
            child: Wrap(spacing: 8, children: [
              if (data?['canCheckUpdates'] == true)
                TextButton(
                    onPressed: () => push(context,
                        CopyUpdatesPage(store: widget.store, id: widget.id)),
                    child: const Text('Cambios del mazo de origen')),
              if (data?['role'] == 'owner')
                TextButton(
                    onPressed: () => push(context,
                        DeckAccessPage(store: widget.store, id: widget.id)),
                    child: const Text('Permisos y publicación')),
              OutlinedButton(
                  onPressed: busy ? null : () => run(load),
                  child: const Text('Consultar tarjetas')),
              OutlinedButton(
                  onPressed: busy || widget.moderation || data == null
                      ? null
                      : () => run(() async {
                            if (!await confirm(context, 'Crear copia personal',
                                'Se crea una copia independiente en tu cuenta. Después podrás descargarla desde Cuenta y copias. Tu progreso no se comparte con el autor.')) {
                              return;
                            }
                            final result = await RemoteSync(widget.store)
                                .request('POST',
                                    '/v1/collaboration/decks/${widget.id}/copy',
                                    extraHeaders: {
                                  'Idempotency-Key': copyRequestId
                                });
                            copyRequestId = const Uuid().v4();
                            if (context.mounted) {
                              toast(context,
                                  '${result['cards']} tarjetas copiadas. Descarga tu progreso para estudiarlas.');
                            }
                          }),
                  child: const Text('Añadir copia personal')),
              TextButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                            final reason = await collaborationText(context,
                                'Motivo del reporte (mínimo 10 caracteres)',
                                maxLength: 2000);
                            if (reason == null) return;
                            await RemoteSync(widget.store)
                                .send('/v1/collaboration/reports', body: {
                              'targetId': widget.id,
                              'reason': reason
                            });
                            if (context.mounted) {
                              toast(context, 'Reporte registrado');
                            }
                          }),
                  child: const Text('Reportar')),
            ])),
        Expanded(
            child: data == null
                ? const Center(
                    child: Text(
                        'El contenido no incluye el progreso de otros usuarios.'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
                    itemCount: (data!['items'] as List).length,
                    itemBuilder: (context, index) {
                      final card = Json.from(data!['items'][index]);
                      return Card(
                          child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(card['front']),
                                    const SizedBox(height: 12),
                                    Text(card['back']),
                                    const SizedBox(height: 8),
                                    Text(
                                        'Contenido: ${card['editorialState'] ?? 'usuario'} · revisión ${card['revision']}'),
                                    if (data!['role'] == 'owner' ||
                                        data!['role'] == 'editor')
                                      TextButton(
                                          onPressed: busy
                                              ? null
                                              : () => run(() async {
                                                    final citation = (card[
                                                                    'citations']
                                                                as List? ??
                                                            [])
                                                        .firstOrNull as Map?;
                                                    final existing = StudyCard(
                                                        id: card['id'],
                                                        deck: data!['title'],
                                                        front: card['front'],
                                                        back: card['back'],
                                                        explanation:
                                                            card['explanation'] ??
                                                                '',
                                                        type: card['type'] ??
                                                            'qa',
                                                        options:
                                                            List<String>.from(
                                                                card['options'] ??
                                                                    []),
                                                        correct:
                                                            card['correct'],
                                                        normId:
                                                            citation?['normId'] ??
                                                                '',
                                                        unitId:
                                                            citation?['unitId'] ??
                                                                '',
                                                        versionId: citation?[
                                                                'versionId'] ??
                                                            '',
                                                        unitVersionHash: citation?[
                                                                'unitVersionHash'] ??
                                                            '',
                                                        revision:
                                                            card['revision']);
                                                    await Navigator.of(context)
                                                        .push(MaterialPageRoute<
                                                                void>(
                                                            builder: (_) =>
                                                                CardEditor(
                                                                    store: widget
                                                                        .store,
                                                                    existing:
                                                                        existing,
                                                                    onSaveShared:
                                                                        (edited) async {
                                                                      final remote =
                                                                          RemoteSync(
                                                                              widget.store);
                                                                      final body =
                                                                          {
                                                                        ...remote.cardPayload(
                                                                            edited,
                                                                            widget.id),
                                                                        'clientId':
                                                                            card['clientId'],
                                                                        'citations':
                                                                            card['citations'] ??
                                                                                []
                                                                      };
                                                                      await remote.request(
                                                                          'PUT',
                                                                          '/v1/collaboration/cards/${Uri.encodeComponent(card['id'])}',
                                                                          body: body,
                                                                          extraHeaders: {
                                                                            'If-Match':
                                                                                '${card['revision']}'
                                                                          });
                                                                    })));
                                                    await load();
                                                  }),
                                          child: const Text(
                                              'Editar tarjeta compartida')),
                                  ])));
                    })),
        if (data != null)
          SafeArea(
              top: false,
              child:
                  Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                TextButton(
                    onPressed: busy || history.isEmpty
                        ? null
                        : () => run(() async {
                              cursor = history.removeLast();
                              await load();
                            }),
                    child: const Text('Anterior')),
                TextButton(
                    onPressed: busy || data!['nextCursor'] == null
                        ? null
                        : () => run(() async {
                              history.add(cursor);
                              cursor = data!['nextCursor'];
                              await load();
                            }),
                    child: const Text('Siguiente')),
              ])),
      ]));
}

class StudyGroupPage extends StatefulWidget {
  final AppStore store;
  final String id;
  const StudyGroupPage({super.key, required this.store, required this.id});
  @override
  State<StudyGroupPage> createState() => _StudyGroupPageState();
}

class _StudyGroupPageState extends State<StudyGroupPage> {
  Json? data;
  bool busy = false;
  String membersCursor = '', resourcesCursor = '';
  final membersHistory = <String>[], resourcesHistory = <String>[];
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    await perform(context, action);
    if (mounted) setState(() => busy = false);
  }

  Future<void> load() async {
    final result = await RemoteSync(widget.store).request(
        'GET',
        '/v1/collaboration/groups/${widget.id}?${Uri(queryParameters: {
              'membersCursor': membersCursor,
              'resourcesCursor': resourcesCursor
            }).query}');
    if (mounted) setState(() => data = result);
  }

  Widget pages({required bool members}) {
    final history = members ? membersHistory : resourcesHistory;
    final next = data?[members ? 'membersNextCursor' : 'resourcesNextCursor'];
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      TextButton(
          onPressed: busy || history.isEmpty
              ? null
              : () => run(() async {
                    final previous = history.removeLast();
                    if (members) {
                      membersCursor = previous;
                    } else {
                      resourcesCursor = previous;
                    }
                    await load();
                  }),
          child: const Text('Anterior')),
      TextButton(
          onPressed: busy || next == null
              ? null
              : () => run(() async {
                    history.add(members ? membersCursor : resourcesCursor);
                    if (members) {
                      membersCursor = next;
                    } else {
                      resourcesCursor = next;
                    }
                    await load();
                  }),
          child: const Text('Siguiente')),
    ]);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(data?['name'] ?? 'Grupo privado')),
      body: PageBody(children: [
        const Text(
            'Se comparten materiales, sin notas ni estadísticas personales.'),
        OutlinedButton(
            onPressed: busy ? null : () => run(load),
            child: const Text('Consultar grupo')),
        if (data != null) ...[
          if (['owner', 'admin'].contains(data!['role']))
            TextButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                          final values =
                              await groupForm(context, initial: data);
                          if (values == null) return;
                          await RemoteSync(widget.store).request(
                              'PUT', '/v1/collaboration/groups/${widget.id}',
                              body: values,
                              extraHeaders: {
                                'If-Match': '${data!['revision']}'
                              });
                          await load();
                        }),
                child: const Text('Editar datos del grupo')),
          if (['owner', 'admin'].contains(data!['role']))
            OutlinedButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                          final settings = await invitationSettings(context,
                              group: true,
                              allowAdmin: data!['role'] == 'owner');
                          if (settings == null) return;
                          final result = await RemoteSync(widget.store).send(
                              '/v1/collaboration/${widget.id}/invitations',
                              body: settings);
                          await SharePlus.instance.share(ShareParams(
                              text:
                                  '${widget.store.apiBase}${result['path']}'));
                        }),
                child: const Text('Invitar participantes')),
          if (['owner', 'admin', 'collaborator'].contains(data!['role']))
            OutlinedButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                          final deckId =
                              await pickOwnDeck(context, widget.store);
                          if (deckId == null) return;
                          if (!context.mounted) return;
                          final topic = await collaborationText(
                              context, 'Tema del recurso (opcional)');
                          if (topic == null) return;
                          await RemoteSync(widget.store).send(
                              '/v1/collaboration/groups/${widget.id}/resources',
                              body: {'deckId': deckId, 'topic': topic.trim()});
                          await load();
                        }),
                child: const Text('Compartir un mazo en el grupo')),
          Details('Miembros', children: [
            for (final member in data!['members'] as List)
              ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(member['displayName']),
                  subtitle: Text(member['role']),
                  trailing: data!['role'] == 'owner' &&
                          member['role'] != 'owner'
                      ? PopupMenuButton<String>(
                          onSelected: (action) => run(() async {
                                final path =
                                    '/v1/collaboration/${widget.id}/members/${member['id']}';
                                if (action == 'remove') {
                                  await RemoteSync(widget.store)
                                      .request('DELETE', path);
                                } else {
                                  await RemoteSync(widget.store).request(
                                      'PUT', path,
                                      body: {'role': action});
                                }
                                await load();
                              }),
                          itemBuilder: (_) => const [
                                PopupMenuItem(
                                    value: 'member', child: Text('Miembro')),
                                PopupMenuItem(
                                    value: 'collaborator',
                                    child: Text('Colaborador')),
                                PopupMenuItem(
                                    value: 'admin',
                                    child: Text('Administrador')),
                                PopupMenuItem(
                                    value: 'remove',
                                    child: Text('Retirar acceso'))
                              ])
                      : data!['role'] == 'admin' &&
                              !['owner', 'admin'].contains(member['role'])
                          ? IconButton(
                              tooltip: 'Retirar acceso',
                              icon: const Icon(Icons.person_remove_outlined),
                              onPressed: busy
                                  ? null
                                  : () => run(() async {
                                        if (!await confirm(
                                            context,
                                            'Retirar acceso',
                                            'Se retirará el acceso al grupo y al material compartido. Las copias personales se conservan.')) {
                                          return;
                                        }
                                        await RemoteSync(widget.store).request(
                                            'DELETE',
                                            '/v1/collaboration/${widget.id}/members/${member['id']}');
                                        await load();
                                      }))
                          : null),
            pages(members: true),
          ]),
          const Section('Materiales'),
          for (final resource in data!['resources'] as List)
            ListTile(
                title: Text(resource['title']),
                subtitle: Text(resource['topic'] ?? ''),
                onTap: () => push(
                    context,
                    SharedDeckPage(
                        store: widget.store, id: resource['deckId'])),
                trailing:
                    ['owner', 'admin', 'collaborator'].contains(data!['role'])
                        ? IconButton(
                            tooltip: 'Retirar material',
                            icon: const Icon(Icons.remove_circle_outline),
                            onPressed: busy
                                ? null
                                : () => run(() async {
                                      await RemoteSync(widget.store).request(
                                          'DELETE',
                                          '/v1/collaboration/groups/${widget.id}/resources/${resource['id']}');
                                      await load();
                                    }))
                        : null),
          pages(members: false),
          TextButton(
              onPressed: busy
                  ? null
                  : () => run(() async {
                        final owner = data!['role'] == 'owner';
                        if (!await confirm(
                            context,
                            owner ? 'Eliminar grupo' : 'Salir del grupo',
                            'Se retira el acceso compartido. Las copias personales y su progreso se conservan.')) {
                          return;
                        }
                        await RemoteSync(widget.store).request(
                            'DELETE',
                            owner
                                ? '/v1/collaboration/groups/${widget.id}'
                                : '/v1/collaboration/${widget.id}/members/${widget.store.data['remoteUserId']}');
                        if (context.mounted) Navigator.pop(context);
                      }),
              child: Text(data!['role'] == 'owner'
                  ? 'Eliminar grupo'
                  : 'Salir del grupo')),
        ],
      ]));
}

class DeckAccessPage extends StatefulWidget {
  final AppStore store;
  final String id;
  const DeckAccessPage({super.key, required this.store, required this.id});
  @override
  State<DeckAccessPage> createState() => _DeckAccessPageState();
}

class _DeckAccessPageState extends State<DeckAccessPage> {
  List<Json>? members;
  bool busy = false;
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    await perform(context, action);
    if (mounted) setState(() => busy = false);
  }

  Future<void> load() async {
    final result = await RemoteSync(widget.store)
        .request('GET', '/v1/collaboration/decks/${widget.id}/members');
    if (mounted) {
      setState(() => members =
          (result['items'] as List).map((r) => Json.from(r)).toList());
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Permisos del mazo')),
      body: PageBody(children: [
        const Text(
            'Se comparte solo el contenido. Los repasos, favoritos y notas permanecen privados.'),
        OutlinedButton(
            onPressed: busy ? null : () => run(load),
            child: const Text('Consultar accesos')),
        for (final member in members ?? <Json>[])
          ListTile(
              title: Text(member['displayName']),
              subtitle: Text(member['role']),
              trailing: PopupMenuButton<String>(
                  onSelected: (action) => run(() async {
                        final path =
                            '/v1/collaboration/${widget.id}/members/${member['id']}';
                        if (action == 'remove') {
                          if (!await confirm(context, 'Retirar acceso',
                              'Este usuario dejará de acceder y se revocarán los enlaces anteriores de este mazo. Sus copias personales se conservan.')) {
                            return;
                          }
                          await RemoteSync(widget.store)
                              .request('DELETE', path);
                        } else {
                          await RemoteSync(widget.store)
                              .request('PUT', path, body: {'role': action});
                        }
                        await load();
                      }),
                  itemBuilder: (_) => const [
                        PopupMenuItem(value: 'reader', child: Text('Lector')),
                        PopupMenuItem(value: 'editor', child: Text('Editor')),
                        PopupMenuItem(
                            value: 'remove', child: Text('Retirar acceso'))
                      ])),
        if (publicDeckPublicationEnabled)
          Details('Catálogo público', children: [
            const Text(
                'La publicación es opcional, requiere moderación y no implica revisión jurídica. No incluye datos de estudio ni notas privadas.'),
            OutlinedButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                          if (!await confirm(
                              context,
                              'Solicitar publicación pública',
                              'Confirma que puedes compartir este material y sus fuentes. Se enviará a moderación antes de aparecer en el catálogo.')) {
                            return;
                          }
                          if (!context.mounted) return;
                          final subject = await collaborationText(
                              context, 'Materia (opcional)',
                              maxLength: 80);
                          if (subject == null) return;
                          await RemoteSync(widget.store).send(
                              '/v1/collaboration/decks/${widget.id}/publication',
                              body: {
                                'confirmation': 'PUBLICAR',
                                'subject': subject
                              });
                          if (context.mounted) {
                            toast(context, 'Solicitud enviada a moderación');
                          }
                        }),
                child: const Text('Solicitar publicación')),
            TextButton(
                onPressed: busy
                    ? null
                    : () => run(() async {
                          await RemoteSync(widget.store).request('DELETE',
                              '/v1/collaboration/decks/${widget.id}/publication');
                          if (context.mounted) {
                            toast(context, 'Publicación retirada');
                          }
                        }),
                child: const Text('Retirar del catálogo público')),
          ]),
      ]));
}

class CopyUpdatesPage extends StatefulWidget {
  final AppStore store;
  final String id;
  const CopyUpdatesPage({super.key, required this.store, required this.id});
  @override
  State<CopyUpdatesPage> createState() => _CopyUpdatesPageState();
}

class _CopyUpdatesPageState extends State<CopyUpdatesPage> {
  Json? changes;
  bool busy = false;
  Future<void> run(Future<void> Function() action) async {
    if (busy) return;
    setState(() => busy = true);
    await perform(context, action);
    if (mounted) setState(() => busy = false);
  }

  Future<void> load() async {
    final result = await RemoteSync(widget.store)
        .request('GET', '/v1/collaboration/copies/${widget.id}/updates');
    if (mounted) setState(() => changes = result);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Cambios del origen')),
      body: PageBody(children: [
        const Text(
            'Tu copia es independiente. Solo se aplican cambios cuando lo confirmas. Las tarjetas editadas personalmente se conservan; las demás mantienen versiones e historial de repasos.'),
        OutlinedButton(
            onPressed: busy ? null : () => run(load),
            child: const Text('Comprobar cambios')),
        if (changes != null) ...[
          Text(
              '${changes!['new']} tarjetas nuevas y ${changes!['changed']} actualizadas.'),
          FilledButton(
              onPressed: busy
                  ? null
                  : () => run(() async {
                        if (!await confirm(
                            context,
                            'Aplicar cambios a mi copia',
                            'Se conservarán las revisiones anteriores y el progreso. Después descarga tus tarjetas para usar la versión actualizada en este dispositivo.')) {
                          return;
                        }
                        await RemoteSync(widget.store).request('POST',
                            '/v1/collaboration/copies/${widget.id}/updates',
                            body: {
                              'confirmation': 'ACTUALIZAR'
                            },
                            extraHeaders: {
                              'If-Match': '${changes!['revision']}'
                            });
                        await load();
                      }),
              child: const Text('Aplicar a mi copia')),
          OutlinedButton(
              onPressed: busy
                  ? null
                  : () => run(() async {
                        await RemoteSync(widget.store).pull();
                        if (context.mounted) {
                          toast(context,
                              'Descarga confirmada; los conflictos se conservan para revisar.');
                        }
                      }),
              child: const Text('Descargar mis tarjetas y progreso')),
        ],
      ]));
}
