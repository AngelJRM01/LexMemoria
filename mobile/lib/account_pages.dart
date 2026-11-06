import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'models.dart';
import 'store.dart';
import 'remote.dart';
import 'widgets.dart';
import 'moderation.dart';
import 'google_identity.dart';

class PersonalProfilePage extends StatefulWidget {
  final AppStore store;
  const PersonalProfilePage({super.key, required this.store});
  @override
  State<PersonalProfilePage> createState() => _PersonalProfilePageState();
}

class _PersonalProfilePageState extends State<PersonalProfilePage> {
  late Json draft;
  late TextEditingController name, alias;
  final form = GlobalKey<FormState>();
  int? revision;
  String? avatarImage;
  String? accountCreatedAt;
  String? ownerScope;
  late String serverScope;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    ownerScope = widget.store.data['remoteUserId'];
    serverScope = widget.store.apiBase;
    draft = {
      ...accountProfileDefaults,
      ...Json.from(widget.store.profile['account'] ?? {}),
      'theme': widget.store.profile['theme'] ??
          (widget.store.data['dark'] == null
              ? 'system'
              : widget.store.dark
                  ? 'dark'
                  : 'light')
    };
    name = TextEditingController(text: draft['displayName']);
    alias = TextEditingController(text: draft['alias']);
  }

  @override
  void dispose() {
    name.dispose();
    alias.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() => busy = true);
    await perform(context, () async {
      final result =
          await RemoteSync(widget.store).request('GET', '/v1/account/profile');
      if (!mounted) return;
      setState(() {
        draft = {...accountProfileDefaults, ...Json.from(result['data'])};
        revision = result['revision'];
        accountCreatedAt = result['createdAt'];
        name.text = draft['displayName'];
        alias.text = draft['alias'];
        ownerScope = widget.store.data['remoteUserId'];
        serverScope = widget.store.apiBase;
      });
      final avatar =
          await RemoteSync(widget.store).request('GET', '/v1/account/avatar');
      if (mounted &&
          ownerScope == widget.store.data['remoteUserId'] &&
          serverScope == widget.store.apiBase) {
        setState(() => avatarImage = avatar['image']);
      }
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    await perform(context, () async {
      for (final key in ['quietStart', 'quietEnd']) {
        if (!RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$').hasMatch(draft[key])) {
          throw StateError('Los horarios de silencio deben usar HH:MM.');
        }
      }
      final owner = widget.store.data['remoteUserId'];
      final server = widget.store.apiBase;
      final expectedAccount = Json.from(widget.store.profile['account'] ?? {});
      if (owner != ownerScope || server != serverScope) {
        throw StateError(
            'La cuenta cambió. Consulta el perfil antes de guardar.');
      }
      final value = {
        ...draft,
        'displayName': name.text.trim(),
        'alias': alias.text.trim().toLowerCase()
      };
      if (owner != null) {
        if (revision == null) {
          throw StateError(
              'Consulta primero tu perfil de cuenta para comparar su versión.');
        }
        final result = await RemoteSync(widget.store).request(
            'PUT', '/v1/account/profile',
            body: value, extraHeaders: {'If-Match': '$revision'});
        revision = result['revision'];
      } else if (alias.text.trim().isNotEmpty) {
        throw StateError(
            'El alias para compartir se reserva desde una cuenta conectada. Puedes guardar tu nombre sin alias.');
      }
      if (widget.store.data['remoteUserId'] != owner ||
          widget.store.apiBase != server) {
        throw StateError(
            'La cuenta ha cambiado. Consulta el perfil antes de continuar.');
      }
      if (owner == null) {
        await widget.store
            .setProfile({'account': value, 'theme': value['theme']});
      } else {
        await widget.store.commitAccountProfile(
            expectedAccount, value, revision!, owner, server);
      }
      if (mounted) toast(context, 'Perfil guardado');
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> uploadAvatar() async {
    setState(() => busy = true);
    await perform(context, () async {
      final picked = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['jpg', 'jpeg', 'png', 'webp'],
          withData: true);
      if (picked == null) return;
      final bytes = picked.files.single.bytes;
      if (bytes == null || bytes.length > 1000000) {
        throw StateError('Elige una imagen de hasta 1 MB.');
      }
      await RemoteSync(widget.store).request('PUT', '/v1/account/avatar',
          body: {'image': base64Encode(bytes)});
      final result =
          await RemoteSync(widget.store).request('GET', '/v1/account/avatar');
      if (mounted) {
        setState(() {
          avatarImage = result['image'];
          draft['avatar'] = 'photo';
        });
      }
    });
    if (mounted) setState(() => busy = false);
  }

  Future<void> importGoogleAvatar() async {
    setState(() => busy = true);
    await perform(context, () async {
      final token = await NativeGoogleIdentity().authenticate();
      if (token == null) return;
      if (ownerScope != widget.store.data['remoteUserId'] ||
          serverScope != widget.store.apiBase) {
        throw StateError('La cuenta cambió. Consulta el perfil de nuevo.');
      }
      await RemoteSync(widget.store)
          .send('/v1/account/avatar/google', body: {'idToken': token});
      final result =
          await RemoteSync(widget.store).request('GET', '/v1/account/avatar');
      if (mounted) {
        setState(() {
          avatarImage = result['image'];
          draft['avatar'] = 'photo';
        });
      }
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final connected = widget.store.data['remoteUserId'] != null;
    return Scaffold(
        appBar: AppBar(title: const Text('Mi perfil')),
        body: Form(
            key: form,
            child: PageBody(children: [
              if (connected)
                Details('Identidad de mi cuenta', children: [
                  SelectableText(
                      'Identificador: ${widget.store.data['remoteUserId']}'),
                  Text(
                      'Creada: ${displayDate(accountCreatedAt, empty: 'Consulta tu perfil para ver la fecha')}'),
                  const Text(
                      'Idioma disponible: español. El alias no cambia este identificador.'),
                ]),
              CircleAvatar(
                  radius: 28,
                  backgroundImage: avatarImage == null
                      ? null
                      : MemoryImage(base64Decode(avatarImage!)),
                  child: avatarImage != null
                      ? null
                      : draft['avatar'] == 'initials' &&
                              name.text.trim().isNotEmpty
                          ? Text(name.text
                              .trim()
                              .split(RegExp(r'\s+'))
                              .take(2)
                              .map((p) => String.fromCharCode(p.runes.first))
                              .join()
                              .toUpperCase())
                          : Icon(draft['avatar'] == 'book'
                              ? Icons.menu_book
                              : draft['avatar'] == 'balance'
                                  ? Icons.balance
                                  : Icons.person_outline)),
              if (connected)
                Wrap(spacing: 8, children: [
                  TextButton(
                      onPressed: busy ? null : uploadAvatar,
                      child: const Text('Foto opcional')),
                  if (NativeGoogleIdentity().available)
                    TextButton(
                        onPressed: busy ? null : importGoogleAvatar,
                        child: const Text('Foto de Google')),
                  TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              await perform(context, () async {
                                await RemoteSync(widget.store)
                                    .request('DELETE', '/v1/account/avatar');
                                if (mounted) {
                                  setState(() {
                                    avatarImage = null;
                                    draft['avatar'] = 'initials';
                                  });
                                }
                              });
                            },
                      child: const Text('Quitar foto')),
                ]),
              const Text(
                  'Tu información académica y tus preferencias son privadas. No hay perfil público obligatorio.'),
              const SizedBox(height: 16),
              if (connected)
                OutlinedButton(
                    onPressed: busy ? null : load,
                    child: const Text('Consultar perfil de mi cuenta')),
              Column(children: [
                TextFormField(
                    controller: name,
                    maxLength: 80,
                    decoration: const InputDecoration(
                        labelText: 'Nombre para mostrar (opcional)')),
                TextFormField(
                    controller: alias,
                    maxLength: 30,
                    enabled: connected,
                    decoration: const InputDecoration(
                        labelText: 'Alias opcional',
                        helperText:
                            '3–30 caracteres: a–z, números y _. Empieza por letra.'),
                    validator: (v) => v == null ||
                            v.trim().isEmpty ||
                            RegExp(r'^[a-z][a-z0-9_]{2,29}$')
                                .hasMatch(v.trim().toLowerCase())
                        ? null
                        : 'Revisa el formato del alias'),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                    initialValue: draft['avatar'],
                    decoration: const InputDecoration(labelText: 'Avatar'),
                    items: const [
                      DropdownMenuItem(
                          value: 'photo',
                          child: Text('Foto privada de mi cuenta')),
                      DropdownMenuItem(
                          value: 'initials', child: Text('Mis iniciales')),
                      DropdownMenuItem(value: 'book', child: Text('Libro')),
                      DropdownMenuItem(value: 'balance', child: Text('Balanza'))
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() => draft['avatar'] = v)),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                    initialValue: draft['theme'],
                    decoration: const InputDecoration(labelText: 'Apariencia'),
                    items: const [
                      DropdownMenuItem(
                          value: 'system', child: Text('Como el dispositivo')),
                      DropdownMenuItem(value: 'light', child: Text('Claro')),
                      DropdownMenuItem(value: 'dark', child: Text('Oscuro'))
                    ],
                    onChanged: busy
                        ? null
                        : (v) => setState(() => draft['theme'] = v)),
              ]),
              Details('Privacidad e invitaciones', children: [
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Permitir invitaciones por alias'),
                    value: draft['allowAliasInvitations'],
                    onChanged: busy
                        ? null
                        : (v) =>
                            setState(() => draft['allowAliasInvitations'] = v)),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Permitir invitaciones por enlace'),
                    value: draft['allowLinkInvitations'],
                    onChanged: busy
                        ? null
                        : (v) =>
                            setState(() => draft['allowLinkInvitations'] = v)),
                const Text(
                    'Desactivadas por defecto. No se comparten notas, calificaciones ni repasos.'),
              ]),
              Details('Preferencias de avisos', children: [
                for (final item in {
                  'studyNotifications': 'Estudio',
                  'legalNotifications': 'Novedades jurídicas',
                  'collaborationNotifications': 'Colaboración'
                }.entries)
                  SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.value),
                      value: draft[item.key],
                      onChanged: busy
                          ? null
                          : (v) => setState(() => draft[item.key] = v)),
                const Text(
                    'Estas preferencias no activan notificaciones push. El envío en dispositivo sigue pendiente de configuración y prueba.'),
                Text(
                    'Hasta ${draft['noticeDailyLimit']} avisos opcionales al día'),
                Slider(
                    value: (draft['noticeDailyLimit'] as num).toDouble(),
                    min: 1,
                    max: 20,
                    divisions: 19,
                    onChanged: busy
                        ? null
                        : (v) => setState(
                            () => draft['noticeDailyLimit'] = v.round())),
                const Text(
                    'El horario de silencio usa la hora peninsular española.'),
                for (final item in {
                  'quietStart': 'Silencio desde',
                  'quietEnd': 'Silencio hasta'
                }.entries)
                  TextFormField(
                      initialValue: draft[item.key],
                      decoration:
                          InputDecoration(labelText: '${item.value} (HH:MM)'),
                      onChanged: (v) => draft[item.key] = v,
                      validator: (v) => RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d$')
                              .hasMatch(v ?? '')
                          ? null
                          : 'Hora no válida'),
              ]),
              const SizedBox(height: 20),
              FilledButton(
                  onPressed: busy ? null : save,
                  child: Text(busy ? 'Guardando…' : 'Guardar perfil')),
              const Text(
                  'El plan, las asignaturas y el objetivo de estudio se gestionan en sus pantallas habituales.'),
            ])));
  }
}

class AccountSecurityPage extends StatefulWidget {
  final AppStore store;
  const AccountSecurityPage({super.key, required this.store});
  @override
  State<AccountSecurityPage> createState() => _AccountSecurityPageState();
}

class _AccountSecurityPageState extends State<AccountSecurityPage> {
  Json? info;
  bool busy = false;
  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    await perform(context, action);
    if (mounted) setState(() => busy = false);
  }

  Future<void> load() async {
    final result =
        await RemoteSync(widget.store).request('GET', '/v1/account/security');
    if (mounted) setState(() => info = result);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Cuenta y seguridad')),
      body: PageBody(children: [
        const Text(
            'Las sesiones son accesos de LexMemoria. No permiten identificar el modelo exacto del dispositivo. La actividad corresponde al inicio o renovación del acceso.'),
        OutlinedButton(
            onPressed: busy ? null : () => run(load),
            child: const Text('Consultar sesiones')),
        if (info != null) ...[
          if (['reviewer', 'publisher', 'admin'].contains(info!['role']))
            TextButton(
                onPressed: () =>
                    push(context, ModerationPage(store: widget.store)),
                child: const Text('Revisión y soporte')),
          SelectableText('Identificador: ${info!['userId']}'),
          Text('Cuenta creada: ${displayDate(info!['createdAt'])}'),
          if ((info!['linkedIdentities'] as List).isNotEmpty)
            const Text('Identidad Firebase vinculada (Google/Apple).'),
          if (NativeGoogleIdentity().available)
            for (final linked in info!['linkedIdentities'] as List)
              TextButton(
                  onPressed: busy
                      ? null
                      : () => run(() async {
                            if (!await confirm(context, 'Desvincular acceso',
                                'Guarda antes un código de recuperación desde Cuenta y copias. Los datos y esta sesión se conservan; Google dejará de dar acceso a esta cuenta.')) {
                              return;
                            }
                            final token =
                                await NativeGoogleIdentity().authenticate();
                            if (token == null) return;
                            await RemoteSync(widget.store).send(
                                '/v1/account/identities/${linked['id']}/unlink',
                                body: {'idToken': token});
                            widget.store.data.remove('remoteGoogleLinked');
                            await widget.store.save();
                            await load();
                          }),
                  child: const Text('Desvincular con identificación reciente')),
          if (info!['legacySessionsPresent'] == true)
            const Text(
                'Hay accesos antiguos sin identificación de dispositivo. Cerrar una sesión antigua revoca esos accesos antiguos.'),
          for (final raw in info!['sessions'] as List) ...[
            ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(raw['current'] == true
                    ? 'Este acceso'
                    : 'Otro acceso de LexMemoria'),
                subtitle: Text(
                    'Actividad aproximada: ${displayDate(raw['lastActiveAt'], time: true)}'),
                trailing: raw['current'] == true
                    ? null
                    : IconButton(
                        tooltip: 'Revocar acceso',
                        icon: const Icon(Icons.logout),
                        onPressed: busy
                            ? null
                            : () => run(() async {
                                  if (!await confirm(context, 'Revocar acceso',
                                      'Este acceso dejará de sincronizar. Los datos educativos del dispositivo no se borran.')) {
                                    return;
                                  }
                                  await RemoteSync(widget.store).request(
                                      'DELETE',
                                      '/v1/account/sessions/${raw['id']}');
                                  await load();
                                }))),
          ],
          OutlinedButton(
              onPressed: busy
                  ? null
                  : () => run(() async {
                        if (!await confirm(context, 'Cerrar otros accesos',
                            'Se revocan los otros accesos del servidor. Conservas este y los datos locales de cada dispositivo.')) {
                          return;
                        }
                        await RemoteSync(widget.store)
                            .send('/v1/account/sessions/revoke-others');
                        await load();
                      }),
              child: const Text('Cerrar las otras sesiones')),
        ],
      ]));
}

class SyncConflictsPage extends StatefulWidget {
  final AppStore store;
  const SyncConflictsPage({super.key, required this.store});
  @override
  State<SyncConflictsPage> createState() => _SyncConflictsPageState();
}

class _SyncConflictsPageState extends State<SyncConflictsPage> {
  bool busy = false;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Resolver cambios')),
      body: PageBody(children: [
        const Text(
            'Puedes conservar el servidor y guardar tus cambios locales en una copia independiente. Los repasos pendientes pasan a la copia con un estado recalculado; se archiva el estado local anterior.'),
        for (final id in widget.store
            .list('syncConflicts')
            .map((c) => c['cardId'] as String)
            .toSet())
          Details('Tarjeta con cambios', children: [
            for (final conflict in widget.store
                .list('syncConflicts')
                .where((c) => c['cardId'] == id))
              SelectableText(const JsonEncoder.withIndent('  ').convert({
                'tipo': conflict['kind'],
                'local': conflict['local'],
                'servidor': conflict['remote'] ?? conflict['remoteState']
              })),
            FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        if (!await confirm(context, 'Conservar ambas versiones',
                            'La original seguirá el estado confirmado del servidor. Se crea una copia de tu contenido local y de sus repasos pendientes, sin sobrescribir la otra versión.')) {
                          return;
                        }
                        if (!context.mounted) return;
                        setState(() => busy = true);
                        await perform(context,
                            () => RemoteSync(widget.store).forkConflict(id));
                        if (mounted) setState(() => busy = false);
                      },
                child: const Text('Conservar ambas versiones')),
          ]),
        if (widget.store.list('syncConflicts').isEmpty)
          const Text('No quedan conflictos pendientes.'),
      ]));
}
