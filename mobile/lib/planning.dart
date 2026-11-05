import 'dart:async';
import 'package:flutter/material.dart' hide Badge;
import 'models.dart';
import 'store.dart';
import 'widgets.dart';
import 'university.dart';

class PlannerPage extends StatefulWidget {
  final AppStore store;
  const PlannerPage({super.key, required this.store});
  @override
  State<PlannerPage> createState() => _PlannerPageState();
}
class _PlannerPageState extends State<PlannerPage> {
  late double goal, hours;
  DateTime? exam;
  late List<int> rest;
  late List<Json> vacations;
  @override
  void initState() {
    super.initState(); goal = (widget.store.profile['dailyGoal'] as num? ?? 20).toDouble(); hours = (widget.store.profile['hours'] as num? ?? 1).toDouble();
    exam = DateTime.tryParse(widget.store.profile['examDate'] ?? ''); rest = List<int>.from(widget.store.profile['restDays'] ?? [7]);
    vacations = (widget.store.profile['vacations'] as List? ?? []).map((v) => Json.from(v)).toList();
  }
  @override
  Widget build(BuildContext context) {
    final days = exam?.difference(DateTime.now()).inDays;
    final forecast = weeklyForecast(widget.store.cards, Json.from(widget.store.data['states'] ?? {}), {...widget.store.profile, 'dailyGoal': goal.round(), 'restDays': rest, 'vacations': vacations}, DateTime.now());
    final load = widget.store.cards.length / ((days ?? 30) < 1 ? 1 : days ?? 30);
    return Scaffold(appBar: AppBar(title: const Text('Mi plan de estudio')), body: PageBody(children: [
      Text('Tu ritmo. Tu calendario.', style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 12),
      const Text('Un plan revisable que se adapta a tus días, sin prometer cubrirlo todo.'), const Section('Carga diaria'),
      Paper(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${goal.round()} tarjetas al día', style: Theme.of(context).textTheme.titleLarge),
        Slider(value: goal.clamp(5, 200), min: 5, max: 200, divisions: 39, label: '${goal.round()}', onChanged: (v) => setState(() => goal = v)),
        Text('${hours.toStringAsFixed(1)} horas disponibles'), Slider(value: hours.clamp(.5, 8), min: .5, max: 8, divisions: 15, label: '$hours h', onChanged: (v) => setState(() => hours = v))])),
      const Section('Días de descanso'), Wrap(spacing: 8, runSpacing: 8, children: List.generate(7, (i) => FilterChip(label: Text(['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'][i]),
        selected: rest.contains(i + 1), onSelected: (v) => setState(() { v ? rest.add(i + 1) : rest.remove(i + 1); })))),
      const Section('Vacaciones'),
      ...vacations.asMap().entries.map((e) => ListTile(title: Text('${e.value['start']} → ${e.value['end']}'),
        trailing: IconButton(tooltip: 'Quitar periodo de vacaciones', icon: const Icon(Icons.close), onPressed: () => setState(() => vacations.removeAt(e.key))))),
      OutlinedButton.icon(onPressed: () async {
        final range = await showDateRangePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)));
        if (range != null) setState(() => vacations.add({'start': civilDate(range.start), 'end': civilDate(range.end)}));
      }, icon: const Icon(Icons.beach_access_outlined), label: const Text('Añadir vacaciones')),
      const Section('Los próximos siete días'),
      Paper(child: Column(children: forecast.map((day) => ListTile(contentPadding: EdgeInsets.zero,
        leading: Icon(day['study'] ? Icons.style_outlined : Icons.free_breakfast_outlined, color: teal),
        title: Text(day['date']), subtitle: Text(day['study'] ? '${day['planned']} tarjetas previstas · ${day['backlog']} pendientes de repartir' : 'Descanso o vacaciones'))).toList())),
      const SizedBox(height: 10), const Text('Previsión de las tarjetas actuales. No anticipa futuros fallos ni nuevas tarjetas; se recalcula al cambiar el plan.', style: TextStyle(fontSize: 12)),
      const Section('Fecha de examen'), OutlinedButton.icon(onPressed: () async {
        final v = await showDatePicker(context: context, initialDate: exam != null && exam!.isAfter(DateTime.now()) ? exam : DateTime.now(), firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 3650)));
        if (v != null) { setState(() => exam = v); }
      }, icon: const Icon(Icons.event), label: Text(exam == null ? 'Añadir fecha opcional' : civilDate(exam!))),
      if (days != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text('$days días hasta el examen. Las revisiones se priorizan por vencimiento, sin estimar una nota.')),
      if (load > goal || rest.length == 7) const Padding(padding: EdgeInsets.only(top: 20), child: Paper(child: Text('La disponibilidad no permite la carga prevista. Revisa la fecha, el objetivo o los días libres.'))),
      const SizedBox(height: 24), FilledButton(onPressed: rest.length == 7 ? null : () => perform(context, () => widget.store.setProfile({'dailyGoal': goal.round(), 'hours': hours, 'examDate': exam?.toIso8601String(), 'restDays': rest, 'vacations': vacations}), success: 'Plan guardado'), child: const Text('Guardar mi plan')),
      const Section('Universidad y semestres'),
      OutlinedButton.icon(onPressed: () => push(context, UniversityPage(store: widget.store)), icon: const Icon(Icons.school_outlined), label: const Text('Asignaturas, temas y evaluaciones')),
    ]));
  }
}

class ExamPage extends StatefulWidget {
  final AppStore store;
  const ExamPage({super.key, required this.store});
  @override
  State<ExamPage> createState() => _ExamPageState();
}
class _ExamPageState extends State<ExamPage> {
  Json? attempt;
  int index = 0, minutes = 20, count = 10;
  double penalty = .25;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    if (widget.store.data['activeExam'] is Map) attempt = Json.from(widget.store.data['activeExam']);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && attempt != null && attempt!['result'] == null) {
        if (remaining <= 0) { finish(); } else { setState(() {}); }
      }
    });
  }
  @override
  void dispose() { timer?.cancel(); super.dispose(); }
  int get remaining => attempt == null ? 0 : DateTime.parse(attempt!['endsAt']).difference(DateTime.now()).inSeconds;
  Future<void> persist() async { widget.store.data['activeExam'] = attempt; await widget.store.save(); }
  Future<void> finish() async {
    if (attempt == null || attempt!['result'] != null) return;
    final questions = (attempt!['questions'] as List).map((q) => Json.from(q)).toList();
    attempt = {...attempt!, 'result': scoreExam(questions, Json.from(attempt!['answers']), (attempt!['penalty'] as num).toDouble()), 'completedAt': DateTime.now().toUtc().toIso8601String()};
    await widget.store.add('examHistory', attempt!); await persist(); if (mounted) setState(() {});
  }
  @override
  Widget build(BuildContext context) {
    final available = widget.store.cards.where((c) => c.type == 'test' && c.options.length >= 2 && c.correct != null && !c.blocked).toList();
    if (attempt == null) { return Scaffold(appBar: AppBar(title: const Text('Simulacro personal')), body: PageBody(children: [
      Text('Practica con intención.', style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 14), const Badge('Práctica personal · no es un examen oficial', warning: true),
      const SizedBox(height: 24), if (available.isEmpty) const EmptyState(icon: Icons.fact_check_outlined, title: 'Necesitas preguntas tipo test', detail: 'Crea tarjetas de tipo test con opciones, solución y explicación. No se inventan preguntas oficiales.'),
      const Section('Configura tu sesión'), DropdownButtonFormField<int>(initialValue: minutes, decoration: const InputDecoration(labelText: 'Tiempo disponible'), items: [10, 20, 30, 60].map((v) => DropdownMenuItem(value: v, child: Text('$v minutos'))).toList(), onChanged: (v) => minutes = v!),
      const SizedBox(height: 16), DropdownButtonFormField<int>(initialValue: count, decoration: const InputDecoration(labelText: 'Máximo de preguntas'), items: [5, 10, 20, 50, 100].map((v) => DropdownMenuItem(value: v, child: Text('$v preguntas'))).toList(), onChanged: (v) => count = v!),
      const SizedBox(height: 16), DropdownButtonFormField<double>(initialValue: penalty, decoration: const InputDecoration(labelText: 'Penalización por error'), items: [0.0, .25, .33, .5, 1.0].map((v) => DropdownMenuItem(value: v, child: Text('−$v puntos'))).toList(), onChanged: (v) => penalty = v!),
      const SizedBox(height: 24), FilledButton(onPressed: available.isEmpty ? null : () async {
        available.shuffle(); final now = DateTime.now().toUtc();
        attempt = {'id': now.microsecondsSinceEpoch.toString(), 'questions': available.take(count).map((c) => c.toJson()).toList(), 'answers': <String, dynamic>{},
          'penalty': penalty, 'startedAt': now.toIso8601String(), 'endsAt': now.add(Duration(minutes: minutes)).toIso8601String(), 'bankVersion': 'frozen-local-1'};
        await persist(); if (mounted) setState(() {});
      }, child: Text('Comenzar · ${available.length < count ? available.length : count} preguntas')),
    ]));
    }
    final questions = (attempt!['questions'] as List).map((q) => Json.from(q)).toList();
    final result = attempt!['result'];
    if (result != null) { return Scaffold(appBar: AppBar(title: const Text('Resultado del simulacro')), body: PageBody(children: [
      Text('${(result['score'] as num).toStringAsFixed(2)} / ${result['total']}', style: Theme.of(context).textTheme.headlineLarge), const SizedBox(height: 12),
      Text('${result['correct']} aciertos · ${result['wrong']} errores · ${result['blank']} en blanco'), const SizedBox(height: 8), const Text('Práctica personal. Esta puntuación no predice tu resultado en una convocatoria.'),
      ...questions.map((q) => Padding(padding: const EdgeInsets.only(top: 20), child: Paper(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(q['front'], style: Theme.of(context).textTheme.titleLarge), const SizedBox(height: 10),
        Text('Tu respuesta: ${(attempt!['answers'] as Map)[q['id']] == null ? 'En blanco' : q['options'][(attempt!['answers'] as Map)[q['id']]]}'),
        Text('Solución: ${q['options'][q['correct']]}'), const SizedBox(height: 10), Text(q['explanation'].toString().isEmpty ? q['back'] : q['explanation']),
        Text('${q['normId']} ${q['unitId']} · versión ${q['versionId']}', style: const TextStyle(fontSize: 12))])))),
      const SizedBox(height: 24), FilledButton(onPressed: () async { attempt = null; await persist(); if (mounted) setState(() {}); }, child: const Text('Configurar otro simulacro')),
    ]));
    }
    final q = questions[index]; final answers = Json.from(attempt!['answers']);
    return Scaffold(appBar: AppBar(title: Text('Pregunta ${index + 1} de ${questions.length}')), body: PageBody(children: [
      Text('Tiempo restante: ${remaining < 0 ? 0 : remaining ~/ 60}:${(remaining < 0 ? 0 : remaining % 60).toString().padLeft(2, '0')}', style: const TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 20),
      LinearProgressIndicator(value: (index + 1) / questions.length, color: teal), const SizedBox(height: 28), Text(q['front'], style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 24),
      ...List.generate((q['options'] as List).length, (i) => Padding(padding: const EdgeInsets.only(bottom: 12), child: OutlinedButton(
        style: OutlinedButton.styleFrom(backgroundColor: answers[q['id']] == i ? Theme.of(context).colorScheme.secondaryContainer : null, padding: const EdgeInsets.all(20), alignment: Alignment.centerLeft),
        onPressed: () async { attempt!['answers'] = {...answers, q['id']: i}; await persist(); if (mounted) setState(() {}); }, child: Text('${String.fromCharCode(65 + i)}. ${q['options'][i]}')))),
      Wrap(spacing: 8, children: [OutlinedButton(onPressed: index == 0 ? null : () => setState(() => index--), child: const Text('Anterior')),
        OutlinedButton(onPressed: index == questions.length - 1 ? null : () => setState(() => index++), child: const Text('Siguiente'))]),
      const SizedBox(height: 20), FilledButton(onPressed: () async { if (await confirm(context, 'Entregar simulacro', 'Se corregirá con las reglas y preguntas guardadas al comenzar.')) await finish(); }, child: const Text('Finalizar y corregir')),
    ]));
  }
}

class ProgressPage extends StatelessWidget {
  final AppStore store;
  const ProgressPage({super.key, required this.store});
  @override
  Widget build(BuildContext context) {
    final events = store.list('reviews');
    final correct = events.where((e) => (e['rating'] as int) >= 3).length;
    return Scaffold(appBar: AppBar(title: const Text('Mi progreso')), body: PageBody(children: [
      Text('Lo que practicas, permanece.', style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 24),
      Paper(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${events.length}', style: Theme.of(context).textTheme.headlineLarge), const Text('revisiones realizadas'),
        const SizedBox(height: 16), Text(events.isEmpty ? 'Todavía no hay datos de recuerdo.' : '${(100 * correct / events.length).round()} % de autoevaluaciones Bien o Fácil'),
        const SizedBox(height: 8), const Text('Recuerdo declarado por el usuario. No mide probabilidad de aprobar.', style: TextStyle(fontSize: 12))])),
      const Section('Por mazo'),
      ...store.cards.map((c) => c.deck).toSet().map((deck) {
        final ids = store.cards.where((c) => c.deck == deck).map((c) => c.id).toSet();
        final reviewed = events.where((e) => ids.contains(e['cardId'])).length;
        return ListTile(leading: const Icon(Icons.layers_outlined, color: teal), title: Text(deck), subtitle: Text('$reviewed revisiones · ${ids.length} tarjetas'));
      }),
      const Section('Simulacros completados'),
      ...store.list('examHistory').reversed.take(20).map((a) => ListTile(leading: const Icon(Icons.fact_check_outlined), title: Text('${a['result']['score']} / ${a['result']['total']}'), subtitle: Text(a['completedAt']))),
      const Section('Últimas revisiones'),
      if (events.isEmpty) const EmptyState(title: 'Tu historial empieza con una tarjeta', detail: 'Completa una sesión y vuelve para ver tus revisiones.'),
      ...events.reversed.take(30).map((r) => ListTile(title: Text(['Otra vez', 'Difícil', 'Bien', 'Fácil'][(r['rating'] as int) - 1]), subtitle: Text('${r['occurredAt']} · ${r['algorithm']}'))),
    ]));
  }
}
