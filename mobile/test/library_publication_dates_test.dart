import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/catalogue.dart';
import 'package:lexmemoria/library.dart';
import 'package:lexmemoria/store.dart';

void main() {
  test(
      'publication dates accept BOE and EUR-Lex formats and reject invalid calendar dates',
      () {
    expect(normPublicationDate({'publicationDate': '20151031'}),
        DateTime.utc(2015, 10, 31));
    expect(normPublicationDate({'publicationDate': '2024-02-29'}),
        DateTime.utc(2024, 2, 29));
    for (final raw in [
      '20230229',
      '2024-02-30',
      '20241301',
      '20240001',
      '2024-0201',
      '00000101',
      '',
      null
    ]) {
      expect(normPublicationDate({'publicationDate': raw}), isNull,
          reason: '$raw');
    }
    expect(
        normPublicationDate({
          'id': 'BOE-A-2015-1',
          'effectiveFrom': '20151031',
          'sourceUpdatedAt': '2026-01-01'
        }),
        isNull);
  });
  test('date ranges are inclusive and combine with jurisdiction and subject',
      () {
    final filter = CatalogueFilters(
        subject: 'Civil',
        scope: 'Estatal',
        publishedFrom: DateTime(2020, 1, 1, 23),
        publishedTo: DateTime(2020, 12, 31, 1));
    bool matches(String date,
            {String subject = 'Civil', String scope = 'Estado'}) =>
        filter.matches({
          'publicationDate': date,
          'subject': subject,
          'jurisdiction': scope
        });
    expect(matches('20200101'), isTrue);
    expect(matches('2020-12-31'), isTrue);
    expect(matches('20191231'), isFalse);
    expect(matches('20210101'), isFalse);
    expect(matches('20200601', subject: 'Penal'), isFalse);
    expect(matches('20200601', scope: 'Unión Europea'), isFalse);
    expect(filter.matches({'subject': 'Civil', 'jurisdiction': 'Estado'}),
        isFalse);
    expect(const CatalogueFilters().matches({'id': 'unknown'}), isTrue);
  });
  test('publication date can be found in human, ISO and compact formats', () {
    final text = normSearchText({
      'id': 'n',
      'title': 'Una norma',
      'publicationDate': '20151031',
      'sourceUpdatedAt': '20261101'
    });
    for (final query in ['31/10/2015', '2015-10-31', '20151031']) {
      expect(text, contains(query));
    }
    expect(text, isNot(contains('01/11/2026')));
  });
  testWidgets(
      'library applies and clears publication dates and resets pagination',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(430, 1000);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    final store = AppStore(await SharedPreferences.getInstance(), {
      'norms': [
        for (var i = 0; i < 45; i++)
          {
            'id': 'n$i',
            'title': 'Fichafecha $i',
            'subject': 'Civil',
            'jurisdiction': 'Estado',
            'publicationDate': i == 25 ? '20200102' : '20100101'
          },
        {
          'id': 'unknown',
          'title': 'Fichafecha sin fecha',
          'subject': 'Civil',
          'jurisdiction': 'Estado'
        },
      ]
    });
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LibraryPage(store: store))));
    await tester.enterText(find.byType(TextField).first, 'Fichafecha');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Página siguiente'));
    await tester.pumpAndSettle();
    expect(find.text('Página 2 de 3'), findsOneWidget);
    await tester.tap(find.byTooltip('Filtros de biblioteca'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Todas las fechas'));
    await tester.tap(find.text('Todas las fechas'));
    await tester.pumpAndSettle();
    final picker = find.byType(DateRangePickerDialog);
    expect(picker, findsOneWidget);
    Navigator.of(tester.element(picker)).pop(
        DateTimeRange(start: DateTime(2020, 1, 1), end: DateTime(2020, 1, 31)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Aplicar filtros'));
    await tester.tap(find.text('Aplicar filtros'));
    await tester.pumpAndSettle();
    expect(find.text('Página 1 de 1'), findsOneWidget);
    expect(find.text('Fichafecha 25'), findsOneWidget);
    expect(find.text('Publicada: 02/01/2020'), findsOneWidget);
    expect(find.text('Fichafecha sin fecha'), findsNothing);
    final chip =
        find.widgetWithText(InputChip, 'Publicación: 01/01/2020 – 31/01/2020');
    expect(chip, findsOneWidget);
    tester.widget<InputChip>(chip).onDeleted!();
    await tester.pumpAndSettle();
    expect(find.text('Página 1 de 3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
