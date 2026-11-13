import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/library.dart';
import 'package:lexmemoria/study.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/models.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final library in [true, false]) {
      testWidgets(
          '${platform.name} ${library ? 'library' : 'cards'} search keeps its input connection when the keyboard resizes the page',
          (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(390, 844);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetViewInsets);
        final store = AppStore(await SharedPreferences.getInstance(), {
          'cards': [
            StudyCard(
                    id: 'c',
                    deck: 'Constitución',
                    front: 'Pregunta',
                    back: 'Respuesta')
                .toJson()
          ],
          'norms': [
            {
              'id': 'n',
              'title': 'Constitución Española',
              'short': 'Constitución',
              'subject': 'Constitucional',
              'jurisdiction': 'Estatal'
            }
          ],
        });
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
          appBar: AppBar(title: const Text('LexMemoria')),
          bottomNavigationBar: const SizedBox(height: 72),
          body: library ? LibraryPage(store: store) : StudyPage(store: store),
        )));
        final field = find.byType(TextField).first;
        await tester.tap(field);
        await tester.pump();
        final original =
            tester.state<EditableTextState>(find.byType(EditableText).first);
        expect(original.widget.focusNode.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
        // iPhone opening the keyboard crosses the old compact-layout threshold.
        tester.view.viewInsets = const FakeViewPadding(bottom: 360);
        await tester.pumpAndSettle();
        final resized =
            tester.state<EditableTextState>(find.byType(EditableText).first);
        expect(identical(original, resized), isTrue,
            reason:
                'Do not recreate the search field during keyboard animation');
        expect(resized.widget.focusNode.hasFocus, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
        await tester.enterText(field, 'Constitución');
        await tester.pump();
        tester.view.viewInsets = const FakeViewPadding(bottom: 390);
        await tester.pumpAndSettle();
        expect(
            tester
                .widget<EditableText>(find.byType(EditableText).first)
                .controller
                .text,
            'Constitución');
        expect(
            tester
                .widget<EditableText>(find.byType(EditableText).first)
                .focusNode
                .hasFocus,
            isTrue);
        tester.view.physicalSize = const Size(844, 390);
        tester.view.viewInsets = const FakeViewPadding(bottom: 160);
        await tester.pumpAndSettle();
        expect(
            identical(
                original,
                tester
                    .state<EditableTextState>(find.byType(EditableText).first)),
            isTrue);
        expect(
            tester
                .widget<EditableText>(find.byType(EditableText).first)
                .focusNode
                .hasFocus,
            isTrue);
        tester.view.physicalSize = const Size(390, 844);
        tester.view.viewInsets = FakeViewPadding.zero;
        await tester.pumpAndSettle();
        expect(
            identical(
                original,
                tester
                    .state<EditableTextState>(find.byType(EditableText).first)),
            isTrue);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        store.dispose();
      }, variant: TargetPlatformVariant({platform}));
    }
  }
}
