import 'dart:convert';
import 'package:flutter/material.dart' hide Badge;
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'store.dart';
import 'models.dart';
import 'widgets.dart';
import 'planning.dart';
import 'remote.dart';
import 'workspace.dart';

ShareParams backupParameters(String json) => ShareParams(
      files: [XFile.fromData(utf8.encode(json), mimeType: 'application/json')],
      fileNameOverrides: ['LexMemoria-copia-${civilDate(DateTime.now())}.json'],
      subject: 'LexMemoria · copia de mis datos',
    );

class ProfilePage extends StatelessWidget {
  final AppStore store;
  const ProfilePage({super.key, required this.store});
  @override
  Widget build(BuildContext context) => PageBody(children: [
        Text('Tu espacio', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 24),
        Paper(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(
              store.data['remoteUserId'] == null
                  ? 'Tu progreso, contigo'
                  : 'Cuenta de estudio',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          Text(store.data['remoteUserId'] == null
              ? 'Guarda una copia o conecta tu cuenta para continuar en otro dispositivo.'
              : 'Consulta tu copia y las opciones para cambiar de dispositivo.'),
          const SizedBox(height: 20),
          FilledButton.icon(
              onPressed: () => push(context, AccountPage(store: store)),
              icon: const Icon(Icons.cloud_outlined),
              label: const Text('Cuenta y copias')),
        ])),
        const SizedBox(height: 24),
        ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.calendar_month_outlined),
            title: const Text('Mi plan de estudio'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(context, PlannerPage(store: store))),
        ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.bar_chart),
            title: const Text('Mi progreso'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(context, ProgressPage(store: store))),
        ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.settings_outlined),
            title: const Text('Ajustes y datos'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(context, SettingsPage(store: store))),
        ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacidad y fuentes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(context, const PrivacyPage())),
      ]);
}

class AccountPage extends StatefulWidget {
  final AppStore store;
  const AccountPage({super.key, required this.store});
  @override
  State<AccountPage> createState() => _AccountPageState();
}

class _AccountPageState extends State<AccountPage> {
  bool busy = false;
  String? code;
  Future<void> protect() async {
    setState(() => busy = true);
    await perform(context, () async {
      final remote = RemoteSync(widget.store);
      if (widget.store.data['remoteUserId'] == null) await remote.activate();
      await remote.upload();
      if (code == null) {
        final value = await remote.recoveryCode();
        if (mounted) setState(() => code = value);
      }
      if (mounted) {
        toast(context, 'Tarjetas y progreso guardados en tu cuenta.');
      }
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final configured = s.hasRemoteServer;
    return Scaffold(
        appBar: AppBar(title: const Text('Cuenta y copias')),
        body: PageBody(children: [
          Text('Continúa en otro dispositivo',
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          Text(configured
              ? 'Guarda tus tarjetas y repasos. En tu otro móvil podrás recuperarlos con un código privado.'
              : 'Las cuentas en la nube todavía no están disponibles en esta instalación. Puedes conservar todo tu progreso con una copia de tus datos.'),
          const SizedBox(height: 24),
          if (configured) ...[
            FilledButton.icon(
                onPressed: busy ? null : protect,
                icon: const Icon(Icons.cloud_upload_outlined),
                label: Text(
                    busy ? 'Guardando…' : 'Guardar mis tarjetas y progreso')),
            if (s.data['lastProgressSync'] != null)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                      'Última copia: ${displayDate(s.data['lastProgressSync'], time: true)}')),
            if (code != null) ...[
              const SizedBox(height: 20),
              const Text(
                  'Guarda este código fuera del móvil. Permite recuperar tu cuenta y sustituye cualquier código anterior.'),
              const SizedBox(height: 12),
              Paper(child: SelectableText(code!)),
              TextButton.icon(
                  onPressed: () => perform(context,
                      () => Clipboard.setData(ClipboardData(text: code!)),
                      success: 'Código copiado'),
                  icon: const Icon(Icons.copy),
                  label: const Text('Copiar mi código')),
            ],
            TextButton(
                onPressed: () => push(context, RecoveryPage(store: s)),
                child: const Text('Ya tengo cuenta: recuperar con código')),
            if (s.data['remoteUserId'] != null)
              Details('Más opciones de mi cuenta', children: [
                OutlinedButton(
                    onPressed: () => perform(context, RemoteSync(s).pull,
                        success:
                            'Progreso recuperado; los conflictos se conservan'),
                    child: const Text('Descargar tarjetas y progreso')),
                OutlinedButton(
                    onPressed: () => push(context, WorkspacePage(store: s)),
                    child: const Text('Sincronizar notas y plan')),
                TextButton(
                    onPressed: () {
                      setState(() => code = null);
                      push(context, RecoveryPage(store: s, create: true));
                    },
                    child: const Text('Renovar código de recuperación')),
                TextButton(
                    onPressed: () => perform(context, () async {
                          await RemoteSync(s).disconnect();
                          if (mounted) setState(() => code = null);
                        }),
                    child: const Text('Cerrar sesión en este dispositivo')),
              ]),
          ],
          OutlinedButton.icon(
              onPressed: () => perform(context, () async {
                    await SharePlus.instance
                        .share(backupParameters(s.export()));
                  }),
              icon: const Icon(Icons.file_download_outlined),
              label: const Text('Guardar copia de mis datos')),
          TextButton(
              onPressed: () => push(context, SettingsPage(store: s)),
              child: const Text('Restaurar una copia y gestionar mis datos')),
          if (s.list('syncConflicts').isNotEmpty)
            Details('Cambios que necesitan revisión', children: [
              Text(
                  '${s.list('syncConflicts').length} conflictos conservados sin sobrescribir tus datos.'),
              ...s.list('syncConflicts').map((c) => Text(
                  c['kind'] == 'pending_reviews'
                      ? 'Hay repasos locales pendientes de subir.'
                      : 'Una tarjeta cambió en dos dispositivos.')),
            ]),
        ]));
  }
}

class SettingsPage extends StatelessWidget {
  final AppStore store;
  const SettingsPage({super.key, required this.store});
  Future<void> export(BuildContext context) => perform(context, () async {
        final text = store.export();
        await SharePlus.instance.share(backupParameters(text));
      });
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: PageBody(children: [
        Details('Mi objetivo de estudio', children: [
          const Text(
              'Puedes leer, repasar y usar todas las herramientas con cualquier objetivo. Tu planificación se configura desde Mi plan.'),
          DropdownButtonFormField<String>(
              initialValue: store.profile['goal'] ??
                  (store.mode == 'Universidad'
                      ? 'Seguir mis asignaturas'
                      : store.mode == 'Oposiciones'
                          ? 'Preparar un examen'
                          : 'Leer y repasar'),
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Quiero…'),
              items: [
                'Leer y repasar',
                'Preparar un examen',
                'Seguir mis asignaturas'
              ].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
              onChanged: (value) => store.setProfile({
                    'goal': value,
                    'mode': value == 'Seguir mis asignaturas'
                        ? 'Universidad'
                        : value == 'Preparar un examen'
                            ? 'Oposiciones'
                            : 'Ambos'
                  })),
          DropdownButtonFormField<String>(
              initialValue:
                  store.availableSubjects.contains(store.profile['subject'])
                      ? store.profile['subject']
                      : store.availableSubjects.first,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Materia principal'),
              items: store.availableSubjects
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (value) => store.setProfile({'subject': value})),
        ]),
        const Section('Preferencias'),
        Paper(
            padding: EdgeInsets.zero,
            child: Column(children: [
              SwitchListTile(
                  value: store.dark,
                  secondary: const Icon(Icons.dark_mode_outlined),
                  title: const Text('Modo oscuro'),
                  onChanged: (v) {
                    store.data['dark'] = v;
                    store.save();
                  }),
              ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: const Text('Plan y asignaturas'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => push(context, PlannerPage(store: store))),
              ListTile(
                  leading: const Icon(Icons.bar_chart),
                  title: const Text('Progreso e historial'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => push(context, ProgressPage(store: store))),
              ListTile(
                  leading: const Icon(Icons.workspace_premium_outlined),
                  title: const Text('Planes y suscripciones'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => push(context, const PlansPage())),
            ])),
        Details('Conexión avanzada', children: [
          TextFormField(
              initialValue: store.data['apiUrl'] ?? '',
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Servidor HTTPS'),
              onChanged: (v) {
                store.data['apiUrl'] = v.trim();
                store.save();
              }),
        ]),
        const Section('Privacidad y control'),
        Paper(
            padding: EdgeInsets.zero,
            child: Column(children: [
              SwitchListTile(
                  value: store.data['analyticsConsent'] ?? false,
                  title: const Text('Consentimiento de analítica opcional'),
                  subtitle:
                      const Text('No hay proveedor de analítica conectado.'),
                  onChanged: (v) {
                    store.data['analyticsConsent'] = v;
                    store.save();
                  }),
              SwitchListTile(
                  value: store.data['marketingConsent'] ?? false,
                  title: const Text('Comunicaciones comerciales opcionales'),
                  subtitle: const Text(
                      'No se envían comunicaciones desde esta versión.'),
                  onChanged: (v) {
                    store.data['marketingConsent'] = v;
                    store.save();
                  }),
              if (store.data['remoteUserId'] != null) ...[
                ListTile(
                    leading: const Icon(Icons.cloud_download_outlined),
                    title: const Text('Exportar datos del servidor'),
                    onTap: () => perform(context, () async {
                          final result = await RemoteSync(store).exportRemote();
                          await SharePlus.instance.share(ShareParams(
                              text: jsonEncode(result),
                              subject: 'LexMemoria · exportación remota'));
                        })),
                ListTile(
                    leading: const Icon(Icons.cloud_off_outlined),
                    title: const Text('Eliminar mi identidad y datos remotos'),
                    onTap: () async {
                      if (await confirm(context, 'Eliminar cuenta remota',
                          'Eliminará tarjetas e historial del servidor. Tus datos de este dispositivo se conservan. Exporta antes una copia.')) {
                        if (context.mounted) {
                          await perform(context, RemoteSync(store).eraseRemote,
                              success: 'Cuenta y datos remotos eliminados');
                        }
                      }
                    }),
              ],
              ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('Exportar todos mis datos'),
                  subtitle: const Text('JSON portable, sin credenciales'),
                  onTap: () => export(context)),
              ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('Restaurar copia JSON'),
                  onTap: () => perform(context, () async {
                        final result = await FilePicker.platform.pickFiles(
                            type: FileType.custom,
                            allowedExtensions: ['json'],
                            withData: true);
                        if (result == null) return;
                        final bytes = result.files.single.bytes;
                        if (bytes == null || bytes.length > 64 * 1024 * 1024) {
                          throw const FormatException(
                              'La copia debe ser menor de 64 MB.');
                        }
                        if (!context.mounted ||
                            !await confirm(context, 'Restaurar copia',
                                'Sustituirá los datos locales. Exporta primero una copia de los actuales.')) {
                          return;
                        }
                        await store.restore(utf8.decode(bytes));
                      })),
              ListTile(
                  leading: const Icon(Icons.privacy_tip_outlined),
                  title: const Text('Privacidad y fuentes'),
                  onTap: () => push(context, const PrivacyPage())),
              ListTile(
                  leading: const Icon(Icons.delete_outline,
                      color: Color(0xffbb3545)),
                  title: const Text('Borrar datos de este dispositivo'),
                  onTap: () async {
                    if (await confirm(
                        context,
                        '¿Borrar todos los datos locales?',
                        'Se eliminarán tarjetas, notas, revisiones, descargas y ajustes de este dispositivo. La acción no se puede deshacer. Exporta una copia antes de confirmar.')) {
                      if (context.mounted) await perform(context, store.reset);
                    }
                  }),
            ])),
        const SizedBox(height: 24),
        const Text(
            'LexMemoria 0.4.0 · Versión de prueba\nProducto educativo independiente de las administraciones públicas.',
            style: TextStyle(fontSize: 12)),
      ]));
}

class PlansPage extends StatelessWidget {
  const PlansPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Planes transparentes')),
      body: const PageBody(children: [
        Text('El conocimiento jurídico, accesible.',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
        SizedBox(height: 16),
        Text(
            'La consulta de las fuentes legales públicas no se bloquea por un plan de pago.'),
        SizedBox(height: 24),
        Paper(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Badge('Disponible en desarrollo'),
          SizedBox(height: 16),
          Text('Free · 0 €',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          Text(
              'Biblioteca, lectura de descargas, tarjetas privadas, repaso, notas, planificación y simulacros locales.')
        ])),
        SizedBox(height: 16),
        Paper(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Badge('Hipótesis comercial · no contratable', warning: true),
          SizedBox(height: 16),
          Text('Estudiante Plus · 3,99 €/mes',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          Text(
              'Precio experimental sujeto a validación, impuestos y configuración de tienda. Sin compra ni renovación disponibles.')
        ])),
        SizedBox(height: 16),
        Paper(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Badge('Hipótesis comercial · no contratable', warning: true),
          SizedBox(height: 16),
          Text('Opositor Pro · 7,99 €/mes',
              style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          Text(
              'Herramientas avanzadas previstas. No se cobran importes ni se conceden derechos de tienda sin validación del servidor.')
        ])),
        SizedBox(height: 24),
        Text(
            'Compras y restauración no habilitadas: faltan productos, credenciales y pruebas sandbox de Google Play y App Store. Ninguna promoción activa cobros automáticos.'),
      ]));
}

class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Privacidad, fuentes y alcance')),
      body: PageBody(children: [
        Text('Tu estudio es tuyo.',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        const Paper(
            child: Text(
                'Esta versión guarda datos en el almacenamiento local de la aplicación. No se envían notas ni respuestas a proveedores de IA. No hay publicidad ni analítica conectada. Las preferencias no implican suscripción a ningún servicio.')),
        const Section('Datos y conservación'),
        const Text(
            'Se guardan perfiles, tarjetas, notas, respuestas de simulacros e historial hasta que los borres. En Android/iOS se utiliza SQLCipher con clave separada en Keychain/Keystore; en web se usan preferencias locales sin este cifrado adicional. Evita guardar datos especialmente sensibles. Exportar o compartir crea una copia bajo tu control.'),
        const Section('Conexiones'),
        const Text(
            'Los textos del catálogo ampliado se descargan desde GitHub al solicitarlos, sin enviar tarjetas, notas ni progreso. Los paquetes públicos se guardan aparte y se pueden volver a descargar. Al sincronizar se consulta la API que configures. Al abrir una fuente sales al navegador y se aplica la privacidad del sitio de destino. La sincronización necesita un servidor configurado. La cuenta con código de recuperación permite trasladar tarjetas y progreso; el código debe guardarse fuera del móvil. Google y Apple requieren configurar sus proveedores antes de habilitarlos.'),
        const Section('Fuentes y contenido'),
        const Text(
            'Las referencias iniciales son un inventario de normas del BOE, no una declaración de cobertura, vigencia o revisión jurídica. Los textos consolidados son informativos. Las tarjetas personales no son contenido editorial verificado.'),
        TextButton(
            onPressed: () => openSource(
                context, 'https://www.boe.es/datosabiertos/api/api.php'),
            child: const Text('API y condiciones del BOE')),
        const Section('Antes de publicación'),
        const Text(
            'Deben identificarse responsable del tratamiento, contacto, base jurídica, proveedores, plazos y condiciones comerciales; verificar licencias, revisión editorial y derechos de las tiendas. Esta pantalla describe el comportamiento actual y no sustituye los textos legales de producción.'),
      ]));
}

class RecoveryPage extends StatefulWidget {
  final AppStore store;
  final bool create;
  const RecoveryPage({super.key, required this.store, this.create = false});
  @override
  State<RecoveryPage> createState() => _RecoveryPageState();
}

class _RecoveryPageState extends State<RecoveryPage> {
  final input = TextEditingController();
  String? generated;
  bool busy = false;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!widget.create && input.text.trim().length < 20) {
      toast(context, 'Introduce el código completo.');
      return;
    }
    setState(() => busy = true);
    await perform(context, () async {
      final remote = RemoteSync(widget.store);
      final code = widget.create
          ? await remote.recoveryCode()
          : await remote.recover(input.text);
      if (mounted) setState(() => generated = code);
    });
    if (mounted) setState(() => busy = false);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(
          title: Text(widget.create
              ? 'Código de recuperación'
              : 'Recuperar identidad')),
      body: PageBody(children: [
        Text('Continúa en otro dispositivo.',
            style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        if (generated == null) ...[
          Text(widget.create
              ? 'Se generará un código de un solo uso. Sustituye al anterior; guárdalo fuera de este dispositivo.'
              : 'Introduce el código que guardaste. Recuperar la identidad cierra las sesiones anteriores y genera un código nuevo.'),
          if (!widget.create) ...[
            const SizedBox(height: 20),
            TextField(
                controller: input,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration:
                    const InputDecoration(labelText: 'Código de recuperación'))
          ],
          const SizedBox(height: 24),
          FilledButton(
              onPressed: busy ? null : submit,
              child: Text(busy
                  ? 'Procesando…'
                  : widget.create
                      ? 'Generar código nuevo'
                      : 'Recuperar y cerrar otras sesiones')),
        ] else ...[
          const Badge('Guarda ahora el código nuevo'),
          const SizedBox(height: 16),
          Paper(child: SelectableText(generated!)),
          const SizedBox(height: 16),
          const Text(
              'Este código permite acceder a tu identidad. Solo se muestra en esta pantalla y no se incluye en las copias de datos.'),
          TextButton.icon(
              onPressed: () => perform(context,
                  () => Clipboard.setData(ClipboardData(text: generated!)),
                  success: 'Código copiado'),
              icon: const Icon(Icons.copy),
              label: const Text('Copiar código')),
          if (!widget.create)
            FilledButton(
                onPressed: () => perform(context, RemoteSync(widget.store).pull,
                    success: 'Tarjetas e historial descargados'),
                child: const Text('Descargar mis tarjetas y progreso')),
        ],
      ]));
}
