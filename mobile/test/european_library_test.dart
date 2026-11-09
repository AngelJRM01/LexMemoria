import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:lexmemoria/persistence.dart';
import 'package:lexmemoria/library.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/catalogue.dart';
import 'package:lexmemoria/legal_units.dart';
import 'package:lexmemoria/prepared.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
      'European original acts load offline and never create unreviewed exercises',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store =
        await AppStore.load(persistence: PreferencesPersistence(prefs));
    final european = store.catalogue
        .where((n) => const CatalogueFilters(scope: 'Europeo').matches(n))
        .toList();
    expect(european.length, 3);
    for (final norm in european) {
      expect(
          const CatalogueFilters(scope: 'Autonómico').matches(norm), isFalse);
      await store.downloadNorm(norm);
      final loaded = store.catalogue.firstWhere((n) => n['id'] == norm['id']);
      final units = (loaded['units'] as List).cast<Json>();
      expect(
          units.where((u) => legalUnitKind(u) == 'article').length,
          norm['celex'] == '32016R0679'
              ? 99
              : norm['celex'] == '32019L1152'
                  ? 26
                  : 4);
      expect(units.any((u) => legalUnitKind(u) == 'recitals'), isTrue);
      for (final format in ['qa', 'cloze', 'test', 'reference']) {
        expect(
            buildLiteralCards({'norm': norm, 'units': units, 'format': format}),
            isEmpty);
      }
      expect(units.every((u) => u['sourceParagraphs'] is List), isTrue);
      expect(
          units.every(
              (u) => (u['versions'] as List).first['effectiveFrom'] == null),
          isTrue);
    }
    store.dispose();
  });
  testWidgets(
      'European index separates recitals and labels the original edition',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = (await tester.runAsync(
        () => AppStore.load(persistence: PreferencesPersistence(prefs))))!;
    final norm = store.catalogue.firstWhere((n) => n['celex'] == '32016R0679');
    await tester.runAsync(() => store.downloadNorm(norm));
    await tester
        .pumpWidget(MaterialApp(home: NormPage(store: store, id: norm['id'])));
    await tester.pumpAndSettle();
    expect(find.text('Artículo 1'), findsOneWidget);
    expect(find.textContaining('Puede haber modificaciones posteriores'),
        findsOneWidget);
    expect(find.byTooltip('Tarjetas de esta norma'), findsNothing);
    await tester.tap(find.byTooltip('Partes de la norma'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Considerandos'));
    await tester.pumpAndSettle();
    expect(find.text('Artículo 1'), findsNothing);
    expect(find.text('Considerandos'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
