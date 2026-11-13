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

final _publicationDateFormat = RegExp(r'^(?:\d{8}|\d{4}-\d{2}-\d{2})$');
DateTime? normPublicationDate(Json norm) {
  final raw = norm['publicationDate'];
  if (raw is! String || !_publicationDateFormat.hasMatch(raw.trim())) {
    return null;
  }
  final value = raw.trim().replaceAll('-', '');
  final year = int.parse(value.substring(0, 4)),
      month = int.parse(value.substring(4, 6)),
      day = int.parse(value.substring(6, 8));
  if (year < 1 || month < 1 || month > 12 || day < 1 || day > 31) return null;
  final date = DateTime.utc(year, month, day);
  return date.year == year && date.month == month && date.day == day
      ? date
      : null;
}

String publicationDateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year.toString().padLeft(4, '0')}';

String publicationRangeLabel(DateTime? from, DateTime? to) => from != null &&
        to != null &&
        from == to
    ? publicationDateLabel(from)
    : '${from == null ? 'Inicio' : publicationDateLabel(from)} – ${to == null ? 'Sin límite' : publicationDateLabel(to)}';

bool _publicationMatches(Json norm, DateTime? from, DateTime? to) {
  if (from == null && to == null) return true;
  final date = normPublicationDate(norm);
  if (date == null) return false;
  final start =
      from == null ? null : DateTime.utc(from.year, from.month, from.day);
  final end = to == null ? null : DateTime.utc(to.year, to.month, to.day);
  return (start == null || !date.isBefore(start)) &&
      (end == null || !date.isAfter(end));
}

class CatalogueFilters {
  final String subject, scope, community;
  final DateTime? publishedFrom, publishedTo;
  const CatalogueFilters(
      {this.subject = 'Todas',
      this.scope = 'Todos',
      this.community = 'Todas',
      this.publishedFrom,
      this.publishedTo});
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
      (community == 'Todas' || normCommunity(norm) == community) &&
      _publicationMatches(norm, publishedFrom, publishedTo);
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
String normSearchText(Json norm) => _normSearchCache[norm] ??= () {
      final date = normPublicationDate(norm);
      final dates = date == null
          ? ''
          : '${date.toIso8601String().substring(0, 10)} ${publicationDateLabel(date)} ${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}';
      return normalize(
          '${norm['title']} ${norm['subject'] ?? ''} ${norm['id']} ${norm['authority'] ?? ''} $dates');
    }();
