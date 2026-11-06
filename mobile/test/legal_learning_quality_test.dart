import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/library.dart';
import 'package:lexmemoria/legal_units.dart';
import 'package:lexmemoria/prepared.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final norm = {'id': 'quality', 'title': 'Norma', 'latestVersion': 'v1'};
  Json unit(String title, String text, {String type = 'precepto'}) => {
        'id': title,
        'title': title,
        'type': type,
        'versions': [
          {'text': text, 'hash': title}
        ]
      };
  test(
      'only articles generate exercises, never signatures, headings or fallback prose',
      () {
    final others = [
      unit('TÍTULO I',
          'El Gobierno garantiza la seguridad jurídica en treinta días.',
          type: 'encabezado'),
      unit('Preámbulo',
          'El Gobierno garantiza la seguridad jurídica en treinta días.'),
      unit('Disposición final',
          'El Gobierno garantiza la seguridad jurídica en treinta días.')
    ];
    for (final format in ['qa', 'cloze', 'test', 'reference']) {
      expect(
          buildLiteralCards({'norm': norm, 'units': others, 'format': format}),
          isEmpty);
    }
    expect(legalUnitKind(unit('Art 31', 'Una regla.')), 'article');
    expect(legalUnitKind(unit('pr', 'Texto.', type: 'preambulo')), 'preamble');
  });
  test('editorial amendment notes are not learned or spoken as legal rules',
      () {
    final version = {
      'text':
          'Artículo 1\nEl Gobierno garantiza la seguridad jurídica en treinta días.\nSe modifica por la reforma.',
      'xml':
          '<version><p class="articulo">Artículo 1</p><p class="parrafo">El Gobierno garantiza la seguridad jurídica en treinta días.</p><blockquote><p class="nota_pie">Se modifica por la reforma.</p></blockquote></version>',
      'hash': 'h'
    };
    expect(legalBodyText(version), isNot(contains('Se modifica')));
    expect(version['xml'], contains('Se modifica'));
    final cards = buildLiteralCards({
      'norm': norm,
      'units': [
        {
          'id': 'a1',
          'title': 'Artículo 1',
          'type': 'precepto',
          'versions': [version]
        }
      ]
    });
    expect(cards, isNotEmpty);
    expect(cards.every((c) => !c['back'].contains('Se modifica')), isTrue);
  });
  test('unrelated long words never become cloze or test targets', () {
    final prose = unit('Artículo 1',
        'Mariposas luminosas acompañaban senderistas tranquilos durante excursiones montañosas.');
    for (final format in ['cloze', 'test']) {
      expect(
          buildLiteralCards({
            'norm': norm,
            'units': [prose],
            'format': format
          }),
          isEmpty);
    }
  });
  test(
      'tests require three distinct alternatives of the same semantic category',
      () {
    final units = List.generate(
        4,
        (i) => unit(
            'Artículo ${i + 1}',
            'El Gobierno resolverá el procedimiento administrativo en ${[
              10,
              20,
              30,
              40
            ][i]} días.'));
    final cards =
        buildLiteralCards({'norm': norm, 'units': units, 'format': 'test'});
    expect(cards, hasLength(4));
    for (final card in cards) {
      expect((card['options'] as List).map((v) => targetCategory(v)).toSet(),
          {'duration'});
      expect(card['options'][card['correct']], card['back']);
      expect((card['options'] as List).toSet().length, 4);
    }
    expect(
        buildLiteralCards({
          'norm': norm,
          'units': [units.first],
          'format': 'test'
        }),
        isEmpty);
  });
  test(
      'long unsplittable sentences are omitted rather than cut into arbitrary rules',
      () {
    final text =
        'El Gobierno ${List.filled(90, 'garantiza').join(' ')} la seguridad jurídica.';
    expect(exercisePassages('Artículo 1', text), isEmpty);
    expect(
        exercisePassages('Artículo 1',
            'Artículo 1. El Gobierno garantiza la seguridad jurídica.'),
        isNotEmpty);
  });
  testWidgets(
      'article index hides preamble and titles while retaining a separate preamble view',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final s = AppStore(await SharedPreferences.getInstance(), {
      'norms': [
        {
          ...norm,
          'units': [
            unit('Preámbulo', 'Texto conservado del preámbulo.'),
            unit('TÍTULO PRELIMINAR', 'Encabezado', type: 'encabezado'),
            unit('Artículo 1', 'Texto del artículo primero.')
          ]
        }
      ]
    });
    await tester
        .pumpWidget(MaterialApp(home: NormPage(store: s, id: 'quality')));
    expect(find.text('Artículo 1'), findsOneWidget);
    expect(find.text('Preámbulo'), findsNothing);
    expect(find.widgetWithText(ListTile, 'TÍTULO PRELIMINAR'), findsNothing);
    expect(find.text('TÍTULO PRELIMINAR'), findsOneWidget);
    await tester.tap(find.byTooltip('Partes de la norma'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Preámbulo'));
    await tester.pumpAndSettle();
    expect(find.text('Preámbulo'), findsOneWidget);
    expect(find.text('Artículo 1'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    s.dispose();
  });
}
