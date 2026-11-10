import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/shell.dart';
import 'package:lexmemoria/persistence.dart';
import 'package:lexmemoria/european_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('measure saved-state load and first Home separately',
      (tester) async {
    final stamp = DateTime.now().toUtc().toIso8601String();
    final snapshot = jsonEncode({
      'starterInstalled': true,
      'literalTemplateReview': 1,
      'onboarded': true,
      'cards': List.generate(
          20000,
          (i) =>
              StudyCard(id: 'c$i', deck: 'D', front: 'Q', back: 'A').toJson()),
      'reviews': List.generate(
          100000,
          (i) => {
                'id': 'r$i',
                'cardId': 'c${i % 20000}',
                'rating': 3,
                'occurredAt': stamp
              })
    });
    SharedPreferences.setMockInitialValues({'lexmemoria.v1': snapshot});
    final prefs = await SharedPreferences.getInstance();
    late AppStore store;
    late int loadMicros;
    var maxGap = 0;
    await tester.runAsync(() async {
      final clock = Stopwatch()..start();
      var previous = clock.elapsedMicroseconds;
      final timer = Timer.periodic(const Duration(milliseconds: 5), (_) {
        final now = clock.elapsedMicroseconds;
        if (now - previous > maxGap) maxGap = now - previous;
        previous = now;
      });
      store = await AppStore.load(persistence: PreferencesPersistence(prefs));
      loadMicros = clock.elapsedMicroseconds;
      // Let the real event loop observe any final synchronous stall.
      await Future<void>.delayed(const Duration(milliseconds: 10));
      timer.cancel();
    });
    final watch = Stopwatch()..start();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: HomePage(store: store, navigate: (_) {}))));
    final homeMicros = watch.elapsedMicroseconds;
    expect(find.text('100000 de 20 repasos de tu objetivo'), findsOneWidget);
    final report = {
      'cards': 20000,
      'reviews': 100000,
      'loadMicroseconds': loadMicros,
      'firstHomeMicroseconds': homeMicros,
      'readyTotalMicroseconds': loadMicros + homeMicros,
      'loadHeartbeatMaxGapMicroseconds': maxGap,
      'environment':
          'Flutter host with preference fixture; not Android SQLCipher or phone latency'
    };
    final output = Platform.environment['LEXMEMORIA_STARTUP_REPORT'];
    if (output != null) {
      File(output).writeAsStringSync('${jsonEncode(report)}\n');
    }
    stdout.writeln(jsonEncode(report));
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
  test('measure simultaneous and repeated European object opens', () async {
    SharedPreferences.setMockInitialValues({});
    final raw = utf8.encode(jsonEncode({
      'items': List.generate(
          10000,
          (i) => {
                'id': 'row$i',
                'text': '${List.filled(16, 'Referencia jurídica ').join()}$i'
              })
    }));
    final bytes = GZipEncoder().encode(raw);
    final hash = sha256.convert(bytes).toString();
    final ref = <String, dynamic>{
      'path': 'objects/${hash.substring(0, 2)}/$hash.gz',
      'sha256': hash,
      'bytes': bytes.length,
      'expandedBytes': raw.length,
      'encoding': 'json'
    };
    var requests = 0;
    final store = AppStore(await SharedPreferences.getInstance(), {},
        client: MockClient((_) async {
      requests++;
      await Future<void>.delayed(const Duration(milliseconds: 5));
      return http.Response.bytes(bytes, 200);
    }));
    final clock = Stopwatch()..start();
    final values = await Future.wait(
        List.generate(3, (_) => EuropeanRepository(store).object(ref)));
    final concurrent = clock.elapsedMicroseconds;
    clock.reset();
    final reopened = await EuropeanRepository(store).object(ref);
    final reopening = clock.elapsedMicroseconds;
    expect(reopened['items'].length, 10000);
    expect(values.every((v) => v['items'].length == 10000), true);
    final report = {
      'objects': 3,
      'expandedBytes': raw.length,
      'httpRequests': requests,
      'simultaneousMicroseconds': concurrent,
      'newRepositoryReopenMicroseconds': reopening,
      'sameDecodedObjectOnReopen': identical(values.first, reopened),
      'contentSha256':
          sha256.convert(utf8.encode(jsonEncode(reopened))).toString(),
      'environment': 'Flutter host with delayed HTTP fixture'
    };
    final output = Platform.environment['LEXMEMORIA_READER_REPORT'];
    if (output != null) {
      File(output).writeAsStringSync('${jsonEncode(report)}\n');
    }
    stdout.writeln(jsonEncode(report));
    store.dispose();
  });
}
