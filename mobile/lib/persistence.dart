import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart' as sqlite;
import 'package:uuid/uuid.dart';

abstract interface class LocalPersistence {
  Future<String?> read();
  Future<void> write(String snapshot);
  Future<void> close();
}

class PreferencesPersistence implements LocalPersistence {
  final SharedPreferences prefs;
  PreferencesPersistence(this.prefs);
  @override
  Future<String?> read() async => prefs.getString('lexmemoria.v1');
  @override
  Future<void> write(String snapshot) async {
    if (!await prefs.setString('lexmemoria.v1', snapshot)) throw StateError('No se pudieron guardar los datos.');
  }
  @override
  Future<void> close() async {}
}

class EncryptedPersistence implements LocalPersistence {
  final sqlite.Database database;
  EncryptedPersistence._(this.database);
  static Future<LocalPersistence> open(SharedPreferences prefs) async {
    // Web public-reader builds retain the explicit local-preferences implementation.
    if (kIsWeb) return PreferencesPersistence(prefs);
    const secure = FlutterSecureStorage();
    var password = await secure.read(key: 'lexmemoria.database.key.v1');
    final path = '${await sqlite.getDatabasesPath()}/lexmemoria.v2.db';
    if (password == null) {
      if (await sqlite.databaseExists(path)) {
        throw StateError('No está disponible la clave del almacén. Los datos existentes no se han sobrescrito.');
      }
      password = '${const Uuid().v4()}${const Uuid().v4()}';
      await secure.write(key: 'lexmemoria.database.key.v1', value: password);
    }
    final db = await sqlite.openDatabase(path, password: password, version: 1,
      onCreate: (db, _) async {
        await db.execute('CREATE TABLE app_state (id INTEGER PRIMARY KEY CHECK(id = 1), payload TEXT NOT NULL)');
      },
      onOpen: configureEncryptedDatabase);
    return EncryptedPersistence._(db);
  }
  @override
  Future<String?> read() async {
    final rows = await database.query('app_state', columns: ['payload'], where: 'id = ?', whereArgs: [1]);
    return rows.isEmpty ? null : rows.single['payload'] as String;
  }
  @override
  Future<void> write(String snapshot) async {
    await database.transaction((txn) async {
      await txn.insert('app_state', {'id': 1, 'payload': snapshot}, conflictAlgorithm: sqlite.ConflictAlgorithm.replace);
    });
  }
  @override
  Future<void> close() => database.close();
}

/// Android execSQL rejects PRAGMAs that return rows. Keep both initialization
/// checks on the query API and fail closed if encryption is unavailable.
Future<void> configureEncryptedDatabase(sqlite.Database db) async {
  final cipher = await db.rawQuery('PRAGMA cipher_version');
  if (cipher.isEmpty) {
    throw StateError('SQLCipher no está disponible; no se usará almacenamiento sin cifrar.');
  }
  final secureDelete = await db.rawQuery('PRAGMA secure_delete = ON');
  if (secureDelete.isEmpty || secureDelete.first.values.first != 1) {
    throw StateError('No se ha podido activar el borrado seguro.');
  }
}
