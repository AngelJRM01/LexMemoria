import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/study.dart';
import 'package:lexmemoria/persistence.dart';

class DraftStorage implements LocalPersistence {
  int writes = 0;
  String? snapshot;
  bool fail = false;
  Completer<void>? hold;
  @override
  Future<String?> read() async => snapshot;
  @override
  Future<void> write(String value) async {
    writes++;
    if (fail) throw StateError('Disk full');
    await hold?.future;
    snapshot = value;
  }

  @override
  Future<void> close() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('typing is coalesced and closing flushes the latest draft',
      (tester) async {
    final storage = DraftStorage();
    final store = AppStore(await SharedPreferences.getInstance(), {},
        persistence: storage);
    await tester.pumpWidget(MaterialApp(home: CardEditor(store: store)));
    for (final text in ['a', 'ab', 'abc']) {
      await tester.enterText(find.byType(TextFormField).at(1), text);
      await tester.pump(const Duration(milliseconds: 70));
    }
    expect(storage.writes, 0);
    await tester.pump(const Duration(milliseconds: 300));
    expect(storage.writes, 1);
    expect(jsonDecode(storage.snapshot!)['draftCard']['front'], 'abc');
    await tester.enterText(find.byType(TextFormField).at(2), 'Respuesta');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(storage.writes, 2);
    expect(jsonDecode(storage.snapshot!)['draftCard']['back'], 'Respuesta');
    store.dispose();
  });
  testWidgets('background retries a failed draft without dropping its text',
      (tester) async {
    final storage = DraftStorage()..fail = true;
    final store = AppStore(await SharedPreferences.getInstance(), {},
        persistence: storage);
    await tester.pumpWidget(MaterialApp(home: CardEditor(store: store)));
    await tester.enterText(
        find.byType(TextFormField).at(1), 'Texto conservado');
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    expect(store.error, isNotNull);
    expect(store.data['draftCard']['front'], 'Texto conservado');
    storage.fail = false;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(jsonDecode(storage.snapshot!)['draftCard']['front'],
        'Texto conservado');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
  testWidgets('saving a card never resurrects a pending draft', (tester) async {
    final storage = DraftStorage();
    final store = AppStore(await SharedPreferences.getInstance(), {},
        persistence: storage);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => CardEditor(store: store))),
                    child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), 'Pregunta');
    await tester.enterText(find.byType(TextFormField).at(2), 'Respuesta');
    await tester.drag(find.byType(ListView).first, const Offset(0, -1000));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.ancestor(
        of: find.text('Guardar tarjeta'), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Guardar tarjeta'));
    await tester.pumpAndSettle();
    expect(store.cards.single.front, 'Pregunta');
    expect(store.data['draftCard'], isNull);
    final writes = storage.writes;
    await tester.pump(const Duration(seconds: 1));
    expect(storage.writes, writes);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
  testWidgets('draft status only confirms a completed write', (tester) async {
    final storage = DraftStorage()..hold = Completer<void>();
    final store = AppStore(await SharedPreferences.getInstance(), {},
        persistence: storage);
    await tester.pumpWidget(MaterialApp(home: CardEditor(store: store)));
    await tester.enterText(find.byType(TextFormField).at(1), 'Texto pendiente');
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Guardando borrador…'), findsOneWidget);
    expect(find.text('Borrador guardado'), findsNothing);
    storage.hold!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Borrador guardado'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });

  testWidgets('continuous typing checkpoints without waiting for idle',
      (tester) async {
    final storage = DraftStorage();
    final store = AppStore(await SharedPreferences.getInstance(), {},
        persistence: storage);
    await tester.pumpWidget(MaterialApp(home: CardEditor(store: store)));
    for (var i = 0; i < 7; i++) {
      await tester.enterText(find.byType(TextFormField).at(1), 'Texto $i');
      await tester.pump(const Duration(milliseconds: 180));
    }
    expect(storage.writes, greaterThanOrEqualTo(1));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    expect(jsonDecode(storage.snapshot!)['draftCard']['front'], 'Texto 6');
    store.dispose();
  });

  testWidgets(
      'back waits for persistence and a failed save keeps the editor open',
      (tester) async {
    final storage = DraftStorage()..fail = true;
    final store = AppStore(await SharedPreferences.getInstance(), {},
        persistence: storage);
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                body: TextButton(
                    onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => CardEditor(store: store))),
                    child: const Text('Abrir'))))));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(1), 'No perder');
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(CardEditor), findsOneWidget);
    expect(store.data['draftCard']['front'], 'No perder');
    expect(store.error, isNotNull);
    storage.fail = false;
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(CardEditor), findsNothing);
    expect(jsonDecode(storage.snapshot!)['draftCard']['front'], 'No perder');
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
