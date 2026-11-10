import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('measure all deck queues with 20000 cards and 200 decks', () async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore(await SharedPreferences.getInstance(), {
      'cards': List.generate(
          20000,
          (i) => StudyCard(
                  id: 'card-${i.toString().padLeft(6, '0')}',
                  deck: 'D${i % 200}',
                  front: 'Q',
                  back: 'A')
              .toJson())
    });
    store.cards;
    final timings = <int>[];
    final result = <List<String>>[];
    for (var pass = 0; pass < 4; pass++) {
      final watch = Stopwatch()..start();
      final queues = List.generate(
          200,
          (i) => store.due(
              deck: 'D$i', at: DateTime.utc(2026, 11, 10), includeRest: true));
      timings.add(watch.elapsedMicroseconds);
      for (var i = 0; i < queues.length; i++) {
        expect(queues[i].length, 20);
        expect(queues[i].every((c) => c.deck == 'D$i'), true);
      }
      if (pass == 3) {
        result.addAll(queues.map((q) => q.map((c) => c.id).toList()));
      }
    }
    final warm = timings.skip(1).toList()..sort();
    final report = {
      'cards': 20000,
      'decks': 200,
      'coldMicroseconds': timings.first,
      'warmMedianMicroseconds': warm[1],
      'resultSha256':
          sha256.convert(utf8.encode(jsonEncode(result))).toString(),
      'environment': 'Flutter host, not a phone benchmark'
    };
    final output = Platform.environment['LEXMEMORIA_DECK_REPORT'];
    if (output != null) {
      File(output).writeAsStringSync('${jsonEncode(report)}\n');
    }
    stdout.writeln(jsonEncode(report));
    store.dispose();
  });
}
