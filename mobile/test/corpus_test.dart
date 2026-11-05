import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/prepared.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/pack_cache_io.dart';

List<Json> fixtureUnits() => List.generate(
    4,
    (i) => {
          'id': 'a${i + 1}',
          'title': 'Artículo ${i + 1}',
          'versions': [
            {
              'text':
                  'Artículo ${i + 1}\nLa ciudadanía conserva derechos fundamentales mediante garantías constitucionales específicas. Documento de estudio ${i + 1}.',
              'hash': 'hash-${i + 1}',
              'effectiveFrom': '20260101'
            },
          ],
        });
Json fixtureNorm() => {
      'id': 'BOE-A-2026-1',
      'title': 'Norma de prueba',
      'latestVersion': 'archive-v1'
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'four formats preserve source citations and have deterministic correct answers',
      () {
    final norm = fixtureNorm();
    final units = fixtureUnits();
    final seen = <String>{};
    for (final format in ['qa', 'cloze', 'test', 'reference']) {
      final cards =
          buildLiteralCards({'norm': norm, 'units': units, 'format': format});
      expect(cards.length, 4);
      expect(cards,
          buildLiteralCards({'norm': norm, 'units': units, 'format': format}));
      for (final card in cards) {
        expect(seen.add(card['id']), isTrue);
        final unit = units.firstWhere((u) => u['id'] == card['unitId']);
        expect(card['normId'], norm['id']);
        expect(card['unitVersionHash'], unit['versions'].last['hash']);
        if (format == 'test' || format == 'reference') {
          expect(card['options'][card['correct']], card['back']);
          expect((card['options'] as List).toSet().length, 4);
        }
        if (format == 'cloze') {
          expect(card['front'], contains('{{c1::${card['back']}}}'));
        }
        if (format != 'reference') {
          expect(unit['versions'].last['text'], contains(card['back']));
        }
      }
    }
    final a =
        buildLiteralCards({'norm': norm, 'units': units, 'deck': 'Tema común'});
    final b =
        buildLiteralCards({'norm': norm, 'units': units, 'deck': 'Otro tema'});
    expect(a.first['deck'], 'Tema común');
    expect(a.first['id'], isNot(b.first['id']));
  });
  test(
      'long Unicode source fragments are preserved without splitting surrogate pairs',
      () {
    final source = List.filled(150000, '𝑥').join();
    final fragments = literalChunks('Artículo 1', source);
    expect(fragments.join(), source);
    expect(fragments.every((s) => s.runes.length <= 1200), isTrue);
  });
  test(
      'reference tests omit ambiguous repeated passages and multilingual words stay whole',
      () {
    final units = fixtureUnits();
    for (final unit in units) {
      unit['versions'].last['text'] =
          'Texto idéntico repetido en todos los artículos.';
    }
    expect(
        buildLiteralCards(
            {'norm': fixtureNorm(), 'units': units, 'format': 'reference'}),
        isEmpty);
    final german = fixtureUnits();
    german.first['versions'].last['text'] =
        'Öffentlïche Körperschaften ermöglichen überörtliche Gewährleistungen.';
    final cards = buildLiteralCards({
      'norm': fixtureNorm(),
      'units': [german.first],
      'format': 'cloze'
    });
    expect(cards, hasLength(1));
    expect([
      'Öffentlïche',
      'Körperschaften',
      'ermöglichen',
      'überörtliche',
      'Gewährleistungen'
    ], contains(cards.single['back']));
  });
  test(
      'public packs verify, persist separately and reopen offline without bloating user backup',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('lexmemoria-public-test-');
    addTearDown(() => directory.delete(recursive: true));
    final norm = fixtureNorm();
    final bytes = Uint8List.fromList(GZipEncoder().encode(utf8.encode(
        jsonEncode(
            {'schemaVersion': 1, 'norm': norm, 'items': fixtureUnits()}))));
    final hash = sha256.convert(bytes).toString();
    final descriptor = {
      ...norm,
      'packHash': hash,
      'packBytes': bytes.length,
      'packUrl':
          'https://raw.githubusercontent.com/AngelJRM01/LexMemoria/legal-corpus-20261105/boe/fixture.json.gz'
    };
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      return http.Response.bytes(bytes, 200);
    });
    final prefs = await SharedPreferences.getInstance();
    final store = AppStore(prefs, {},
        client: client, packCache: FilePackCache(directory));
    store.corpusNorms = [descriptor];
    await store
        .addCard(StudyCard(id: 'mine', deck: 'D', front: 'Q', back: 'A'));
    await Future.wait(
        [store.downloadNorm(descriptor), store.downloadNorm(descriptor)]);
    expect(requests, 1);
    expect(store.list('norms').single['units'], isNull);
    expect(store.list('norms').single['packReady'], isTrue);
    final saved = jsonDecode(prefs.getString('lexmemoria.v1')!);
    final restored = AppStore(prefs, Json.from(saved),
        client: MockClient((_) async => throw StateError('offline')),
        packCache: FilePackCache(directory));
    restored.corpusNorms = [descriptor];
    await restored.downloadNorm(descriptor);
    expect(
        restored.catalogue
            .firstWhere((n) => n['id'] == descriptor['id'])['units'],
        hasLength(4));
    expect(restored.cards.single.id, 'mine');
    final damaged = Uint8List.fromList(bytes);
    damaged[damaged.length - 1] ^= 1;
    final bad = AppStore(prefs, {},
        client: MockClient((_) async => http.Response.bytes(damaged, 200)),
        packCache:
            FilePackCache(await Directory('${directory.path}/bad').create()));
    Object? error;
    try {
      await bad.downloadNorm(descriptor);
    } catch (e) {
      error = e;
    }
    expect(error, isA<StateError>());
    expect(bad.list('norms'), isEmpty);
    await expectLater(
        FilePackCache(directory).read('../private'), throwsArgumentError);
    store.dispose();
    restored.dispose();
    bad.dispose();
  });
}
