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

int preferredEuropeanEdition(List<Json> versions, DateTime today) {
  if (versions.isEmpty) return -1;
  final now = civilDate(today);
  final candidates = <int>[];
  for (var i = 0; i < versions.length; i++) {
    final v = versions[i];
    if (v['kind'] == 'correction') continue;
    if (v['date'] is String && (v['date'] as String).compareTo(now) > 0) {
      continue;
    }
    candidates.add(i);
  }
  candidates.sort((a, b) => (versions[b]['date'] as String? ?? '')
      .compareTo(versions[a]['date'] as String? ?? ''));
  if (candidates.isNotEmpty) return candidates.first;
  return 0;
}

String europeanEditionLabel(Json version) {
  final label = version['kind'] == 'consolidated'
      ? 'Texto consolidado'
      : version['kind'] == 'correction'
          ? (version['celex'] is String
              ? 'Corrección · ${version['celex']}'
              : 'Corrección de errores')
          : 'Texto original';
  return version['date'] == null
      ? label
      : '$label · ${displayDate(version['date'])}';
}

class EuropeanRepository {
  final AppStore store;
  EuropeanRepository(this.store);
  static const manifestKey = 'lexmemoria.public.european.manifest.v1';
  final Map<String, dynamic> _decoded = {};
  final List<String> _order = [];

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
      throw StateError('El contenido no supera la comprobación de integridad.');
    }
    await store.packCache.write(hash, bytes);
    return bytes;
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
    objectUri(ref);
    final key = ref['sha256'] as String;
    if (_decoded.containsKey(key)) return _decoded[key];
    final raw = GZipDecoder().decodeBytes(await compressed(ref));
    if (raw.length != ref['expandedBytes']) {
      throw StateError('Archivo incompleto.');
    }
    dynamic result;
    if (ref['encoding'] == 'jsonl') {
      if (raw.length > 5000000) throw StateError('Página demasiado grande.');
      result = const LineSplitter()
          .convert(utf8.decode(raw))
          .where((line) => line.isNotEmpty)
          .map((line) => Json.from(jsonDecode(line)))
          .toList();
    } else {
      result = Json.from(jsonDecode(utf8.decode(raw)));
    }
    _decoded[key] = result;
    _order.add(key);
    while (_order.length > 4) {
      _decoded.remove(_order.removeAt(0));
    }
    return result;
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

bool europeanLiteralStudyAllowed(
    Json norm, Json edition, List<Json> documents) {
  if (![
        'Reglamento',
        'Directiva',
        'Decisión',
        'Tratado',
        'Acuerdo internacional'
      ].contains(norm['kind']) ||
      edition['kind'] == 'correction') {
    return false;
  }
  final title = normalize(norm['title'].toString());
  final change =
      RegExp(r'por (?:el|la) que se (?:modifica|deroga|rectifica|corrige)')
          .firstMatch(title);
  if (change != null &&
      !RegExp(r'relativ[oa]|se establece')
          .hasMatch(title.substring(0, change.start))) {
    return false;
  }
  return documents.any((d) =>
      d['sourceParser'] == 'eu-html-leaf-paragraphs-2' &&
      (d['warnings'] as List).isEmpty &&
      (d['units'] as List).any((u) => u['kind'] == 'article_candidate'));
}

/// A missed heading must never merge a second article or annex into a card.
bool europeanArticleParagraphsAllowed(List<Json> paragraphs) {
  final heading = RegExp(
      r'^(?:(?:art[íi]culo|article|art\.?)\s+|anexo(?:\s|$)|(?:t[íi]tulo|cap[íi]tulo|secci[óo]n|parte)\s+[ivxlcdm\d]+(?:\s|$))',
      caseSensitive: false,
      multiLine: true);
  return paragraphs
      .skip(1)
      .every((p) => !heading.hasMatch(p['text'].toString().trim()));
}

class _EuropeanCatalogueMemo {
  final String hash;
  final Future<List<Json>> value;
  _EuropeanCatalogueMemo(this.hash, this.value);
}
