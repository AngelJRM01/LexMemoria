import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart';
import 'store.dart';
import 'models.dart';
import 'widgets.dart';
import 'planning.dart';
import 'remote.dart';

class ProfilePage extends StatelessWidget {
  final AppStore store;
  const ProfilePage({super.key, required this.store});
  Future<void> export(BuildContext context) => perform(context, () async {
    final text = store.export();
    await SharePlus.instance.share(ShareParams(text: text, subject: 'LexMemoria · copia de mis datos'));
  });
  @override
  Widget build(BuildContext context) => PageBody(children: [
    Text('Tu espacio de estudio', style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 24),
    Paper(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const CircleAvatar(radius: 28, backgroundColor: Color(0xffe3f4f0), child: Icon(Icons.person_outline, color: ink, size: 30)),
      const SizedBox(height: 16), Text('Perfil local', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8),
      const Text('Tus datos se conservan en este dispositivo. Exporta una copia antes de cambiar de móvil o borrar la aplicación.'), const SizedBox(height: 16), const Badge('Sin cuenta · sin cobros automáticos')])),
    const Section('Mis itinerarios'),
    Wrap(spacing: 8, runSpacing: 8, children: ['Universidad', 'Oposiciones', 'Ambos'].map((m) => ChoiceChip(label: Text(m), selected: store.mode == m,
      onSelected: (_) => perform(context, () => store.setProfile({'mode': m}), success: 'Itinerario actualizado; progreso conservado'))).toList()),
    const SizedBox(height: 16), DropdownButtonFormField<String>(initialValue: store.profile['subject'] ?? subjects.first, decoration: const InputDecoration(labelText: 'Materia activa'),
      items: subjects.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => store.setProfile({'subject': v})),
    const SizedBox(height: 16), DropdownButtonFormField<String>(initialValue: store.profile['track'] ?? tracks.first, isExpanded: true, decoration: const InputDecoration(labelText: 'Oposición · plantilla no verificada'),
      items: tracks.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => store.setProfile({'track': v})),
    const Section('Preferencias'),
    Paper(padding: EdgeInsets.zero, child: Column(children: [
      SwitchListTile(value: store.dark, secondary: const Icon(Icons.dark_mode_outlined), title: const Text('Modo oscuro'), onChanged: (v) { store.data['dark'] = v; store.save(); }),
      ListTile(leading: const Icon(Icons.calendar_month_outlined), title: const Text('Plan y asignaturas'), trailing: const Icon(Icons.chevron_right), onTap: () => push(context, PlannerPage(store: store))),
      ListTile(leading: const Icon(Icons.bar_chart), title: const Text('Progreso e historial'), trailing: const Icon(Icons.chevron_right), onTap: () => push(context, ProgressPage(store: store))),
      ListTile(leading: const Icon(Icons.workspace_premium_outlined), title: const Text('Planes y suscripciones'), trailing: const Icon(Icons.chevron_right), onTap: () => push(context, const PlansPage())),
    ])),
    const Section('Servidor y sincronización'),
    TextFormField(initialValue: store.data['apiUrl'] ?? '', keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'URL de API HTTPS', hintText: 'https://api.tu-dominio.es'),
      onChanged: (v) { store.data['apiUrl'] = v.trim(); store.save(); }), const SizedBox(height: 12),
    const Text('La identidad opcional permite subir tarjetas y revisiones con reintentos idempotentes. Los tokens se guardan en Keychain/Keystore. La recuperación de cuenta en otro móvil aún no está disponible.', style: TextStyle(fontSize: 12)),
    const SizedBox(height: 12),
    Wrap(spacing: 8, runSpacing: 8, children: [
      if (store.data['remoteUserId'] == null) OutlinedButton(onPressed: () => perform(context, RemoteSync(store).activate, success: 'Identidad remota creada en este dispositivo'), child: const Text('Activar identidad remota'))
      else ...[FilledButton.icon(onPressed: () => perform(context, RemoteSync(store).upload, success: 'Tarjetas y revisiones sincronizadas'), icon: const Icon(Icons.sync), label: const Text('Subir progreso')),
        TextButton(onPressed: () => perform(context, RemoteSync(store).disconnect, success: 'Sesión remota revocada'), child: const Text('Desconectar'))],
    ]),
    const Section('Privacidad y control'),
    Paper(padding: EdgeInsets.zero, child: Column(children: [
      SwitchListTile(value: store.data['analyticsConsent'] ?? false, title: const Text('Consentimiento de analítica opcional'), subtitle: const Text('No hay proveedor de analítica conectado.'), onChanged: (v) { store.data['analyticsConsent'] = v; store.save(); }),
      SwitchListTile(value: store.data['marketingConsent'] ?? false, title: const Text('Comunicaciones comerciales opcionales'), subtitle: const Text('No se envían comunicaciones desde esta versión.'), onChanged: (v) { store.data['marketingConsent'] = v; store.save(); }),
      if (store.data['remoteUserId'] != null) ...[
        ListTile(leading: const Icon(Icons.cloud_download_outlined), title: const Text('Exportar datos del servidor'), onTap: () => perform(context, () async {
          final result = await RemoteSync(store).exportRemote();
          await SharePlus.instance.share(ShareParams(text: jsonEncode(result), subject: 'LexMemoria · exportación remota'));
        })),
        ListTile(leading: const Icon(Icons.cloud_off_outlined), title: const Text('Eliminar mi identidad y datos remotos'), onTap: () async {
          if (await confirm(context, 'Eliminar cuenta remota', 'Eliminará tarjetas e historial del servidor. Tus datos de este dispositivo se conservan. Exporta antes una copia.')) {
            if (context.mounted) await perform(context, RemoteSync(store).eraseRemote, success: 'Cuenta y datos remotos eliminados');
          }
        }),
      ],
      ListTile(leading: const Icon(Icons.file_download_outlined), title: const Text('Exportar todos mis datos'), subtitle: const Text('JSON portable, sin credenciales'), onTap: () => export(context)),
      ListTile(leading: const Icon(Icons.restore), title: const Text('Restaurar copia JSON'), onTap: () => perform(context, () async {
        final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
        if (result == null) return;
        final bytes = result.files.single.bytes;
        if (bytes == null || bytes.length > 10000000) throw const FormatException('La copia debe ser menor de 10 MB.');
        if (!context.mounted || !await confirm(context, 'Restaurar copia', 'Sustituirá los datos locales. Exporta primero una copia de los actuales.')) return;
        await store.restore(utf8.decode(bytes));
      })),
      ListTile(leading: const Icon(Icons.privacy_tip_outlined), title: const Text('Privacidad y fuentes'), onTap: () => push(context, const PrivacyPage())),
      ListTile(leading: const Icon(Icons.delete_outline, color: Color(0xffbb3545)), title: const Text('Borrar datos de este dispositivo'), onTap: () async {
        if (await confirm(context, '¿Borrar todos los datos locales?', 'Se eliminarán tarjetas, notas, revisiones, descargas y ajustes de este dispositivo. La acción no se puede deshacer. Exporta una copia antes de confirmar.')) {
          if (context.mounted) await perform(context, store.reset);
        }
      }),
    ])), const SizedBox(height: 24), const Text('LexMemoria 0.1.0 · Desarrollo\nProducto educativo independiente de las administraciones públicas.', style: TextStyle(fontSize: 12)),
  ]);
}
class PlansPage extends StatelessWidget {
  const PlansPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Planes transparentes')), body: const PageBody(children: [
    Text('El conocimiento jurídico, accesible.', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold)), SizedBox(height: 16),
    Text('La consulta de las fuentes legales públicas no se bloquea por un plan de pago.'), SizedBox(height: 24),
    Paper(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Badge('Disponible en desarrollo'), SizedBox(height: 16), Text('Free · 0 €', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
      SizedBox(height: 10), Text('Biblioteca, lectura de descargas, tarjetas privadas, repaso, notas, planificación y simulacros locales.')])), SizedBox(height: 16),
    Paper(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Badge('Hipótesis comercial · no contratable', warning: true), SizedBox(height: 16), Text('Estudiante Plus · 3,99 €/mes', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      SizedBox(height: 10), Text('Precio experimental sujeto a validación, impuestos y configuración de tienda. Sin compra ni renovación disponibles.')])), SizedBox(height: 16),
    Paper(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Badge('Hipótesis comercial · no contratable', warning: true), SizedBox(height: 16), Text('Opositor Pro · 7,99 €/mes', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
      SizedBox(height: 10), Text('Herramientas avanzadas previstas. No se cobran importes ni se conceden derechos de tienda sin validación del servidor.')])), SizedBox(height: 24),
    Text('Compras y restauración no habilitadas: faltan productos, credenciales y pruebas sandbox de Google Play y App Store. Ninguna promoción activa cobros automáticos.'),
  ]));
}
class PrivacyPage extends StatelessWidget {
  const PrivacyPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Privacidad, fuentes y alcance')), body: PageBody(children: [
    Text('Tu estudio es tuyo.', style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 20),
    const Paper(child: Text('Esta versión guarda datos en el almacenamiento local de la aplicación. No se envían notas ni respuestas a proveedores de IA. No hay publicidad ni analítica conectada. Las preferencias no implican suscripción a ningún servicio.')),
    const Section('Datos y conservación'), const Text('Se guardan perfiles, tarjetas, notas, respuestas de simulacros e historial hasta que los borres. El almacenamiento local no incorpora cifrado adicional: evita guardar datos especialmente sensibles. Exportar o compartir crea una copia bajo tu control.'),
    const Section('Conexiones'), const Text('Al sincronizar se consulta la API que configures. Al abrir una fuente sales al navegador y se aplica la privacidad del sitio de destino. El backend de desarrollo permite identidades invitadas; no incluye recuperación por email ni OAuth.'),
    const Section('Fuentes y contenido'), const Text('Las referencias iniciales son un inventario de normas del BOE, no una declaración de cobertura, vigencia o revisión jurídica. Los textos consolidados son informativos. Las tarjetas personales no son contenido editorial verificado.'),
    TextButton(onPressed: () => openSource(context, 'https://www.boe.es/datosabiertos/api/api.php'), child: const Text('API y condiciones del BOE')),
    const Section('Antes de publicación'), const Text('Deben identificarse responsable del tratamiento, contacto, base jurídica, proveedores, plazos y condiciones comerciales; verificar licencias, revisión editorial y derechos de las tiendas. Esta pantalla describe el comportamiento actual y no sustituye los textos legales de producción.'),
  ]));
}
