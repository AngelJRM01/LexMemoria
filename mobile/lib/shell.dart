import 'package:flutter/material.dart' hide Badge;
import 'models.dart';
import 'store.dart';
import 'widgets.dart';
import 'study.dart';
import 'library.dart';
import 'profile.dart';
import 'planning.dart';
import 'collaboration.dart';

class WelcomePage extends StatefulWidget {
  final AppStore store;
  const WelcomePage({super.key, required this.store});
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  bool started = false;
  String goal = 'Leer y repasar', subject = subjects.first;
  @override
  Widget build(BuildContext context) => Scaffold(
          body: SafeArea(
              child: PageBody(children: [
        const SizedBox(height: 32),
        const Icon(Icons.balance, color: teal, size: 40),
        const SizedBox(height: 32),
        Text(
            started
                ? '¿Cómo quieres empezar?'
                : 'Estudia Derecho,\nun paso cada día.',
            style: Theme.of(context).textTheme.headlineLarge),
        const SizedBox(height: 20),
        if (!started) ...[
          const Text(
              'Artículos claros y tarjetas preparadas. Empieza sin crear una cuenta.'),
          const SizedBox(height: 32),
          FilledButton(
              onPressed: () => setState(() => started = true),
              child: const Text('Elegir mi objetivo')),
          TextButton(
              onPressed: () => perform(context, () async {
                    widget.store.data['onboarded'] = true;
                    await widget.store.save();
                  }),
              child: const Text('Explorar sin cuenta')),
        ] else ...[
          ...['Leer y repasar', 'Preparar un examen', 'Seguir mis asignaturas']
              .map((value) => ListTile(
                  leading: Icon(value == goal
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked),
                  selected: value == goal,
                  onTap: () => setState(() => goal = value),
                  title: Text(value),
                  subtitle: value == goal
                      ? Text(value == 'Preparar un examen'
                          ? 'Podrás añadir fecha y temario a tu plan.'
                          : value == 'Seguir mis asignaturas'
                              ? 'Organiza el estudio por materia y evaluación.'
                              : 'Explora normas y repasa a tu ritmo.')
                      : null)),
          const SizedBox(height: 24),
          DropdownButtonFormField<String>(
              initialValue: subject,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Primera materia'),
              items: widget.store.availableSubjects
                  .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                  .toList(),
              onChanged: (v) => subject = v!),
          const SizedBox(height: 24),
          FilledButton(
              onPressed: () => perform(context, () async {
                    await widget.store.setProfile({
                      'goal': goal,
                      'mode': goal == 'Seguir mis asignaturas'
                          ? 'Universidad'
                          : goal == 'Preparar un examen'
                              ? 'Oposiciones'
                              : 'Ambos',
                      'subject': subject,
                      'dailyGoal': 20
                    });
                    widget.store.data['onboarded'] = true;
                    await widget.store.save();
                  }),
              child: const Text('Empezar con mis tarjetas')),
          TextButton(
              onPressed: () => setState(() => started = false),
              child: const Text('Volver')),
        ],
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
    final pages = [
      HomePage(store: s, navigate: (i) => setState(() => index = i)),
      StudyPage(store: s),
      LibraryPage(store: s),
      UpdatesPage(store: s),
      ProfilePage(store: s)
    ];
    const destinations = [
      (Icons.grid_view_outlined, 'Inicio'),
      (Icons.style_outlined, 'Estudiar'),
      (Icons.menu_book_outlined, 'Biblioteca'),
      (Icons.notifications_none, 'Actualidad'),
      (Icons.person_outline, 'Perfil')
    ];
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return Scaffold(
        appBar: AppBar(
            title: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.balance, size: 24),
              SizedBox(width: 10),
              Text('LexMemoria',
                  style: TextStyle(
                      fontWeight: FontWeight.w700, letterSpacing: -.5))
            ]),
            actions: [
              IconButton(
                  tooltip: 'Progreso',
                  onPressed: () => push(context, ProgressPage(store: s)),
                  icon: const Icon(Icons.bar_chart)),
              const SizedBox(width: 8)
            ]),
        body: SafeArea(
            child: Row(children: [
          if (wide)
            NavigationRail(
                selectedIndex: index,
                extended: true,
                minExtendedWidth: 220,
                onDestinationSelected: (v) => setState(() => index = v),
                destinations: destinations
                    .map((d) => NavigationRailDestination(
                        icon: Icon(d.$1), label: Text(d.$2)))
                    .toList()),
          Expanded(child: IndexedStack(index: index, children: pages))
        ])),
        bottomNavigationBar: wide
            ? null
            : NavigationBar(
                selectedIndex: index,
                onDestinationSelected: (v) => setState(() => index = v),
                destinations: destinations
                    .map((d) =>
                        NavigationDestination(icon: Icon(d.$1), label: d.$2))
                    .toList()));
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
    final today = store
        .list('reviews')
        .where((r) =>
            civilDate(DateTime.parse(r['occurredAt']).toLocal()) ==
            civilDate(DateTime.now()))
        .length;
    final goal = (store.profile['dailyGoal'] as num? ?? 20).toInt();
    return PageBody(children: [
      Text('Tu estudio de hoy',
          style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 24),
      Paper(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            restDay
                ? 'Hoy tienes descanso'
                : due > 0
                    ? '$due tarjetas para repasar'
                    : 'Tu sesión está al día',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text('$today de $goal repasos de tu objetivo'),
        const SizedBox(height: 20),
        LinearProgressIndicator(
            value: (today / goal.clamp(1, 200)).clamp(0, 1), minHeight: 5),
        const SizedBox(height: 24),
        FilledButton.icon(
            onPressed: () => restDay
                ? push(context, PlannerPage(store: store))
                : due > 0
                    ? push(
                        context, ReviewPage(store: store, queue: store.due()))
                    : navigate(1),
            icon: const Icon(Icons.play_arrow_rounded),
            label: Text(restDay
                ? 'Ver mi plan'
                : due > 0
                    ? 'Comenzar repaso'
                    : 'Explorar mis mazos')),
      ])),
      const SizedBox(height: 24),
      ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.menu_book_outlined),
          title: const Text('Leer una norma'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => navigate(2)),
      ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.calendar_month_outlined),
          title: const Text('Organizar mi estudio'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => push(context, PlannerPage(store: store))),
      ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.fact_check_outlined),
          title: const Text('Practicar un simulacro'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => push(context, ExamPage(store: store))),
      const SizedBox(height: 24),
      if (store.data['remoteUserId'] == null)
        TextButton.icon(
            onPressed: () => push(context, AccountPage(store: store)),
            icon: const Icon(Icons.cloud_outlined),
            label: const Text('Conservar mi progreso al cambiar de móvil')),
      if (store.data['remoteUserId'] != null)
        TextButton.icon(onPressed: () => push(context, CollaborationPage(store: store)),
            icon: const Icon(Icons.folder_shared_outlined), label: const Text('Materiales compartidos')),
    ]);
  }
}
