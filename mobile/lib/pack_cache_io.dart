import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'pack_cache.dart';

class FilePackCache implements PackCache {
  final Directory directory;
  FilePackCache(this.directory);
  @override
  bool get persistent => true;
  File file(String hash) {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw ArgumentError('Hash de paquete no válido');
    }
    return File('${directory.path}/$hash.gz');
  }

  @override
  Future<Uint8List?> read(String hash) async {
    final path = file(hash);
    return await path.exists() ? path.readAsBytes() : null;
  }

  @override
  Future<void> write(String hash, Uint8List bytes) async {
    await directory.create(recursive: true);
    final target = file(hash);
    final temporary = File('${target.path}.${const Uuid().v4()}.tmp');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(target.path);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }
}

Future<PackCache> openCache() async => FilePackCache(Directory(
    '${(await getApplicationSupportDirectory()).path}/public-corpus-v1'));
