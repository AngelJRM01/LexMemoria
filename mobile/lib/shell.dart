import 'package:flutter/material.dart' hide Badge;
import 'models.dart';
import 'store.dart';
import 'widgets.dart';
import 'study.dart';
import 'library.dart';
import 'profile.dart';
import 'planning.dart';

class WelcomePage extends StatefulWidget {
  final AppStore store;
  const WelcomePage({super.key, required this.store});
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}
class _WelcomePageState extends State<WelcomePage> {
  var started = false;
  String mode = 'Ambos', subject = 'Constitucional', track = tracks.first, region = 'Estatal', level = 'Inicial';
  double hours = 1;
  DateTime? exam;
  @override
  Widget build(BuildContext context) => Scaffold(body: SafeArea(child: PageBody(children: [
    const SizedBox(height: 32), const Row(children: [Icon(Icons.balance, color: ink, size: 32), SizedBox(width: 10), Text('LEXMEMORIA', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2, color: ink))]),
    const SizedBox(height: 48), Text('El Derecho cambia.\nTu conocimiento\ntambién.', style: Theme.of(context).textTheme.headlineLarge),
    const SizedBox(height: 18), const Text('Estudia con contexto, recuerda con método y conoce siempre la fuente.', style: TextStyle(fontSize: 18, height: 1.6)),
    const SizedBox(height: 32),
    if (!started) ...[
      const Paper(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.link, color: teal), title: Text('Cada tarjeta, una fuente'), subtitle: Text('Referencias y versiones jurídicas visibles.')),
        ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.offline_bolt_outlined, color: teal), title: Text('Tu estudio va contigo'), subtitle: Text('Mazos y textos descargados disponibles offline.')),
        ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.school_outlined, color: teal), title: Text('Un método, dos caminos'), subtitle: Text('Universidad y oposiciones sin perder progreso.'))])),
      const SizedBox(height: 28), FilledButton(onPressed: () => setState(() => started = true), child: const Text('Preparar mi plan')),
      TextButton(onPressed: () => perform(context, () async { widget.store.data['onboarded'] = true; await widget.store.save(); }), child: const Text('Explorar sin cuenta')),
    ] else ...[
      const Section('¿Qué quieres preparar?'),
      Wrap(spacing: 8, children: ['Universidad', 'Oposiciones', 'Ambos'].map((m) => ChoiceChip(label: Text(m), selected: mode == m, onSelected: (_) => setState(() => mode = m))).toList()),
      const SizedBox(height: 20), DropdownButtonFormField<String>(initialValue: subject, decoration: const InputDecoration(labelText: 'Materia principal'), isExpanded: true,
        items: subjects.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => subject = v!),
      if (mode != 'Universidad') ...[const SizedBox(height: 16), DropdownButtonFormField<String>(initialValue: track, isExpanded: true,
        decoration: const InputDecoration(labelText: 'Oposición · plantilla no verificada'), items: tracks.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => track = v!)],
      const SizedBox(height: 16), TextFormField(decoration: const InputDecoration(labelText: 'Territorio / comunidad autónoma'), initialValue: region, onChanged: (v) => region = v),
      const SizedBox(height: 16), DropdownButtonFormField<String>(initialValue: level, decoration: const InputDecoration(labelText: 'Nivel'),
        items: ['Inicial', 'Intermedio', 'Avanzado'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(), onChanged: (v) => level = v!),
      const SizedBox(height: 16), Text('Disponibilidad: ${hours.toStringAsFixed(1)} h al día'), Slider(value: hours, min: .5, max: 8, divisions: 15, label: '$hours h', onChanged: (v) => setState(() => hours = v)),
      OutlinedButton.icon(onPressed: () async { final v = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)));
        if (v != null) setState(() => exam = v); }, icon: const Icon(Icons.event_outlined), label: Text(exam == null ? 'Fecha de examen (opcional)' : civilDate(exam!))),
      const SizedBox(height: 20), FilledButton(onPressed: () => perform(context, () async {
        await widget.store.setProfile({'mode': mode, 'subject': subject, 'track': track, 'region': region, 'level': level, 'hours': hours,
          'examDate': exam?.toIso8601String(), 'dailyGoal': 20});
        widget.store.data['onboarded'] = true; await widget.store.save();
      }), child: const Text('Comenzar mi camino')),
    ],
    const SizedBox(height: 24), const Text('Producto educativo independiente del BOE. Sin garantías de aprobado. El catálogo muestra su cobertura real y la revisión pendiente.', style: TextStyle(fontSize: 12)),
  ])));
}

class AppShell extends StatefulWidget {
  final AppStore store;
  const AppShell({super.key, required this.store});
  @override
  State<AppShell> createState() => _AppShellState();
}
class _AppShellState extends State<AppShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    final s = widget.store;
    final pages = [HomePage(store: s, navigate: (i) => setState(() => index = i)), StudyPage(store: s), LibraryPage(store: s), UpdatesPage(store: s), ProfilePage(store: s)];
    const destinations = [(Icons.grid_view_outlined, 'Inicio'), (Icons.style_outlined, 'Estudiar'), (Icons.menu_book_outlined, 'Biblioteca'), (Icons.notifications_none, 'Actualidad'), (Icons.person_outline, 'Perfil')];
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(appBar: AppBar(title: const Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.balance, size: 24), SizedBox(width: 10), Text('LexMemoria', style: TextStyle(fontWeight: FontWeight.w700, letterSpacing: -.5))]),
      actions: [IconButton(tooltip: 'Progreso', onPressed: () => push(context, ProgressPage(store: s)), icon: const Icon(Icons.bar_chart)), const SizedBox(width: 8)]),
      body: SafeArea(child: Row(children: [if (wide) NavigationRail(selectedIndex: index, extended: true, minExtendedWidth: 220,
        onDestinationSelected: (v) => setState(() => index = v), destinations: destinations.map((d) => NavigationRailDestination(icon: Icon(d.$1), label: Text(d.$2))).toList()),
        Expanded(child: IndexedStack(index: index, children: pages))])),
      bottomNavigationBar: wide ? null : NavigationBar(selectedIndex: index, onDestinationSelected: (v) => setState(() => index = v),
        destinations: destinations.map((d) => NavigationDestination(icon: Icon(d.$1), label: d.$2)).toList()));
  }
}
class HomePage extends StatelessWidget {
  final AppStore store;
  final ValueChanged<int> navigate;
  const HomePage({super.key, required this.store, required this.navigate});
  @override
  Widget build(BuildContext context) {
    final due = store.due().length;
    final restDay = !isStudyDay(DateTime.now(), store.profile);
    final today = store.list('reviews').where((r) => civilDate(DateTime.parse(r['occurredAt']).toLocal()) == civilDate(DateTime.now())).length;
    final goal = (store.profile['dailyGoal'] as num? ?? 20).toInt();
    final downloaded = store.catalogue.where((n) => n['units'] != null).length;
    return PageBody(children: [
      Text(civilDate(DateTime.now()), style: const TextStyle(letterSpacing: 1.4, fontSize: 12, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8), Text('Un poco cada día.\nMucho por recordar.', style: Theme.of(context).textTheme.headlineLarge),
      const SizedBox(height: 16), Wrap(spacing: 8, runSpacing: 8, children: [Badge(store.mode), Badge(store.profile['subject'] ?? 'Estudio libre'), const Badge('Modo local')]),
      const SizedBox(height: 24), Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: ink, borderRadius: BorderRadius.circular(20)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('TU SESIÓN DE HOY', style: TextStyle(color: Color(0xff99c8d6), letterSpacing: 1.5, fontSize: 12)),
          const SizedBox(height: 18), Text(restDay ? 'Hoy tienes descanso' : '$due tarjetas por repasar', style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 8), Text('$today de $goal revisiones de tu objetivo', style: const TextStyle(color: Color(0xffd2deed))),
          const SizedBox(height: 18), ClipRRect(borderRadius: BorderRadius.circular(8), child: LinearProgressIndicator(value: (today / goal).clamp(0, 1), minHeight: 6, color: const Color(0xff53d3b7), backgroundColor: Colors.white24)),
          const SizedBox(height: 24), FilledButton.icon(style: FilledButton.styleFrom(backgroundColor: const Color(0xffd4f5e9), foregroundColor: ink),
            onPressed: () => restDay ? push(context, PlannerPage(store: store)) : due > 0 ? push(context, ReviewPage(store: store, queue: store.due())) : navigate(1), icon: const Icon(Icons.play_arrow_rounded), label: Text(restDay ? 'Consultar mi plan' : due > 0 ? 'Comenzar repaso' : 'Crear mi primer mazo'))])),
      const Section('Tu camino de estudio'),
      Paper(child: Column(children: [ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.calendar_month_outlined, color: teal), title: const Text('Planifica con calma'),
        subtitle: const Text('Objetivos, descansos y fecha de examen'), trailing: const Icon(Icons.chevron_right), onTap: () => push(context, PlannerPage(store: store))),
        const Divider(), ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.fact_check_outlined, color: teal), title: const Text('Ponte a prueba'),
          subtitle: const Text('Simulacros personales con corrección explicada'), trailing: const Icon(Icons.chevron_right), onTap: () => push(context, ExamPage(store: store)))])),
      const Section('Fuentes claras. Cobertura honesta.'),
      Paper(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Badge('Catálogo inicial · pendiente de revisión', warning: true), const SizedBox(height: 16),
        Text('${store.catalogue.length} referencias identificadas', style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 8),
        Text('$downloaded textos descargados · 0 materiales con certificación jurídica en esta instalación.'),
        const SizedBox(height: 16), TextButton.icon(onPressed: () => navigate(2), icon: const Icon(Icons.arrow_forward), label: const Text('Explorar la biblioteca'))])),
      const Section('Constancia, sin presión'),
      Paper(child: Wrap(spacing: 10, runSpacing: 10, children: List.generate(14, (i) {
        final date = DateTime.now().subtract(Duration(days: 13 - i));
        final count = store.list('reviews').where((r) => civilDate(DateTime.parse(r['occurredAt']).toLocal()) == civilDate(date)).length;
        return Semantics(label: '${civilDate(date)}: $count revisiones', child: Container(width: 36, height: 44,
          alignment: Alignment.center, decoration: BoxDecoration(color: count > 0 ? teal : Theme.of(context).colorScheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(8)),
          child: Text('${date.day}', style: TextStyle(color: count > 0 ? Colors.white : null))));
      }))),
      const SizedBox(height: 20), Text(store.data['lastSync'] == null ? 'Sin sincronización remota. Tu progreso se guarda en este dispositivo.' : 'Última sincronización: ${store.data['lastSync']}', style: const TextStyle(fontSize: 12)),
    ]);
  }
}
