import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lexmemoria/main.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/library.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/study.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'capture real private-study screens using only synthetic local data',
      (tester) async {
    final store = await AppStore.load();
    final original = jsonEncode(store.data);
    await binding.convertFlutterSurfaceToImage();
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // ImageReader can still expose the preceding native frame after a route
      // transition on a software emulator. Warm it, pump and keep the second
      // unedited capture under the same name in the host driver.
      await binding.takeScreenshot(name);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      await binding.takeScreenshot(name);
    }

    try {
      store.data = {'onboarded': true};
      await store.loadPreparedCards();
      await tester.pumpWidget(LexMemoria(store: store));
      await capture('01-inicio');
      await tester.tap(find.byIcon(Icons.menu_book_outlined).last);
      await capture('02-biblioteca');
      final norm =
          store.catalogue.firstWhere((n) => n['id'] == 'BOE-A-1978-31229');
      await store.downloadNorm(norm);
      final loaded = store.catalogue.firstWhere((n) => n['id'] == norm['id']);
      final units = (loaded['units'] as List).map((u) => Json.from(u)).toList();
      final article = units.firstWhere((u) => u['title'] == 'Artículo 1');
      Navigator.of(tester.element(find.byType(LibraryPage))).push(
          MaterialPageRoute(
              builder: (_) =>
                  ReaderPage(store: store, norm: loaded, unit: article)));
      await capture('03-articulo');
      final cards = [...store.cards]..sort((a, b) =>
          (a.front.length + a.back.length)
              .compareTo(b.front.length + b.back.length));
      Navigator.of(tester.element(find.byType(ReaderPage))).push(
          MaterialPageRoute(
              builder: (_) => ReviewPage(store: store, queue: [cards.first])));
      await capture('04-tarjeta');
      await tester.tap(find.text('Mostrar respuesta'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('RESPUESTA'));
      await capture('05-respuesta');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      store.data = Json.from(jsonDecode(original));
      await store.save();
      await store.persistence.close();
      store.dispose();
    }
  });
}
