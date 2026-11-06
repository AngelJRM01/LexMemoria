import 'dart:math';

String civilDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

String displayDate(dynamic input,
    {bool time = false, String empty = 'Sin fecha'}) {
  if (input == null || input.toString().isEmpty) return empty;
  final raw = input.toString();
  if ((RegExp(r'^\d{8}$').hasMatch(raw) && legalDate(raw) == null) ||
      (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(raw) &&
          legalDate(raw.substring(0, 10)) == null)) {
    return empty;
  }
  final date = legalDate(raw) ?? DateTime.tryParse(raw)?.toLocal();
  if (date == null) return empty;
  final day =
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  return time && raw.contains('T')
      ? '$day · ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}'
      : day;
}

String normalize(String value) {
  var result = value.toLowerCase();
  const accented = 'áéíóúüñ';
  const plain = 'aeiouun';
  for (var i = 0; i < accented.length; i++) {
    result = result.replaceAll(accented[i], plain[i]);
  }
  return result;
}

// Canonical order makes comparison independent of JSON map insertion order.
dynamic canonicalJsonValue(dynamic value) {
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return {for (final key in keys) key: canonicalJsonValue(value[key])};
  }
  if (value is List) return value.map(canonicalJsonValue).toList();
  return value;
}

const accountProfileDefaults = <String, dynamic>{
  'displayName': '',
  'alias': '',
  'avatar': 'initials',
  'language': 'es',
  'theme': 'system',
  'allowAliasInvitations': false,
  'allowLinkInvitations': false,
  'studyNotifications': false,
  'legalNotifications': false,
  'collaborationNotifications': false,
  'noticeDailyLimit': 3,
  'quietStart': '22:00',
  'quietEnd': '08:00',
};

typedef Json = Map<String, dynamic>;
final _familiarNormNames = {
  for (final n in initialCatalogue()) n['id']: n['short'] as String
};
String friendlyNormLabel(Json norm) {
  if (norm['short'] is String && (norm['short'] as String).isNotEmpty) {
    return norm['short'];
  }
  if (_familiarNormNames[norm['id']] != null) {
    return _familiarNormNames[norm['id']]!;
  }
  final title = norm['title'] as String? ?? norm['id'].toString();
  final match = RegExp(r'^(.{1,60}?\s+[A-Z0-9]+/\d{4})\b', caseSensitive: false)
      .firstMatch(title);
  var label = match?.group(1) ??
      (title.length > 140 ? '${title.substring(0, 139)}…' : title);
  if (normalize(norm['jurisdiction'] ?? '').startsWith('autonom') &&
      norm['authority'] is String) {
    final region = (norm['authority'] as String)
        .replaceFirst(RegExp(r'^Comunidad (?:Autónoma|Foral) de '), '');
    if (region.isNotEmpty) label = '$label · $region';
  }
  return label;
}

class StudyCard {
  final String id,
      deck,
      front,
      back,
      explanation,
      type,
      normId,
      unitId,
      versionId,
      unitVersionHash;
  final String editorialState;
  final bool blocked;
  final List<String> options;
  final int? correct;
  final int revision;
  StudyCard(
      {required this.id,
      required this.deck,
      required this.front,
      required this.back,
      this.explanation = '',
      this.type = 'qa',
      this.normId = '',
      this.unitId = '',
      this.versionId = '',
      this.unitVersionHash = '',
      this.editorialState = 'user',
      this.blocked = false,
      this.options = const [],
      this.correct,
      this.revision = 1});
  Json toJson() => {
        'id': id,
        'deck': deck,
        'front': front,
        'back': back,
        'explanation': explanation,
        'type': type,
        'normId': normId,
        'unitId': unitId,
        'versionId': versionId,
        'unitVersionHash': unitVersionHash,
        'editorialState': editorialState,
        'blocked': blocked,
        'options': options,
        'correct': correct,
        'revision': revision
      };
  factory StudyCard.fromJson(Json j) => StudyCard(
      id: j['id'],
      deck: j['deck'],
      front: j['front'],
      back: j['back'],
      explanation: j['explanation'] ?? '',
      type: j['type'] ?? 'qa',
      normId: j['normId'] ?? '',
      unitId: j['unitId'] ?? '',
      versionId: j['versionId'] ?? '',
      unitVersionHash: j['unitVersionHash'] ?? '',
      editorialState: j['editorialState'] ?? 'user',
      blocked: j['blocked'] ?? false,
      options: List<String>.from(j['options'] ?? []),
      correct: j['correct'],
      revision: j['revision'] ?? 1);
}

/// Documented SM-2 variant, sm2-1. Shared fixtures with the backend.
Json schedule(Json old, int rating, DateTime at) {
  if (rating < 1 || rating > 4) throw ArgumentError.value(rating);
  var repetitions = (old['repetitions'] as num? ?? 0).toInt();
  var interval = (old['interval'] as num? ?? 0).toDouble();
  var ease = (old['ease'] as num? ?? 2.5).toDouble();
  switch (rating) {
    case 1:
      repetitions = 0;
      interval = 10 / 1440;
      ease = max(1.3, ease - .2);
    case 2:
      interval = max(1.0, interval * 1.2);
      ease = max(1.3, ease - .15);
      repetitions++;
    case 3:
      interval = repetitions == 0
          ? 1
          : repetitions == 1
              ? 6
              : max(1.0, interval * ease);
      repetitions++;
    case 4:
      interval = max(4.0, interval * ease * 1.3);
      ease += .15;
      repetitions++;
  }
  return {
    'repetitions': repetitions,
    'interval': interval,
    'ease': ease,
    'dueAt': at
        .toUtc()
        .add(Duration(milliseconds: (interval * 86400000).round()))
        .toIso8601String(),
    'reviewedAt': at.toUtc().toIso8601String(),
    'algorithm': 'sm2-1',
    'lapses': (old['lapses'] as num? ?? 0).toInt() + (rating == 1 ? 1 : 0)
  };
}

Json scoreExam(List<Json> questions, Json answers, double penalty) {
  var correct = 0, wrong = 0, blank = 0;
  for (final q in questions) {
    final answer = answers[q['id']];
    if (answer == null) {
      blank++;
    } else if (answer == q['correct']) {
      correct++;
    } else {
      wrong++;
    }
  }
  return {
    'correct': correct,
    'wrong': wrong,
    'blank': blank,
    'score': correct - wrong * penalty,
    'total': questions.length
  };
}

List<Json> initialCatalogue() => [
      {
        'id': 'BOE-A-1978-31229',
        'short': 'Constitución Española',
        'title': 'Constitución Española',
        'subject': 'Constitucional'
      },
      {
        'id': 'BOE-A-1889-4763',
        'short': 'Código Civil',
        'title':
            'Real Decreto de 24 de julio de 1889 por el que se publica el Código Civil',
        'subject': 'Civil'
      },
      {
        'id': 'BOE-A-1995-25444',
        'short': 'Código Penal',
        'title': 'Ley Orgánica 10/1995, de 23 de noviembre, del Código Penal',
        'subject': 'Penal'
      },
      {
        'id': 'BOE-A-2000-323',
        'short': 'Enjuiciamiento Civil',
        'title': 'Ley 1/2000, de 7 de enero, de Enjuiciamiento Civil',
        'subject': 'Procesal'
      },
      {
        'id': 'BOE-A-1882-6036',
        'short': 'Enjuiciamiento Criminal',
        'title':
            'Real Decreto de 14 de septiembre de 1882 por el que se aprueba la Ley de Enjuiciamiento Criminal',
        'subject': 'Procesal'
      },
      {
        'id': 'BOE-A-1985-12666',
        'short': 'Poder Judicial',
        'title': 'Ley Orgánica 6/1985, de 1 de julio, del Poder Judicial',
        'subject': 'Procesal'
      },
      {
        'id': 'BOE-A-2015-10565',
        'short': 'Procedimiento Administrativo',
        'title':
            'Ley 39/2015, de 1 de octubre, del Procedimiento Administrativo Común de las Administraciones Públicas',
        'subject': 'Administrativo'
      },
      {
        'id': 'BOE-A-2015-10566',
        'short': 'Régimen Jurídico del Sector Público',
        'title':
            'Ley 40/2015, de 1 de octubre, de Régimen Jurídico del Sector Público',
        'subject': 'Administrativo'
      },
      {
        'id': 'BOE-A-2015-11430',
        'short': 'Estatuto de los Trabajadores',
        'title':
            'Real Decreto Legislativo 2/2015, de 23 de octubre, por el que se aprueba el texto refundido de la Ley del Estatuto de los Trabajadores',
        'subject': 'Laboral'
      },
      {
        'id': 'BOE-A-2003-23186',
        'short': 'Ley General Tributaria',
        'title': 'Ley 58/2003, de 17 de diciembre, General Tributaria',
        'subject': 'Tributario'
      },
      {
        'id': 'BOE-A-1885-6627',
        'short': 'Código de Comercio',
        'title':
            'Real Decreto de 22 de agosto de 1885 por el que se publica el Código de Comercio',
        'subject': 'Mercantil'
      },
      {
        'id': 'BOE-A-2010-10544',
        'short': 'Sociedades de Capital',
        'title':
            'Real Decreto Legislativo 1/2010, de 2 de julio, por el que se aprueba el texto refundido de la Ley de Sociedades de Capital',
        'subject': 'Mercantil'
      },
      {
        'id': 'BOE-A-1998-16718',
        'short': 'Jurisdicción Contencioso-administrativa',
        'title':
            'Ley 29/1998, de 13 de julio, reguladora de la Jurisdicción Contencioso-administrativa',
        'subject': 'Administrativo'
      },
      {
        'id': 'BOE-A-2011-15936',
        'short': 'Jurisdicción Social',
        'title':
            'Ley 36/2011, de 10 de octubre, reguladora de la jurisdicción social',
        'subject': 'Laboral'
      },
      {
        'id': 'BOE-A-2017-12902',
        'short': 'Contratos del Sector Público',
        'title':
            'Ley 9/2017, de 8 de noviembre, de Contratos del Sector Público',
        'subject': 'Administrativo'
      },
      {
        'id': 'BOE-A-2015-11719',
        'short': 'Estatuto Básico del Empleado Público',
        'title':
            'Real Decreto Legislativo 5/2015, de 30 de octubre, por el que se aprueba el texto refundido de la Ley del Estatuto Básico del Empleado Público',
        'subject': 'Administrativo'
      },
      {
        'id': 'BOE-A-2018-16673',
        'short': 'Protección de Datos',
        'title':
            'Ley Orgánica 3/2018, de 5 de diciembre, de Protección de Datos Personales y garantía de los derechos digitales',
        'subject': 'Derechos Humanos'
      },
      {
        'id': 'BOE-A-2007-6115',
        'short': 'Igualdad Efectiva',
        'title':
            'Ley Orgánica 3/2007, de 22 de marzo, para la igualdad efectiva de mujeres y hombres',
        'subject': 'Derechos Humanos'
      },
      {
        'id': 'BOE-A-1985-5392',
        'short': 'Bases del Régimen Local',
        'title':
            'Ley 7/1985, de 2 de abril, Reguladora de las Bases del Régimen Local',
        'subject': 'Administrativo'
      },
      {
        'id': 'BOE-A-1979-23709',
        'short': 'Tribunal Constitucional',
        'title':
            'Ley Orgánica 2/1979, de 3 de octubre, del Tribunal Constitucional',
        'subject': 'Constitucional'
      },
    ]
        .map((n) => <String, dynamic>{
              ...n,
              'coverage': 'identified',
              'jurisdiction': 'Estado',
              'sourceUrl': 'https://www.boe.es/buscar/act.php?id=${n['id']}',
              'reviewState': 'pending'
            })
        .toList();

const subjects = [
  'Constitucional',
  'Civil',
  'Penal',
  'Procesal',
  'Administrativo',
  'Mercantil',
  'Laboral',
  'Tributario',
  'Internacional',
  'UE',
  'Derechos Humanos',
  'Criminología'
];
const tracks = [
  'Auxilio Judicial',
  'Tramitación Procesal',
  'Gestión Procesal',
  'Administrativo',
  'Estudio libre'
];

DateTime? legalDate(dynamic input) {
  if (input is! String) return null;
  final text = RegExp(r'^\d{8}$').hasMatch(input)
      ? '${input.substring(0, 4)}-${input.substring(4, 6)}-${input.substring(6, 8)}'
      : input;
  if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) return null;
  final parsed = DateTime.tryParse(text);
  if (parsed == null || civilDate(parsed) != text) return null;
  return DateTime.utc(parsed.year, parsed.month, parsed.day);
}

/// Selects source dates only. Ambiguous dates never fall back to publication.
Json resolveLegalVersions(List<Json> versions, DateTime asOf) {
  final target = DateTime.utc(asOf.year, asOf.month, asOf.day);
  DateTime? newest;
  int? selected;
  final candidates = <int>[];
  for (var i = 0; i < versions.length; i++) {
    final starts = legalDate(versions[i]['effectiveFrom']);
    final ends = versions[i]['effectiveTo'] == null
        ? null
        : legalDate(versions[i]['effectiveTo']);
    if (starts == null ||
        (versions[i]['effectiveTo'] != null && ends == null) ||
        (ends != null && !ends.isAfter(starts))) {
      return {
        'status': 'unresolved',
        'selectedIndex': null,
        'reason': 'Fechas de efecto incompletas o contradictorias.'
      };
    }
    if (!starts.isAfter(target) && (ends == null || target.isBefore(ends))) {
      candidates.add(i);
      if (newest == null || starts.isAfter(newest)) {
        newest = starts;
        selected = i;
      }
    }
  }
  if (selected == null) {
    return {
      'status': 'unavailable',
      'selectedIndex': null,
      'reason': 'No hay una redacción de la fuente para esta fecha.'
    };
  }
  final sameDate = candidates
      .where((i) => legalDate(versions[i]['effectiveFrom']) == newest)
      .map((i) => versions[i]['hash'] ?? versions[i]['text'])
      .toSet();
  if (sameDate.length > 1) {
    return {
      'status': 'unresolved',
      'selectedIndex': null,
      'reason':
          'Hay redacciones distintas con la misma fecha. Requiere revisión editorial.'
    };
  }
  return {
    'status': 'selected_by_source_date',
    'selectedIndex': selected,
    'reason':
        'Selección por fechas de la fuente; comprueba vigencias parciales y disposiciones transitorias.'
  };
}

bool isStudyDay(DateTime day, Json profile) {
  if ((profile['restDays'] as List? ?? []).contains(day.weekday)) return false;
  final date = civilDate(day);
  for (final vacation in profile['vacations'] as List? ?? []) {
    final start = vacation['start'] as String, end = vacation['end'] as String;
    if (date.compareTo(start) >= 0 && date.compareTo(end) <= 0) return false;
  }
  return true;
}

List<Json> weeklyForecast(
    List<StudyCard> cards, Json states, Json profile, DateTime start) {
  final pending = cards.where((c) => !c.blocked).toList();
  final limit = studyCapacity(profile);
  final assigned = <String>{};
  return List.generate(7, (i) {
    final day = DateTime(start.year, start.month, start.day + i);
    final end = DateTime(day.year, day.month, day.day + 1);
    final available = pending.where((c) {
      final state = states[c.id] as Map? ?? {};
      final due = DateTime.tryParse(state['dueAt'] ?? '');
      return !assigned.contains(c.id) && (due == null || due.isBefore(end));
    }).toList();
    final study = isStudyDay(day, profile);
    final count = study ? available.length.clamp(0, limit) : 0;
    if (study) assigned.addAll(available.take(count).map((c) => c.id));
    return {
      'date': civilDate(day),
      'study': study,
      'planned': count,
      'estimatedMinutes':
          (count * (profile['estimatedSecondsPerCard'] as num? ?? 60) / 60)
              .ceil(),
      'backlog': available.length - count
    };
  });
}

int studyCapacity(Json profile) {
  final goal = (profile['dailyGoal'] as num? ?? 20).toInt().clamp(1, 200);
  if (profile['hours'] is! num) return goal;
  final seconds =
      (profile['estimatedSecondsPerCard'] as num? ?? 60).clamp(5, 600);
  final capacity =
      ((profile['hours'] as num).clamp(.5, 8) * 3600 / seconds).floor();
  return min(goal, max(1, capacity));
}
