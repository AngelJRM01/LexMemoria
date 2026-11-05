import 'models.dart';

/// Only the selected latest wording is indexed, never earlier block versions.
Map<String, String> buildReadingIndex(List<Json> rows) => {
      for (final row in rows)
        row['id'] as String: normalize('${row['title']}\n${row['text']}')
    };

int? savedReadingVersion(Json norm, Json unit, Json saved) {
  final hash = saved['unitVersionHash'];
  if (norm['latestVersion'] == null ||
      saved['normVersion'] != norm['latestVersion'] ||
      saved['normId'] != norm['id'] ||
      saved['unitId'] != unit['id'] ||
      hash is! String ||
      hash.isEmpty) {
    return null;
  }
  final versions = unit['versions'] as List? ?? [];
  for (var i = versions.length - 1; i >= 0; i--) {
    if (versions[i]['hash'] == hash) return i;
  }
  return null;
}
