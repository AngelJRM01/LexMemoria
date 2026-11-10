import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/shell.dart';
import 'package:lexmemoria/planning.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('day counts follow reviews, undo, raw saves and day changes', () async {
    final day = DateTime.now();
    final yesterday = DateTime(day.year, day.month, day.day - 1);
    final store = AppStore(await SharedPreferences.getInstance(), {
      'reviews': [
        {
          'id': 'old',
          'cardId': 'c',
          'rating': 3,
          'occurredAt': yesterday.toUtc().toIso8601String()
        },
        {
          'id': 'today',
          'cardId': 'c',
          'rating': 3,
          'occurredAt': day.toUtc().toIso8601String()
        }
      ]
    });
    await store.addCard(StudyCard(id: 'c', deck: 'D', front: 'Q', back: 'A'));
    expect(store.reviewCountOn(day), 1);
    expect(store.reviewCountOn(yesterday), 1);
    await store.review(store.cards.single, 3);
    expect(store.reviewCountOn(day), 2);
    await store.undoLast();
    expect(store.reviewCountOn(day), 1);
    store.data['reviews'][1]['occurredAt'] =
        yesterday.toUtc().toIso8601String();
    await store.save();
    expect(store.reviewCountOn(day), 0);
    expect(store.reviewCountOn(yesterday), 2);
    store.dispose();
  });
  test('card ID index refreshes after editing and clearing the collection',
      () async {
    final store = AppStore(await SharedPreferences.getInstance(), {});
    await store
        .addCard(StudyCard(id: 'c', deck: 'D', front: 'Original', back: 'A'));
    expect(store.cardById('c')!.front, 'Original');
    await store.editCard(
        StudyCard(
            id: 'c', deck: 'Other', front: 'Changed', back: 'A', revision: 2),
        expectedRevision: 1);
    expect(store.cardById('c')!.front, 'Changed');
    expect(store.cardById('missing'), isNull);
    await store.reset();
    expect(store.cardById('c'), isNull);
    store.dispose();
  });
  testWidgets('measure real home and progress builds with a large history',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final stamp = DateTime.now().toUtc().toIso8601String();
    final store = AppStore(await SharedPreferences.getInstance(), {
      'cards': List.generate(
          20000,
          (i) =>
              StudyCard(id: 'c$i', deck: 'D${i % 200}', front: 'Q', back: 'A')
                  .toJson()),
      'reviews': List.generate(
          100000,
          (i) => <String, dynamic>{
                'id': 'r$i',
                'cardId': 'c${i % 20000}',
                'rating': 3,
                'occurredAt': stamp
              })
    });
    store.cards;
    final report = <String, dynamic>{
      'cards': 20000,
      'reviews': 100000,
      'decks': 200,
      'environment': 'Flutter host, not a phone benchmark'
    };
    for (final type in ['home', 'progress']) {
      final samples = <int>[];
      for (var i = 0; i < 4; i++) {
        await tester.pumpWidget(const SizedBox.shrink());
        final watch = Stopwatch()..start();
        await tester.pumpWidget(MaterialApp(
            home: type == 'home'
                ? Scaffold(body: HomePage(store: store, navigate: (_) {}))
                : ProgressPage(store: store)));
        samples.add(watch.elapsedMicroseconds);
        expect(tester.takeException(), isNull);
        if (type == 'progress') expect(find.text('100000'), findsOneWidget);
      }
      final warm = samples.skip(1).toList()..sort();
      report[type] = {
        'coldMicroseconds': samples.first,
        'warmMedianMicroseconds': warm[1]
      };
    }
    final output = Platform.environment['LEXMEMORIA_HISTORY_REPORT'];
    if (output != null) {
      File(output).writeAsStringSync('${jsonEncode(report)}\n');
    }
    stdout.writeln(jsonEncode(report));
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
