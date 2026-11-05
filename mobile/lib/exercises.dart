import 'package:flutter/material.dart';
import 'models.dart';

/// Active responses stay separate from the learner's recall rating.
class ExerciseInput extends StatefulWidget {
  final StudyCard card;
  final bool revealed;
  final ValueChanged<dynamic> onChanged;
  const ExerciseInput(
      {super.key,
      required this.card,
      required this.revealed,
      required this.onChanged});
  @override
  State<ExerciseInput> createState() => _ExerciseInputState();
}

class _ExerciseInputState extends State<ExerciseInput> {
  int? selected;
  late List<int> order;
  @override
  void initState() {
    super.initState();
    order = List.generate(widget.card.options.length, (i) => i)..shuffle();
    // A shuffled order must still offer actual work.
    if (order.length > 1 &&
        order.asMap().entries.every((e) => e.key == e.value)) {
      order = [...order.skip(1), order.first];
    }
    if (widget.card.type == 'order') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onChanged(List<int>.from(order));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.card;
    if (c.type == 'order') {
      final correct = order.asMap().entries.every((e) => e.key == e.value);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Ordena los elementos con las flechas.'),
        ...order.asMap().entries.map((entry) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('${entry.key + 1}. ${c.options[entry.value]}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    tooltip: 'Subir elemento ${entry.key + 1}',
                    icon: const Icon(Icons.arrow_upward),
                    onPressed: widget.revealed || entry.key == 0
                        ? null
                        : () => move(entry.key, -1)),
                IconButton(
                    tooltip: 'Bajar elemento ${entry.key + 1}',
                    icon: const Icon(Icons.arrow_downward),
                    onPressed: widget.revealed || entry.key == order.length - 1
                        ? null
                        : () => move(entry.key, 1)),
              ]),
            )),
        if (widget.revealed)
          Text(correct ? 'Orden correcto.' : 'Revisa el orden correcto:',
              style: const TextStyle(fontWeight: FontWeight.bold)),
        if (widget.revealed && !correct)
          ...c.options
              .asMap()
              .entries
              .map((e) => Text('${e.key + 1}. ${e.value}')),
      ]);
    }
    if (c.options.isEmpty || c.correct == null) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...c.options.asMap().entries.map((e) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
                alignment: Alignment.centerLeft,
                backgroundColor: selected == e.key
                    ? Theme.of(context).colorScheme.secondaryContainer
                    : null),
            onPressed: widget.revealed
                ? null
                : () {
                    setState(() => selected = e.key);
                    widget.onChanged(e.key);
                  },
            child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text('${String.fromCharCode(65 + e.key)}. ${e.value}')),
          ))),
      if (widget.revealed)
        Text(selected == null
            ? 'Sin respuesta. Solución: ${c.options[c.correct!]}'
            : selected == c.correct
                ? 'Respuesta correcta.'
                : 'Respuesta incorrecta. Solución: ${c.options[c.correct!]}'),
    ]);
  }

  void move(int index, int delta) {
    setState(() {
      final item = order.removeAt(index);
      order.insert(index + delta, item);
    });
    widget.onChanged(List<int>.from(order));
  }
}
