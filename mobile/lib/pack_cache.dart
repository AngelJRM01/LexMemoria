import 'dart:typed_data';
import 'pack_cache_stub.dart' if (dart.library.io) 'pack_cache_io.dart'
    as platform;

abstract interface class PackCache {
  bool get persistent;
  Future<Uint8List?> read(String hash);
  Future<void> write(String hash, Uint8List bytes);
}

class MemoryPackCache implements PackCache {
  final entries = <String, Uint8List>{};
  @override
  bool get persistent => false;
  @override
  Future<Uint8List?> read(String hash) async => entries[hash];
  @override
  Future<void> write(String hash, Uint8List bytes) async {
    entries[hash] = Uint8List.fromList(bytes);
  }
}

Future<PackCache> openPackCache() => platform.openCache();
