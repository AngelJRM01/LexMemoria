import 'models.dart';

String normSubject(Json norm) =>
    (norm['subject'] as String? ?? '').trim().isEmpty
        ? 'Normativa'
        : norm['subject'];

List<String> catalogueSubjects(Iterable<Json> norms) {
  final present = norms.map(normSubject).toSet();
  final extra = present.where((v) => !subjects.contains(v)).toList()..sort();
  return [
    ...subjects.where(present.contains),
    ...extra,
  ];
}

String? normCommunity(Json norm) {
  if (!normalize(norm['jurisdiction'] ?? '').startsWith('autonom')) return null;
  final value = normalize(norm['authority'] ?? '');
  for (final entry in _communities.entries) {
    if (entry.value.any(value.contains)) return entry.key;
  }
  return null;
}

const _communities = {
  'Andalucía': ['andalucia'],
  'Aragón': ['aragon'],
  'Asturias': ['asturias'],
  'Islas Baleares': ['illes balears', 'islas baleares'],
  'Canarias': ['canarias'],
  'Cantabria': ['cantabria'],
  'Castilla-La Mancha': ['castilla-la mancha'],
  'Castilla y León': ['castilla y leon'],
  'Cataluña': ['cataluna'],
  'Comunidad Valenciana': ['valenciana'],
  'Extremadura': ['extremadura'],
  'Galicia': ['galicia'],
  'Madrid': ['madrid'],
  'Murcia': ['murcia'],
  'Navarra': ['navarra'],
  'País Vasco': ['pais vasco'],
  'La Rioja': ['la rioja'],
};

List<String> catalogueCommunities(Iterable<Json> norms) =>
    norms.map(normCommunity).whereType<String>().toSet().toList()..sort();

class CatalogueFilters {
  final String subject, scope, community;
  const CatalogueFilters(
      {this.subject = 'Todas', this.scope = 'Todos', this.community = 'Todas'});
  bool matches(Json norm) =>
      (subject == 'Todas' || normSubject(norm) == subject) &&
      (scope == 'Todos' ||
          (scope == 'Estatal'
              ? normalize(norm['jurisdiction'] ?? '').startsWith('esta')
              : scope == 'Europeo'
                  ? norm['jurisdiction'] == 'Unión Europea'
                  : scope == 'Autonómico' &&
                      normalize(norm['jurisdiction'] ?? '')
                          .startsWith('autonom'))) &&
      (community == 'Todas' || normCommunity(norm) == community);
}

class ResultPage<T> {
  final List<T> rows;
  final int size;
  late final int pages = rows.isEmpty ? 1 : (rows.length / size).ceil();
  late final int page;
  ResultPage(this.rows, int requested, this.size) {
    if (size < 1) throw ArgumentError('Invalid page size');
    page = requested.clamp(0, pages - 1);
  }
  List<T> get items => rows.skip(page * size).take(size).toList();
}

final _normSearchCache = Expando<String>();
String normSearchText(Json norm) => _normSearchCache[norm] ??= normalize(
    '${norm['title']} ${norm['subject'] ?? ''} ${norm['id']} ${norm['authority'] ?? ''}');
