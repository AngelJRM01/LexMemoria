export 'european_policy.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'models.dart';
import 'store.dart';

const europeanLibraryBase =
    'https://raw.githubusercontent.com/AngelJRM01/LexMemoria/european-corpus-20261109/';

List<Json> decodeEuropeanIndex(Json input) {
  final raw = GZipDecoder().decodeBytes(input['bytes'] as Uint8List);
  if (raw.length != input['expandedBytes']) {
    throw StateError('Catálogo incompleto.');
  }
  if (raw.length > 256000000) throw StateError('Catálogo demasiado grande.');
  final value = Json.from(jsonDecode(utf8.decode(raw)));
  if (value['schemaVersion'] != 1) throw StateError('Catálogo incompatible.');
  final rows = (value['items'] as List).map((v) => Json.from(v)).toList();
  if (rows.map((n) => n['id']).toSet().length != rows.length) {
    throw StateError('El catálogo contiene identificadores repetidos.');
  }
  for (final row in rows) {
    if (row['celex'] is! String ||
        row['id'] != 'EU-${row['celex']}' ||
        row['title'] is! String) {
      throw StateError('Identificador europeo incompatible.');
    }
    row['_search'] = normalize('${row['title']} ${row['celex']} '
        '${row['celex'] == '32016R0679' ? 'RGPD protección de datos' : ''}');
  }
  return rows;
}

dynamic decodeEuropeanObject(Json input) {
  final raw = GZipDecoder().decodeBytes(input['bytes'] as Uint8List);
  if (raw.length != input['expandedBytes']) {
    throw StateError('Archivo incompleto.');
  }
  if (input['encoding'] == 'jsonl') {
    if (raw.length > 5000000) throw StateError('Página demasiado grande.');
    return const LineSplitter()
        .convert(utf8.decode(raw))
        .where((line) => line.isNotEmpty)
        .map((line) => Json.from(jsonDecode(line)))
        .toList();
  }
  return Json.from(jsonDecode(utf8.decode(raw)));
}

class _EuropeanObjects {
  final decoded = <String, dynamic>{};
  final weights = <String, int>{};
  final loading = <String, Future<dynamic>>{};
  final compressed = <String, Future<Uint8List>>{};
  int expandedBytes = 0;
  void keep(String key, dynamic value, int weight) {
    if (weight > 16 * 1024 * 1024) return;
    if (decoded.containsKey(key)) {
      decoded.remove(key);
      expandedBytes -= weights.remove(key)!;
    }
    decoded[key] = value;
    weights[key] = weight;
    expandedBytes += weight;
    while (decoded.length > 4 || expandedBytes > 16 * 1024 * 1024) {
      final first = decoded.keys.first;
      decoded.remove(first);
      expandedBytes -= weights.remove(first)!;
    }
  }
}

class EuropeanRepository {
  final AppStore store;
  EuropeanRepository(this.store);
  static const manifestKey = 'lexmemoria.public.european.manifest.v1';
  static final _objects = Expando<_EuropeanObjects>();
  _EuropeanObjects get _memo => _objects[store] ??= _EuropeanObjects();
  String _refKey(Json ref) => jsonEncode([
        ref['path'],
        ref['sha256'],
        ref['bytes'],
        ref['expandedBytes'],
        ref['encoding']
      ]);

  Uri objectUri(Json ref) {
    if (!RegExp(r'^objects/[a-f0-9]{2}/[a-f0-9]{64}\.gz$')
            .hasMatch(ref['path']?.toString() ?? '') ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(ref['sha256']?.toString() ?? '') ||
        ref['bytes'] is! num ||
        (ref['bytes'] as num) <= 0 ||
        (ref['bytes'] as num) > 64000000 ||
        ref['expandedBytes'] is! num ||
        ((ref['expandedBytes'] as num) <= 0 ||
            (ref['expandedBytes'] as num) > 256000000)) {
      throw StateError('Referencia de biblioteca no válida.');
    }
    return Uri.parse('$europeanLibraryBase${ref['path']}');
  }

  Future<Uint8List> _request(Uri uri, int limit) async {
    final request = await store.client
        .send(http.Request('GET', uri))
        .timeout(const Duration(seconds: 30));
    if (request.statusCode != 200) {
      throw StateError(
          'No se pudo descargar el contenido (${request.statusCode}).');
    }
    final bytes = BytesBuilder(copy: false);
    var size = 0;
    final elapsed = Stopwatch()..start();
    await for (final chunk
        in request.stream.timeout(const Duration(seconds: 30))) {
      size += chunk.length;
      if (size > limit || elapsed.elapsed > const Duration(minutes: 2)) {
        throw StateError('La descarga supera el límite previsto.');
      }
      bytes.add(chunk);
    }
    return bytes.takeBytes();
  }

  Future<Json> manifest({bool refresh = false}) async {
    final saved = store.prefs.getString(manifestKey);
    Json? cached;
    try {
      if (saved != null) cached = Json.from(jsonDecode(saved));
      if (cached != null) _validateManifest(cached);
    } catch (_) {
      cached = null;
    }
    if (!refresh && cached != null) return cached;
    try {
      final value = Json.from(jsonDecode(utf8.decode(await _request(
          Uri.parse('${europeanLibraryBase}catalogue-manifest.json'),
          512000))));
      _validateManifest(value);
      await store.prefs.setString(manifestKey, jsonEncode(value));
      return value;
    } catch (_) {
      if (cached != null) return cached;
      rethrow;
    }
  }

  void _validateManifest(Json value) {
    if (value['schemaVersion'] != 1 ||
        value['baseUrl'] != europeanLibraryBase ||
        value['norms'] is! num ||
        (value['norms'] as num) <= 0) {
      throw StateError('Catálogo europeo no válido.');
    }
    objectUri(Json.from(value['index']));
  }

  Future<Uint8List> compressed(Json ref) async {
    final request = Json.from(ref);
    objectUri(request);
    final key = _refKey(request);
    final memo = _memo;
    return memo.compressed[key] ??= _loadCompressed(request, key, memo);
  }

  Future<Uint8List> _loadCompressed(
      Json ref, String key, _EuropeanObjects memo) async {
    try {
      final uri = objectUri(ref);
      final hash = ref['sha256'] as String;
      var bytes = await store.packCache.read(hash);
      if (bytes != null &&
          bytes.length == ref['bytes'] &&
          sha256.convert(bytes).toString() == hash) {
        return bytes;
      }
      bytes = await _request(uri, (ref['bytes'] as num).toInt());
      if (bytes.length != ref['bytes'] ||
          sha256.convert(bytes).toString() != hash) {
        throw StateError(
            'El contenido no supera la comprobación de integridad.');
      }
      await store.packCache.write(hash, bytes);
      return bytes;
    } finally {
      memo.compressed.remove(key);
    }
  }

  static final _catalogues = Expando<_EuropeanCatalogueMemo>();

  Future<List<Json>> catalogue({bool refresh = false}) async {
    final header = await manifest(refresh: refresh);
    final index = Json.from(header['index']);
    var memo = _catalogues[store];
    if (memo == null || memo.hash != index['sha256']) {
      memo = _EuropeanCatalogueMemo(index['sha256'], _decodeCatalogue(index));
      _catalogues[store] = memo;
    }
    try {
      final rows = await memo.value;
      if (rows.length != header['norms']) {
        throw StateError('Catálogo incompleto.');
      }
      return rows;
    } catch (_) {
      if (identical(_catalogues[store], memo)) _catalogues[store] = null;
      rethrow;
    }
  }

  Future<List<Json>> _decodeCatalogue(Json index) async =>
      compute(decodeEuropeanIndex, <String, dynamic>{
        'bytes': await compressed(index),
        'expandedBytes': index['expandedBytes']
      });

  Future<dynamic> object(Json ref) async {
    final request = Json.from(ref);
    objectUri(request);
    final key = _refKey(request);
    final memo = _memo;
    if (memo.decoded.containsKey(key)) {
      final value = memo.decoded.remove(key);
      memo.decoded[key] = value;
      return value;
    }
    return memo.loading[key] ??= _loadObject(request, key, memo);
  }

  Future<dynamic> _loadObject(
      Json ref, String key, _EuropeanObjects memo) async {
    try {
      final input = <String, dynamic>{
        'bytes': await compressed(ref),
        'expandedBytes': ref['expandedBytes'],
        'encoding': ref['encoding']
      };
      final result = (ref['expandedBytes'] as num) > 128 * 1024
          ? await compute(decodeEuropeanObject, input)
          : decodeEuropeanObject(input);
      memo.keep(key, result, (ref['expandedBytes'] as num).toInt());
      return result;
    } finally {
      memo.loading.remove(key);
    }
  }

  Future<List<Json>> unitParagraphs(Json document, Json unit,
      {int offset = 0, int limit = 30}) async {
    final first = (unit['firstParagraph'] as num).toInt() + offset;
    final count = (unit['paragraphCount'] as num).toInt();
    final end = ((unit['firstParagraph'] as num).toInt() + count)
        .clamp(first, first + limit);
    final result = <Json>[];
    for (final value in document['pages'] as List) {
      final page = Json.from(value);
      final start = (page['firstParagraph'] as num).toInt();
      final stop = start + (page['paragraphs'] as num).toInt();
      if (stop <= first || start >= end) continue;
      final records = (await object(page) as List).cast<Json>();
      for (var i = 0; i < records.length; i++) {
        final position = start + i;
        if (position >= first && position < end) {
          if (records[i]['unitId'] != unit['id']) {
            throw StateError('Índice de artículo incoherente.');
          }
          result.add(Json.from(records[i]['paragraph']));
        }
      }
    }
    if (result.length != end - first) {
      throw StateError('Faltan fragmentos del artículo.');
    }
    return result;
  }
}

class _EuropeanCatalogueMemo {
  final String hash;
  final Future<List<Json>> value;
  _EuropeanCatalogueMemo(this.hash, this.value);
}

/// Reuse a filtered view while paging; bookmark lookup must not scan a list
/// for each of the 149k catalogue entries. Holds only the latest result.
class EuropeanCatalogueFilter {
  List<Json>? _source;
  String? _key;
  List<Json> _rows = const [];
  List<Json> select(List<Json> source,
      {String query = '',
      String kind = 'Todos',
      String year = 'Todos',
      bool textOnly = false,
      bool saved = false,
      List<String> bookmarks = const []}) {
    final needle = normalize(query.trim());
    final key =
        jsonEncode([needle, kind, year, textOnly, saved, if (saved) bookmarks]);
    if (identical(source, _source) && key == _key) return _rows;
    final savedIds = saved ? bookmarks.toSet() : const <String>{};
    final rows = needle.isEmpty &&
            kind == 'Todos' &&
            year == 'Todos' &&
            !textOnly &&
            !saved
        ? source
        : source
            .where((n) =>
                (kind == 'Todos' || n['kind'] == kind) &&
                (year == 'Todos' || n['year'] == year) &&
                (!textOnly || (n['readableEditions'] as num) > 0) &&
                (!saved || savedIds.contains(n['id'])) &&
                (needle.isEmpty || (n['_search'] as String).contains(needle)))
            .toList();
    _source = source;
    _key = key;
    _rows = rows;
    return rows;
  }
}
