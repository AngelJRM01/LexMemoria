import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/main.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/persistence.dart';

void main() {
  testWidgets('guest can open library without signing in', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final store = (await tester.runAsync(
        () => AppStore.load(persistence: PreferencesPersistence(prefs))))!;
    await tester.pumpWidget(LexMemoria(store: store));
    await tester.pumpAndSettle();
    final explore = find.text('Explorar sin cuenta');
    await tester.scrollUntilVisible(explore, 250,
        scrollable: find.byType(Scrollable).first);
    await tester.tap(explore);
    await tester.pumpAndSettle();
    expect(store.onboarded, isTrue);
    await tester.tap(find.byIcon(Icons.menu_book_outlined).last);
    await tester.pumpAndSettle();
    expect(find.text('Tu biblioteca jurídica'), findsOneWidget);
    expect(find.text('Constitución Española'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
