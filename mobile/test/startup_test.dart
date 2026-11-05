import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/main.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/startup.dart';
import 'package:lexmemoria/persistence.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlite;

class BrokenSnapshot implements LocalPersistence {
  final String? snapshot;
  bool closed = false;
  BrokenSnapshot(this.snapshot);
  @override
  Future<String?> read() async => snapshot;
  @override
  Future<void> write(String snapshot) async =>
      throw StateError('must not overwrite');
  @override
  Future<void> close() async {
    closed = true;
  }
}

class QueryOnlyDatabase implements sqlite.Database {
  final bool encrypted;
  QueryOnlyDatabase({this.encrypted = true});
  @override
  Future<List<Map<String, Object?>>> rawQuery(String sql,
      [List<Object?>? arguments]) async {
    if (sql == 'PRAGMA cipher_version') {
      return encrypted
          ? [
              {'cipher_version': '4.10.0'}
            ]
          : [];
    }
    if (sql == 'PRAGMA secure_delete = ON') {
      return [
        {'secure_delete': 1}
      ];
    }
    throw UnsupportedError('Unexpected statement');
  }

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    throw StateError('Android execSQL cannot execute a PRAGMA returning rows');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected database operation');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('cipher initialization uses queries for row-returning PRAGMAs',
      () async {
    await configureEncryptedDatabase(QueryOnlyDatabase());
    await expectLater(
        configureEncryptedDatabase(QueryOnlyDatabase(encrypted: false)),
        throwsStateError);
  });
  test('invalid saved data is closed and preserved without reset', () async {
    final storage = BrokenSnapshot('damaged-json');
    await expectLater(
        AppStore.load(persistence: storage),
        throwsA(isA<StartupFailure>()
            .having((e) => e.code, 'code', 'SNAPSHOT_FORMAT')));
    expect(storage.snapshot, 'damaged-json');
    expect(storage.closed, isTrue);
  });
  testWidgets('startup failure exposes a safe code and retry can recover',
      (tester) async {
    var attempts = 0;
    final prefs = await SharedPreferences.getInstance();
    final store = AppStore(prefs, {});
    await tester.pumpWidget(AppBootstrap(storeLoader: () async {
      attempts++;
      if (attempts == 1) throw StartupFailure('SECURE_STORAGE');
      return store;
    }));
    await tester.pumpAndSettle();
    expect(find.textContaining('SECURE_STORAGE'), findsOneWidget);
    expect(find.textContaining('No desinstales'), findsOneWidget);
    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(find.textContaining('SECURE_STORAGE'), findsNothing);
    expect(tester.takeException(), isNull);
    store.dispose();
  });
  testWidgets('native exception messages are not exposed in diagnostics',
      (tester) async {
    await tester.pumpWidget(AppBootstrap(
        storeLoader: () => startupStep('SECURE_STORAGE', () async {
              throw StateError('private note or encryption key');
            })));
    await tester.pumpAndSettle();
    expect(find.textContaining('SECURE_STORAGE'), findsOneWidget);
    expect(find.textContaining('private note'), findsNothing);
    expect(find.text('Copiar diagnóstico'), findsOneWidget);
  });
}
