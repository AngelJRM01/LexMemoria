import 'package:flutter/material.dart' hide Badge;
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'store.dart';
import 'widgets.dart';

/// Returns a grade out of ten only for recorded assessments. Missing grades
/// contribute no points and never silently redistribute the published weights.
Json courseGrade(List<Json> assessments) {
  double weight = 0, completed = 0, earned = 0;
  for (final a in assessments) {
    final w = (a['weight'] as num).toDouble();
    final max = (a['maximum'] as num).toDouble();
    final score = (a['score'] as num?)?.toDouble();
    if (!w.isFinite ||
        w <= 0 ||
        w > 100 ||
        !max.isFinite ||
        max <= 0 ||
        (score != null && (!score.isFinite || score < 0 || score > max))) {
      throw const FormatException('Ponderación o calificación no válida.');
    }
    weight += w;
    if (score != null) {
      completed += w;
      earned += score / max * w / 10;
    }
  }
  if (weight > 100.000001) {
    throw const FormatException('Las ponderaciones superan el 100 %.');
  }
  return {'weight': weight, 'completedWeight': completed, 'earned': earned};
}

class UniversityPage extends StatefulWidget {
  final AppStore store;
  const UniversityPage({super.key, required this.store});
  @override
  State<UniversityPage> createState() => _UniversityPageState();
}

class _UniversityPageState extends State<UniversityPage> {
  bool archived = false;
  Future<void> addCourse() async {
    final title = TextEditingController(),
        institution = TextEditingController(),
        semester = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('Nueva asignatura'),
                content: Form(
                    key: form,
                    child: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      TextFormField(
                          controller: title,
                          maxLength: 160,
                          decoration:
                              const InputDecoration(labelText: 'Asignatura'),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Indica una asignatura'
                              : null),
                      TextField(
                          controller: institution,
                          maxLength: 160,
                          decoration: const InputDecoration(
                              labelText: 'Universidad / centro')),
                      TextField(
                          controller: semester,
                          maxLength: 80,
                          decoration: const InputDecoration(
                              labelText: 'Semestre / curso')),
                    ]))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('Cancelar')),
                  FilledButton(
                      onPressed: () {
                        if (form.currentState!.validate()) {
                          Navigator.pop(ctx, true);
                        }
                      },
                      child: const Text('Guardar'))
                ]));
    if (ok == true && mounted) {
      await perform(
          context,
          () => widget.store.add('courses', {
                'id': const Uuid().v4(),
                'title': title.text.trim(),
                'institution': institution.text.trim(),
                'semester': semester.text.trim(),
                'archived': false
              }));
    }
    title.dispose();
    institution.dispose();
    semester.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: widget.store,
      builder: (context, _) {
        final courses = widget.store
            .list('courses')
            .asMap()
            .entries
            .where((e) => (e.value['archived'] == true) == archived);
        return Scaffold(
            appBar: AppBar(title: const Text('Mis asignaturas')),
            body: SearchPageBody(header: [
              const Text('Organiza tus materias, temas y evaluaciones.'),
              const SizedBox(height: 16),
              Wrap(spacing: 8, children: [
                FilterChip(
                    label: const Text('Archivadas'),
                    selected: archived,
                    onSelected: (v) => setState(() => archived = v)),
                FilledButton.icon(
                    onPressed: addCourse,
                    icon: const Icon(Icons.add),
                    label: const Text('Añadir asignatura')),
              ]),
            ], children: [
              if (courses.isEmpty)
                const EmptyState(
                    title: 'Organiza tu semestre',
                    detail:
                        'Añade asignaturas, sus temas y las ponderaciones de tus evaluaciones.'),
              ...courses.map((e) => ListTile(
                  leading: const Icon(Icons.school_outlined),
                  title: Text(e.value['title']),
                  subtitle: Text(
                      '${e.value['institution'] ?? ''} · ${e.value['semester'] ?? ''}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => push(
                      context, CoursePage(store: widget.store, index: e.key)))),
            ]));
      });
}

class CoursePage extends StatelessWidget {
  final AppStore store;
  final String courseId;
  CoursePage({super.key, required this.store, required int index})
      : courseId = store.list('courses')[index]['id'];
  Future<void> update(Json course, {required Json expected}) =>
      store.updateCourse(course, expected: expected);

  Future<void> assessment(BuildContext context, Json course) async {
    final name = TextEditingController(),
        weight = TextEditingController(),
        maximum = TextEditingController(text: '10'),
        score = TextEditingController();
    final form = GlobalKey<FormState>();
    String? error;
    final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setState) => AlertDialog(
                    title: const Text('Añadir evaluación'),
                    content: Form(
                        key: form,
                        child: SingleChildScrollView(
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                              TextFormField(
                                  controller: name,
                                  decoration: const InputDecoration(
                                      labelText: 'Nombre de la evaluación'),
                                  validator: (v) =>
                                      v == null || v.trim().isEmpty
                                          ? 'Completa el nombre'
                                          : null),
                              TextField(
                                  controller: weight,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'Ponderación (%)')),
                              TextField(
                                  controller: maximum,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'Puntuación máxima')),
                              TextField(
                                  controller: score,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                      labelText: 'Nota obtenida (opcional)')),
                              if (error != null)
                                Text(error!,
                                    style: TextStyle(
                                        color:
                                            Theme.of(ctx).colorScheme.error)),
                            ]))),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('Cancelar')),
                      FilledButton(
                          onPressed: () {
                            if (!form.currentState!.validate()) return;
                            try {
                              final a = {
                                'id': const Uuid().v4(),
                                'title': name.text.trim(),
                                'weight': double.parse(
                                    weight.text.replaceAll(',', '.')),
                                'maximum': double.parse(
                                    maximum.text.replaceAll(',', '.')),
                                'score': score.text.trim().isEmpty
                                    ? null
                                    : double.parse(
                                        score.text.replaceAll(',', '.'))
                              };
                              courseGrade([
                                ...(course['assessments'] as List? ?? [])
                                    .map((v) => Json.from(v)),
                                a
                              ]);
                              Navigator.pop(ctx, true);
                            } catch (_) {
                              setState(() => error =
                                  'Revisa los números y que la suma de ponderaciones no supere el 100 %.');
                            }
                          },
                          child: const Text('Guardar'))
                    ])));
    if (ok == true) {
      await update({
        ...course,
        'assessments': [
          ...(course['assessments'] as List? ?? []),
          {
            'id': const Uuid().v4(),
            'title': name.text.trim(),
            'weight': double.parse(weight.text.replaceAll(',', '.')),
            'maximum': double.parse(maximum.text.replaceAll(',', '.')),
            'score': score.text.trim().isEmpty
                ? null
                : double.parse(score.text.replaceAll(',', '.'))
          }
        ]
      }, expected: course);
    }
    for (final c in [name, weight, maximum, score]) {
      c.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final course =
            store.list('courses').where((c) => c['id'] == courseId).firstOrNull;
        if (course == null) {
          return Scaffold(
              appBar: AppBar(title: const Text('Asignatura')),
              body: const PageBody(children: [
                Text(
                    'Esta asignatura ya no está disponible. Vuelve a la lista para consultar tus asignaturas actuales.')
              ]));
        }
        final assessments = (course['assessments'] as List? ?? [])
            .map((v) => Json.from(v))
            .toList();
        final grade = courseGrade(assessments);
        return Scaffold(
            appBar: AppBar(title: Text(course['title'])),
            body: PageBody(children: [
              Badge(
                  '${course['semester'] ?? 'Sin semestre'} · programa personal',
                  warning: true),
              const Section('Evaluaciones y ponderaciones'),
              Text(
                  '${(grade['earned'] as num).toStringAsFixed(2)} / 10 puntos acumulados · ${grade['completedWeight']} % evaluado'),
              Text(
                  '${grade['weight']} % de ponderación registrada. No se predicen notas futuras.'),
              ...assessments.map((a) => ListTile(
                  title: Text(a['title']),
                  subtitle: Text(
                      '${a['weight']} % · ${a['score'] ?? 'Pendiente'} / ${a['maximum']}'),
                  trailing: IconButton(
                      tooltip: 'Eliminar evaluación',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (await confirm(context, 'Eliminar evaluación',
                            'Se eliminará esta evaluación y su calificación.')) {
                          await update({
                            ...course,
                            'assessments': assessments
                                .where((v) => v['id'] != a['id'])
                                .toList()
                          }, expected: course);
                        }
                      }))),
              OutlinedButton.icon(
                  onPressed: () => assessment(context, course),
                  icon: const Icon(Icons.add),
                  label: const Text('Añadir evaluación')),
              const Section('Temario y apuntes privados'),
              ...((course['topics'] as List? ?? []).map((v) => Json.from(v)))
                  .map((topic) =>
                      ExpansionTile(title: Text(topic['title']), children: [
                        Padding(
                            padding: const EdgeInsets.all(16),
                            child: SelectableText(topic['notes'] ?? '')),
                      ])),
              OutlinedButton.icon(
                  onPressed: () async {
                    final title = TextEditingController(),
                        notes = TextEditingController();
                    final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                                title: const Text('Nuevo tema privado'),
                                content: SingleChildScrollView(
                                    child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                      TextField(
                                          controller: title,
                                          maxLength: 160,
                                          decoration: const InputDecoration(
                                              labelText: 'Tema / subtema')),
                                      TextField(
                                          controller: notes,
                                          maxLength: 20000,
                                          maxLines: 6,
                                          decoration: const InputDecoration(
                                              labelText: 'Apuntes privados')),
                                    ])),
                                actions: [
                                  TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('Cancelar')),
                                  FilledButton(
                                      onPressed: () {
                                        if (title.text.trim().isNotEmpty) {
                                          Navigator.pop(ctx, true);
                                        }
                                      },
                                      child: const Text('Guardar'))
                                ]));
                    if (ok == true) {
                      await update({
                        ...course,
                        'topics': [
                          ...(course['topics'] as List? ?? []),
                          {
                            'id': const Uuid().v4(),
                            'title': title.text.trim(),
                            'notes': notes.text.trim()
                          }
                        ]
                      }, expected: course);
                    }
                    title.dispose();
                    notes.dispose();
                  },
                  icon: const Icon(Icons.note_add_outlined),
                  label: const Text('Añadir tema')),
              const SizedBox(height: 24),
              TextButton.icon(
                  onPressed: () async {
                    final archive = course['archived'] != true;
                    if (await confirm(
                        context,
                        archive
                            ? 'Archivar asignatura'
                            : 'Recuperar asignatura',
                        'Se conservan temas, evaluaciones y progreso.')) {
                      await update({...course, 'archived': archive},
                          expected: course);
                    }
                  },
                  icon: const Icon(Icons.archive_outlined),
                  label: Text(course['archived'] == true
                      ? 'Recuperar asignatura'
                      : 'Archivar asignatura')),
            ]));
      });
}
