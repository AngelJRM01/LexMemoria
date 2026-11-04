import 'package:flutter_test/flutter_test.dart';
import 'package:lexmemoria/models.dart';

void main() {
  test('SM-2 intervals and lapse preserve versioned history inputs', () {
    final at = DateTime.utc(2026, 1, 1);
    final a = schedule({}, 3, at);
    expect(a['interval'], 1);
    final b = schedule(a, 3, at);
    expect(b['interval'], 6);
    final failed = schedule(b, 1, at);
    expect(failed['repetitions'], 0);
    expect(failed['lapses'], 1);
    expect(failed['algorithm'], 'sm2-1');
    expect(DateTime.parse(failed['dueAt']).difference(at).inMinutes, 10);
    expect(b['repetitions'], 2);
    expect(() => schedule({}, 9, at), throwsArgumentError);
  });
  test('score distinguishes unanswered, wrong and correct', () {
    final score = scoreExam([{'id': 'a', 'correct': 0}, {'id': 'b', 'correct': 1}, {'id': 'c', 'correct': 0}], {'a': 0, 'b': 0}, .25);
    expect(score, {'correct': 1, 'wrong': 1, 'blank': 1, 'score': .75, 'total': 3});
  });
  test('reference inventory never claims downloaded or verified', () {
    final catalogue = initialCatalogue();
    expect(catalogue.length, 20);
    expect(catalogue.map((n) => n['id']).toSet().length, 20);
    for (final norm in catalogue) {
      expect(norm['coverage'], 'identified');
      expect(norm['reviewState'], 'pending');
      expect(norm['units'], isNull);
    }
  });
  test('search normalizes accents without changing source', () {
    expect(normalize('Constitución ÁÉÍÓÚ'), 'constitucion aeiou');
  });
}
