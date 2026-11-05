import 'package:flutter_test/flutter_test.dart';
import 'package:lexmemoria/models.dart';

void main() {
  test('future effective date never replaces earlier text', () {
    final versions = <Json>[
      {'effectiveFrom': '20250101', 'text': 'A'},
      {'effectiveFrom': '20270101', 'publicationDate': '20261101', 'text': 'B'},
    ];
    expect(
        resolveLegalVersions(versions, DateTime(2026, 11, 4))['selectedIndex'],
        0);
    expect(
        resolveLegalVersions(versions, DateTime(2027, 1, 1))['selectedIndex'],
        1);
  });
  test('unknown dates, conflicts and nonexistent dates are unresolved', () {
    expect(legalDate('2026-02-30'), isNull);
    expect(
        resolveLegalVersions([
          {'text': 'A', 'publicationDate': '20250101'}
        ], DateTime(2026))['selectedIndex'],
        isNull);
    expect(
        resolveLegalVersions([
          {'effectiveFrom': '20250101', 'text': 'A'},
          {'effectiveFrom': '20250101', 'text': 'B'}
        ], DateTime(2026))['status'],
        'unresolved');
  });
  test('rest and vacation boundaries respect civil dates', () {
    final profile = <String, dynamic>{
      'restDays': [7],
      'vacations': [
        {'start': '2026-11-09', 'end': '2026-11-10'}
      ]
    };
    expect(isStudyDay(DateTime(2026, 11, 8), profile), isFalse);
    expect(isStudyDay(DateTime(2026, 11, 9, 23), profile), isFalse);
    expect(isStudyDay(DateTime(2026, 11, 10), profile), isFalse);
    expect(isStudyDay(DateTime(2026, 11, 11), profile), isTrue);
  });
  test('weekly forecast carries backlog past rest and excludes blocked cards',
      () {
    final cards = List.generate(
        5,
        (i) => StudyCard(
            id: '$i', deck: 'D', front: 'Q', back: 'A', blocked: i == 4));
    final forecast = weeklyForecast(
        cards,
        {},
        {
          'dailyGoal': 2,
          'restDays': [7]
        },
        DateTime(2026, 11, 8));
    expect(forecast[0]['planned'], 0);
    expect(forecast[0]['backlog'], 4);
    expect(forecast[1]['planned'], 2);
    expect(forecast[2]['planned'], 2);
    expect(forecast[3]['planned'], 0);
    expect(
        forecast.fold<int>(0, (sum, day) => sum + (day['planned'] as int)), 4);
  });
}
