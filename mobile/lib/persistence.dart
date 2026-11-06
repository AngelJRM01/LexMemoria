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
    if (!await prefs.setString('lexmemoria.v1', snapshot)) {
      throw StateError('No se pudieron guardar los datos.');
    }
  }

  @override
  Future<void> close() async {}
}

class EncryptedPersistence implements LocalPersistence {
  final sqlite.Database database;
  EncryptedPersistence._(this.database);
  @visibleForTesting
  EncryptedPersistence.testDatabase(this.database);
  static Future<LocalPersistence> open(SharedPreferences prefs) async {
    // Web public-reader builds retain the explicit local-preferences implementation.
    if (kIsWeb) return PreferencesPersistence(prefs);
    const secure = FlutterSecureStorage();
    var password = await secure.read(key: 'lexmemoria.database.key.v1');
    final path = '${await sqlite.getDatabasesPath()}/lexmemoria.v2.db';
    if (password == null) {
      if (await sqlite.databaseExists(path)) {
        throw StateError(
            'No está disponible la clave del almacén. Los datos existentes no se han sobrescrito.');
      }
      password = '${const Uuid().v4()}${const Uuid().v4()}';
      await secure.write(key: 'lexmemoria.database.key.v1', value: password);
    }
    final db = await sqlite.openDatabase(path, password: password, version: 2,
        onCreate: (db, _) async {
      await db.execute(
          'CREATE TABLE app_state (id INTEGER PRIMARY KEY CHECK(id = 1), payload TEXT NOT NULL)');
      await createSnapshotChunks(db);
    }, onUpgrade: (db, oldVersion, newVersion) async {
      if (oldVersion < 2) await createSnapshotChunks(db);
    }, onOpen: configureEncryptedDatabase);
    return EncryptedPersistence._(db);
  }

  @override
  Future<String?> read() async {
    final chunks = await database.query('app_state_chunks',
        columns: ['payload'], orderBy: 'id');
    if (chunks.isNotEmpty) {
      return chunks.map((r) => r['payload'] as String).join();
    }
    // A legacy single row can exceed Android's CursorWindow. Read it through
    // SQLite substr(), whose offsets are Unicode code points, without ever
    // returning the whole large row to the native cursor.
    final rows = await database
        .rawQuery('SELECT length(payload) AS size FROM app_state WHERE id = 1');
    if (rows.isEmpty) return null;
    final length = (rows.single['size'] as num).toInt();
    final buffer = StringBuffer();
    for (var offset = 1; offset <= length; offset += 32768) {
      final part = await database.rawQuery(
          'SELECT substr(payload, ?, 32768) AS part FROM app_state WHERE id = 1',
          [offset]);
      buffer.write(part.single['part'] as String);
    }
    return buffer.toString();
  }

  @override
  Future<void> write(String snapshot) async {
    await database.transaction((txn) async {
      final batch = txn.batch();
      batch.delete('app_state_chunks');
      var index = 0;
      for (final chunk in snapshotChunks(snapshot)) {
        batch.insert('app_state_chunks', {'id': index++, 'payload': chunk});
      }
      // The old snapshot is removed in the same transaction only after the
      // replacement chunks are queued. Any failed write rolls all changes back.
      batch.delete('app_state');
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<void> close() => database.close();
}

Future<void> createSnapshotChunks(sqlite.Database db) => db.execute(
    'CREATE TABLE app_state_chunks (id INTEGER PRIMARY KEY, payload TEXT NOT NULL)');

Iterable<String> snapshotChunks(String text) sync* {
  if (text.isEmpty) {
    yield '';
    return;
  }
  var start = 0;
  while (start < text.length) {
    var end = (start + 32768).clamp(0, text.length);
    if (end < text.length) {
      final previous = text.codeUnitAt(end - 1), next = text.codeUnitAt(end);
      if (previous >= 0xd800 &&
          previous <= 0xdbff &&
          next >= 0xdc00 &&
          next <= 0xdfff) {
        end--;
      }
    }
    yield text.substring(start, end);
    start = end;
  }
}

/// Android execSQL rejects PRAGMAs that return rows. Keep both initialization
/// checks on the query API and fail closed if encryption is unavailable.
Future<void> configureEncryptedDatabase(sqlite.Database db) async {
  final cipher = await db.rawQuery('PRAGMA cipher_version');
  if (cipher.isEmpty) {
    throw StateError(
        'SQLCipher no está disponible; no se usará almacenamiento sin cifrar.');
  }
  final secureDelete = await db.rawQuery('PRAGMA secure_delete = ON');
  if (secureDelete.isEmpty || secureDelete.first.values.first != 1) {
    throw StateError('No se ha podido activar el borrado seguro.');
  }
}
