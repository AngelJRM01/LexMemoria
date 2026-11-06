import 'dart:convert';
import 'models.dart';

/// Validate before replacing any state. Unknown fields are retained for forward
/// compatibility; known fields must be safe for their existing readers.
Json decodeStudyBackup(String text) {
  final parsed = jsonDecode(text);
  if (parsed is! Map ||
      parsed['schemaVersion'] != 1 ||
      parsed['data'] is! Map) {
    throw const FormatException(
        'Copia incompatible. No se ha sustituido nada.');
  }
  final data = Json.from(parsed['data']);
  Never invalid(String section) => throw FormatException(
      'La sección $section no es válida. No se ha sustituido nada.');
  for (final key in [
    'profile',
    'notes',
    'states',
    'readingPositions',
    'lastReadUnits',
    'remoteCardIds',
    'remoteCardRevisions',
    'remoteCardClientIds',
    'remoteCardDeckIds',
    'remoteDeckNames',
    'workspaceBase'
  ]) {
    if (data[key] != null && data[key] is! Map) invalid(key);
  }
  for (final key in [
    'cards',
    'cardHistory',
    'supersededPreparedCards',
    'reviews',
    'courses',
    'norms',
    'archivedPacks',
    'notifications',
    'reports',
    'syncConflicts',
    'workspaceHistory',
    'examHistory'
  ]) {
    final entries = data[key];
    if (entries == null) continue;
    if (entries is! List || entries.any((e) => e is! Map)) invalid(key);
  }
  for (final key in ['follows', 'bookmarks', 'favoriteCards']) {
    if (data[key] != null &&
        (data[key] is! List || (data[key] as List).any((e) => e is! String))) {
      invalid(key);
    }
  }
  for (final key in ['session', 'activeExam', 'restoreCheckpoint']) {
    if (data[key] != null && data[key] is! Map) invalid(key);
  }
  for (final key in [
    'dark',
    'onboarded',
    'starterInstalled',
    'internalAlerts',
    'analyticsConsent',
    'marketingConsent'
  ]) {
    if (data[key] != null && data[key] is! bool) invalid(key);
  }
  final ids = <String>{};
  for (final raw in data['cards'] as List? ?? []) {
    _validateCard(Json.from(raw), invalid);
    if (!ids.add(raw['id'])) invalid('cards: identificadores duplicados');
  }
  for (final key in ['cardHistory', 'supersededPreparedCards']) {
    for (final raw in data[key] as List? ?? []) {
      _validateCard(Json.from(raw), invalid);
    }
  }
  final reviewIds = <String>{};
  for (final raw in data['reviews'] as List? ?? []) {
    if (raw['id'] is! String ||
        raw['cardId'] is! String ||
        raw['rating'] is! int ||
        raw['rating'] < 1 ||
        raw['rating'] > 4 ||
        raw['occurredAt'] is! String ||
        DateTime.tryParse(raw['occurredAt']) == null ||
        !reviewIds.add(raw['id'])) {
      invalid('reviews');
    }
  }
  for (final value in (data['states'] as Map? ?? {}).values) {
    if (value is! Map) invalid('states');
    for (final key in ['repetitions', 'interval', 'ease', 'lapses']) {
      if (value[key] != null &&
          (value[key] is! num ||
              !(value[key] as num).isFinite ||
              value[key] < 0)) {
        invalid('states');
      }
    }
    if (value['dueAt'] != null &&
        (value['dueAt'] is! String ||
            DateTime.tryParse(value['dueAt']) == null)) {
      invalid('states');
    }
  }
  for (final value in (data['notes'] as Map? ?? {}).values) {
    if (value is! String) invalid('notes');
  }
  final profile = data['profile'] as Map? ?? {};
  if (profile['deckPriorities'] != null &&
      (profile['deckPriorities'] is! Map ||
          (profile['deckPriorities'] as Map).entries.any((e) =>
              e.key is! String ||
              e.value is! num ||
              !(e.value as num).isFinite ||
              e.value < 0 ||
              e.value > 3))) {
    invalid('profile');
  }
  if (profile['preferredExerciseTypes'] != null &&
      (profile['preferredExerciseTypes'] is! List ||
          (profile['preferredExerciseTypes'] as List).any((v) => ![
                'qa',
                'cloze',
                'test',
                'truefalse',
                'order',
                'case'
              ].contains(v)))) {
    invalid('profile');
  }
  if (profile['estimatedSecondsPerCard'] != null &&
      (profile['estimatedSecondsPerCard'] is! num ||
          !(profile['estimatedSecondsPerCard'] as num).isFinite ||
          profile['estimatedSecondsPerCard'] < 5 ||
          profile['estimatedSecondsPerCard'] > 600)) {
    invalid('profile');
  }
  if (profile['dailyGoal'] != null &&
      (profile['dailyGoal'] is! num ||
          !(profile['dailyGoal'] as num).isFinite ||
          profile['dailyGoal'] < 1 ||
          profile['dailyGoal'] > 200)) {
    invalid('profile');
  }
  if (profile['restDays'] != null &&
      (profile['restDays'] is! List ||
          (profile['restDays'] as List)
              .any((v) => v is! int || v < 1 || v > 7))) {
    invalid('profile');
  }
  for (final key in ['mode', 'goal', 'subject', 'examDate']) {
    if (profile[key] != null && profile[key] is! String) invalid('profile');
  }
  if (profile['hours'] != null &&
      (profile['hours'] is! num ||
          !(profile['hours'] as num).isFinite ||
          profile['hours'] < 0)) {
    invalid('profile');
  }
  if (profile['vacations'] != null) {
    if (profile['vacations'] is! List) invalid('profile');
    for (final vacation in profile['vacations']) {
      if (vacation is! Map ||
          vacation['start'] is! String ||
          vacation['end'] is! String ||
          legalDate(vacation['start']) == null ||
          legalDate(vacation['end']) == null ||
          legalDate(vacation['end'])!.isBefore(legalDate(vacation['start'])!)) {
        invalid('profile');
      }
    }
  }
  for (final course in data['courses'] as List? ?? []) {
    if (course['id'] is! String ||
        course['title'] is! String ||
        (course['archived'] != null && course['archived'] is! bool)) {
      invalid('courses');
    }
    if (course['topics'] != null && course['topics'] is! List) {
      invalid('courses');
    }
    for (final topic in course['topics'] as List? ?? []) {
      if (topic is! Map ||
          topic['title'] is! String ||
          (topic['notes'] != null && topic['notes'] is! String)) {
        invalid('courses');
      }
    }
    if (course['assessments'] != null && course['assessments'] is! List) {
      invalid('courses');
    }
    var total = 0.0;
    for (final item in course['assessments'] as List? ?? []) {
      if (item is! Map || item['title'] is! String) invalid('courses');
      for (final key in ['weight', 'maximum']) {
        if (item[key] is! num ||
            !(item[key] as num).isFinite ||
            item[key] <= 0) {
          invalid('courses');
        }
      }
      if (item['score'] != null &&
          (item['score'] is! num ||
              !(item['score'] as num).isFinite ||
              item['score'] < 0 ||
              item['score'] > item['maximum'])) {
        invalid('courses');
      }
      total += (item['weight'] as num).toDouble();
    }
    if (total > 100.000001) invalid('courses');
  }
  final session = data['session'];
  if (session != null &&
      (session['ids'] is! List ||
          (session['ids'] as List).any((v) => v is! String) ||
          session['index'] is! int ||
          session['index'] < 0 ||
          session['index'] > session['ids'].length)) {
    invalid('session');
  }
  // A backup is data, never authority to reuse credentials still in the vault.
  if (data['localDataOwnerId'] == null && data['remoteUserId'] is String) {
    data['localDataOwnerId'] = data['remoteUserId'];
    data['localDataServer'] = data['remoteServer'];
  }
  for (final key in [
    'auth',
    'remoteUserId',
    'remoteServer',
    'remoteGoogleLinked',
    'autoSyncConsent',
    'autoWorkspaceConsent',
    'workspaceOutbox',
    'workspaceRevision',
    'accountProfileBase',
    'accountProfileRevision',
    'serverProgressVersion',
    'syncOutbox',
    'progressSyncHash',
    'providerDeletionSubject',
    'providerDeletionOwner',
    'providerDeletionServer',
    'remoteCardIds',
    'remoteCardRevisions',
    'remoteCardClientIds',
    'remoteCardDeckIds',
    'remoteDeckNames',
    'workspaceBase'
  ]) {
    data.remove(key);
  }
  return data;
}

void _validateCard(Json raw, Never Function(String) invalid) {
  for (final key in ['id', 'deck', 'front', 'back']) {
    if (raw[key] is! String || (key == 'id' && (raw[key] as String).isEmpty)) {
      invalid('cards');
    }
  }
  for (final key in [
    'explanation',
    'type',
    'normId',
    'unitId',
    'versionId',
    'unitVersionHash',
    'editorialState'
  ]) {
    if (raw[key] != null && raw[key] is! String) invalid('cards');
  }
  if (raw['revision'] != null &&
      (raw['revision'] is! int || raw['revision'] < 1)) {
    invalid('cards');
  }
  if (raw['blocked'] != null && raw['blocked'] is! bool) invalid('cards');
  final options = raw['options'] ?? <String>[];
  if (options is! List || options.any((v) => v is! String)) invalid('cards');
  if (raw['correct'] != null &&
      (raw['correct'] is! int ||
          raw['correct'] < 0 ||
          raw['correct'] >= options.length)) {
    invalid('cards');
  }
  StudyCard.fromJson(raw);
}
