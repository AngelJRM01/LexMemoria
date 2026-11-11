import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lexmemoria/main.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/persistence.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlite;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('large legacy encrypted row migrates and failed writes roll back',
      (tester) async {
    final path =
        '${await sqlite.getDatabasesPath()}/lexmemoria-integration-${DateTime.now().microsecondsSinceEpoch}.db';
    const testKey = 'temporary-integration-key-not-a-production-secret';
    final original =
        '{"probe":"${List.filled(96, List.filled(32768, 'ñ').join()).join()}𝑥"}';
    sqlite.Database? db;
    try {
      db = await sqlite.openDatabase(path, password: testKey, version: 1,
          onCreate: (db, _) async {
        await db.execute(
            'CREATE TABLE app_state (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)');
      });
      await db.insert('app_state', {'id': 1, 'payload': original});
      await db.close();
      db = await sqlite.openDatabase(path,
          password: testKey,
          version: 2,
          onUpgrade: (db, _, __) => createSnapshotChunks(db),
          onOpen: configureEncryptedDatabase);
      final storage = EncryptedPersistence.testDatabase(db);
      expect(await storage.read(), original);
      final updated = '$original ';
      await storage.write(updated);
      expect(await storage.read(), updated);
      expect(
          (await db.rawQuery('SELECT count(*) AS n FROM app_state'))
              .single['n'],
          0);
      final beforeChanges =
          (await db.rawQuery('SELECT total_changes() AS n')).single['n'] as int;
      await storage.write(updated);
      final afterChanges =
          (await db.rawQuery('SELECT total_changes() AS n')).single['n'] as int;
      expect(afterChanges - beforeChanges, 0,
          reason: 'Unchanged encrypted chunks must not be rewritten');
      final changedTail = '$updated!';
      await storage.write(changedTail);
      final tailChanges =
          (await db.rawQuery('SELECT total_changes() AS n')).single['n'] as int;
      expect(tailChanges - afterChanges, 1,
          reason: 'Only the final changed chunk should be updated');
      await storage.write(updated);
      await db.execute(
          "CREATE TEMP TRIGGER fail_snapshot BEFORE INSERT ON app_state_chunks WHEN NEW.id=1 BEGIN SELECT RAISE(ABORT, 'integration simulated failure'); END");
      await expectLater(storage.write(original), throwsException);
      expect(await storage.read(), updated);
      await db.execute('DROP TRIGGER fail_snapshot');
      await storage.write('𝑥');
      expect(await storage.read(), '𝑥');
      expect(
          (await db.rawQuery('SELECT count(*) AS n FROM app_state_chunks'))
              .single['n'],
          1);
    } finally {
      if (db?.isOpen == true) await db!.close();
      await sqlite.deleteDatabase(path);
    }
  });
  testWidgets('native encrypted store opens and retains data after reopening',
      (tester) async {
    // Use the actual Android/iOS plugins. Do not replace SQLCipher or Keystore
    // with preference mocks: those mocks cannot expose native startup failures.
    final first = await AppStore.load();
    final existed = first.data.containsKey('startupIntegrationProbe');
    final before = first.data['startupIntegrationProbe'];
    final largeProbe =
        'native-reopen-probe:${List.filled(96, List.filled(32768, 'a').join()).join()}𝑥';
    first.data['startupIntegrationProbe'] = largeProbe;
    await first.save();
    await first.persistence.close();
    final reopened = await AppStore.load();
    try {
      expect(reopened.data['startupIntegrationProbe'], largeProbe);
      expect(reopened.bundledNorms.where((n) => n['source'] == 'BOE'),
          hasLength(20));
      expect(
          reopened.bundledNorms.where((n) => n['celex'] != null), hasLength(3));
      await tester.pumpWidget(LexMemoria(store: reopened));
      await tester.pumpAndSettle();
      expect(find.textContaining('No se ha podido iniciar'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      if (existed) {
        reopened.data['startupIntegrationProbe'] = before;
      } else {
        reopened.data.remove('startupIntegrationProbe');
      }
      await reopened.save();
      await reopened.persistence.close();
    }
  });
}
