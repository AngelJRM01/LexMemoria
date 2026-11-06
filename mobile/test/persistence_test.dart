import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/persistence.dart';

class MemoryPersistence implements LocalPersistence {
  String? snapshot;
  bool fail = false;
  @override
  Future<String?> read() async => snapshot;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('Disk unavailable');
    snapshot = value;
  }

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(
      {'lexmemoria.v1': '{"profile":{"mode":"Universidad"}}'}));
  test(
      'multi-megabyte snapshots retain Unicode at native cursor-safe chunk boundaries',
      () {
    final text =
        '${List.filled(32767, 'a').join()}𝑥${List.filled(3 * 1024 * 1024, 'ñ').join()}';
    expect(snapshotChunks('').toList(), ['']);
    final chunks = snapshotChunks(text).toList();
    expect(chunks.length, greaterThan(90));
    expect(chunks.join(), text);
    for (final chunk in chunks) {
      expect(chunk.length, lessThanOrEqualTo(32768));
      expect(chunk.runes.contains(0xfffd), isFalse);
    }
  });
  test('legacy data is removed only after verified destination write',
      () async {
    final storage = MemoryPersistence();
    final store = await AppStore.load(persistence: storage);
    expect(store.mode, 'Universidad');
    expect((await SharedPreferences.getInstance()).getString('lexmemoria.v1'),
        isNull);
    expect(storage.snapshot, isNotNull);
    await store.setProfile({'mode': 'Ambos'});
    final loaded = await AppStore.load(persistence: storage);
    expect(loaded.mode, 'Ambos');
  });
  test('failed migration retains the original copy', () async {
    final storage = MemoryPersistence()..fail = true;
    await expectLater(AppStore.load(persistence: storage), throwsStateError);
    expect((await SharedPreferences.getInstance()).getString('lexmemoria.v1'),
        isNotNull);
  });
}
