import 'dart:convert';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/persistence.dart';
import 'package:lexmemoria/european_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'large private snapshot preserves unknown fields and derives its own day count',
      () async {
    final day = DateTime.now();
    final data = <String, dynamic>{
      'starterInstalled': true,
      'literalTemplateReview': 1,
      'reviewsToday': 999,
      'private': {'unicode': 'ñ𝑥', 'text': List.filled(600000, 'a').join()},
      'reviews': [
        {'id': 'r', 'occurredAt': day.toUtc().toIso8601String()}
      ]
    };
    final decoded = await compute(decodeStudyStartup, jsonEncode(data));
    expect(decoded['data'], data);
    expect(decoded['reviewsToday'], 1);
    SharedPreferences.setMockInitialValues({'lexmemoria.v1': jsonEncode(data)});
    final prefs = await SharedPreferences.getInstance();
    final store =
        await AppStore.load(persistence: PreferencesPersistence(prefs));
    expect(store.data['private'], data['private']);
    expect(store.data['reviewsToday'], 999);
    expect(store.reviewCountOn(day), 1);
    store.dispose();
  });
  test(
      'parallel object requests share work and wrong metadata cannot bypass validation',
      () async {
    final raw = utf8.encode('{"text":"correcto"}');
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
    final values = await Future.wait(
        List.generate(3, (_) => EuropeanRepository(store).object(ref)));
    expect(requests, 1);
    expect(values.every((v) => identical(v, values.first)), true);
    expect(identical(await EuropeanRepository(store).object(ref), values.first),
        true);
    await expectLater(
        EuropeanRepository(store)
            .object({...ref, 'expandedBytes': raw.length + 1}),
        throwsStateError);
    expect((await EuropeanRepository(store).object(ref))['text'], 'correcto');
    store.dispose();
  });
  test(
      'failed shared downloads can be retried instead of retaining a failed future',
      () async {
    final raw = utf8.encode('{"text":"recuperado"}');
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
      return requests == 1
          ? http.Response('unavailable', 503)
          : http.Response.bytes(bytes, 200);
    }));
    await expectLater(EuropeanRepository(store).object(ref), throwsStateError);
    expect((await EuropeanRepository(store).object(ref))['text'], 'recuperado');
    expect(requests, 2);
    store.dispose();
  });
  test(
      'shared decoded cache evicts by expanded-byte budget before retaining oversized history',
      () async {
    final payload = List.filled(40, List.filled(128 * 1024, 'x').join()).join();
    final bodies = <String, List<int>>{};
    final refs = <Json>[];
    for (var i = 0; i < 4; i++) {
      final raw = utf8.encode(jsonEncode({'text': '$i:$payload'}));
      final bytes = GZipEncoder().encode(raw);
      final hash = sha256.convert(bytes).toString();
      final path = 'objects/${hash.substring(0, 2)}/$hash.gz';
      bodies['$europeanLibraryBase$path'] = bytes;
      refs.add({
        'path': path,
        'sha256': hash,
        'bytes': bytes.length,
        'expandedBytes': raw.length,
        'encoding': 'json'
      });
    }
    final store = AppStore(await SharedPreferences.getInstance(), {},
        client: MockClient(
            (r) async => http.Response.bytes(bodies[r.url.toString()]!, 200)));
    final first = await EuropeanRepository(store).object(refs.first);
    for (final ref in refs.skip(1)) {
      await EuropeanRepository(store).object(ref);
    }
    final reopened = await EuropeanRepository(store).object(refs.first);
    expect(identical(first, reopened), false);
    expect(reopened['text'], first['text']);
    store.dispose();
  });
}
