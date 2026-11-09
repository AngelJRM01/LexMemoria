import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:lexmemoria/catalogue.dart';
import 'package:lexmemoria/library.dart';
import 'package:lexmemoria/study.dart';
import 'package:lexmemoria/exercises.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/prepared.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/persistence.dart';

Json regionNorm(String id, String authority) => {
      'id': id,
      'title': 'Norma $id',
      'latestVersion': 'v1',
      'subject': 'Civil',
      'jurisdiction': 'Autonómico',
      'authority': authority
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'community aliases are merged and state departments are never communities',
      () {
    expect(normCommunity(regionNorm('a', 'Comunitat Valenciana')),
        'Comunidad Valenciana');
    expect(normCommunity(regionNorm('b', 'Comunidad Valenciana')),
        'Comunidad Valenciana');
    expect(
        normCommunity(
            regionNorm('c', 'Comunidad Autónoma de las Illes Balears')),
        'Islas Baleares');
    expect(
        normCommunity({
          ...regionNorm('d', 'Comunidad de Madrid'),
          'jurisdiction': 'Estado'
        }),
        isNull);
    expect(
        catalogueSubjects([
          {'subject': 'Civil'},
          {'subject': 'Normativa'}
        ]),
        ['Civil', 'Normativa']);
    expect(
        catalogueSubjects([
          {'subject': 'Civil'}
        ]),
        isNot(contains('Criminología')));
    final rows = List.generate(101, (i) => i);
    expect(ResultPage(rows, 5, 20).items, [100]);
    expect(ResultPage(rows, 99, 20).page, 5);
    expect(ResultPage([], 0, 20).pages, 1);
  });

  test(
      'real catalogue has populated subjects and all 17 autonomous communities',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final store =
        await AppStore.load(persistence: PreferencesPersistence(prefs));
    final regional = store.catalogue
        .where((n) => normalize(n['jurisdiction'] ?? '').startsWith('autonom'))
        .toList();
    expect(store.corpusNorms.length, 12457);
    expect(regional.length, 3623);
    expect(regional.every((n) => normCommunity(n) != null), isTrue);
    expect(catalogueCommunities(store.catalogue).length, 17);
    expect(store.availableSubjects, isNot(contains('Criminología')));
    store.dispose();
  });

  testWidgets('library paginates, jumps to a page and resets on search',
      (tester) async {
    final store = AppStore(await SharedPreferences.getInstance(), {});
    store.corpusNorms = List.generate(
        65,
        (i) => {
              'id': 'page-$i',
              'title': 'Norma de página $i',
              'subject': 'Civil'
            });
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: LibraryPage(store: store))));
    await tester.pumpAndSettle();
    expect(find.textContaining('Página 1 de'), findsOneWidget);
    expect(find.text('Norma de página 64'), findsNothing);
    final pagerPosition = tester.getTopLeft(find.textContaining('Página 1 de'));
    final searchPosition = tester.getTopLeft(find.byType(TextField));
    await tester.drag(find.byType(ListView).last, const Offset(0, -800));
    await tester.pumpAndSettle();
    expect(
        tester.getTopLeft(find.textContaining('Página 1 de')), pagerPosition);
    expect(tester.getTopLeft(find.byType(TextField)), searchPosition);
    await tester.tap(find.byTooltip('Página siguiente'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Página 2 de'), findsOneWidget);
    expect(find.text('Norma de página 0'), findsOneWidget);
    await tester.tap(find.textContaining('Página 2 de'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '4');
    await tester.tap(find.text('Ir'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Página 4 de'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Norma de página 64');
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate(
            (w) => w is Text && w.data == 'Norma de página 64'),
        findsOneWidget);
    expect(find.text('Página 1 de 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  testWidgets('community filtering applies to library and prepared decks',
      (tester) async {
    final store = AppStore(await SharedPreferences.getInstance(), {});
    final rows = [
      regionNorm('andalucia', 'Comunidad Autónoma de Andalucía'),
      regionNorm('cataluna', 'Comunidad Autónoma de Cataluña')
    ];
    store.corpusNorms = rows;
    store.preparedDecks = rows.map((r) => {...r, 'count': 2}).toList();
    for (final prepared in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          home: prepared
              ? PreparedDecksPage(store: store)
              : Scaffold(body: LibraryPage(store: store))));
      await tester.pumpAndSettle();
      await tester.tap(find
          .byTooltip(prepared ? 'Filtros de mazos' : 'Filtros de biblioteca'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).first);
      await tester.pumpAndSettle();
      expect(find.text('Criminología'), findsNothing);
      await tester.tap(find.text('Todas').last);
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>).at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Andalucía').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Aplicar filtros'));
      await tester.pumpAndSettle();
      expect(find.text('Norma andalucia'), findsOneWidget);
      expect(find.text('Norma cataluna'), findsNothing);
      expect(find.text('Página 1 de 1'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    }
    store.dispose();
  });

  test('European clozes hide complete legal concepts and complete quantities',
      () {
    final paragraphs = [
      'El responsable del tratamiento aplicará las medidas necesarias para proteger los datos personales y garantizar los derechos y libertades fundamentales del interesado.',
      'La autoridad de control velará por la aplicación del Derecho de la Unión y protegerá los derechos del interesado en el territorio de cada Estado miembro.',
      'El responsable del tratamiento podrá ser sancionado con una multa de 20 000 000 EUR cuando concurran las condiciones previstas en la norma.',
      'Las infracciones podrán ser sancionadas con una multa de hasta el 4 % del volumen de negocio total anual global, bajo la supervisión de la autoridad de control.',
      'El responsable del tratamiento responderá en un mes a la solicitud del interesado en los términos previstos en el presente Reglamento.'
    ];
    final cards = buildLiteralCards({
      'norm': {
        'id': 'EU-example',
        'title': 'Norma europea',
        'latestVersion': 'original'
      },
      'units': [
        {
          'id': 'a',
          'title': 'Artículo 1',
          'versions': [
            {'text': paragraphs.join('\n'), 'hash': 'source'}
          ]
        }
      ],
      'format': 'cloze'
    });
    expect(cards.length, paragraphs.length);
    final answers = <String>[];
    for (final card in cards) {
      final holes =
          RegExp(r'\{\{c\d+::(.+?)\}\}').allMatches(card['front']).toList();
      expect(holes.length, inInclusiveRange(2, 3));
      answers.addAll(holes.map((h) => h.group(1)!));
    }
    expect(
        answers,
        containsAll([
          'datos personales',
          'responsable del tratamiento',
          '20 000 000 EUR',
          '4 %',
          'un mes'
        ]));
    expect(answers, isNot(contains('000 EUR')));
    expect(targetCategory('20 000 000 EUR'), 'amount');
    expect(targetCategory('4 %'), 'percentage');
    expect(targetCategory('un mes'), 'duration');
  });

  test(
      'long articles produce brief multi-target clozes and source-based expression tests',
      () {
    final text = List.generate(
            30,
            (i) =>
                '$i. El tribunal competente garantiza los derechos fundamentales mediante el procedimiento administrativo en un plazo de ${i + 1} días para las personas interesadas.')
        .join('\n');
    final unit = {
      'id': 'a1',
      'title': 'Artículo 1',
      'versions': [
        {'text': text, 'hash': 'h1', 'effectiveFrom': '20260101'}
      ]
    };
    for (final format in ['cloze', 'test']) {
      final cards = buildLiteralCards({
        'norm': {'id': 'norm', 'title': 'Norma', 'latestVersion': 'v1'},
        'units': [unit],
        'format': format
      });
      expect(cards.length, greaterThan(10));
      for (final card in cards) {
        final quote = (card['explanation'] as String)
            .split('\n\nEjercicio')
            .first
            .replaceFirst('Texto de referencia:\n', '');
        expect(quote.runes.length, lessThanOrEqualTo(320));
        if (format == 'cloze') {
          final holes =
              RegExp(r'\{\{c\d+::(.+?)\}\}').allMatches(card['front']).toList();
          expect(holes.length, inInclusiveRange(2, 3));
          for (final h in holes) {
            expect(quote, contains(h.group(1)));
          }
        } else {
          expect(card['back'], contains(' '));
          expect((card['options'] as List).toSet().length, 4);
          expect(card['options'][card['correct']], card['back']);
        }
      }
    }
  });

  testWidgets(
      'each numbered cloze accepts an answer and reveals individual feedback',
      (tester) async {
    dynamic response;
    final card = StudyCard(
        id: 'c',
        deck: 'D',
        type: 'cloze',
        front: 'El {{c1::tribunal}} protege los {{c2::derechos}}.',
        back: '1. tribunal\n2. derechos');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ExerciseInput(
                card: card, revealed: false, onChanged: (v) => response = v))));
    await tester.enterText(find.byType(TextFormField).at(0), 'tribunal');
    await tester.enterText(find.byType(TextFormField).at(1), 'leyes');
    expect(response, {'1': 'tribunal', '2': 'leyes'});
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ExerciseInput(
                card: card, revealed: true, onChanged: (v) => response = v))));
    await tester.pumpAndSettle();
    expect(find.text('Correcto'), findsOneWidget);
    expect(find.text('Respuesta: derechos'), findsOneWidget);
  });

  testWidgets(
      'prepared sheet creates interactive clozes without disposing an active field',
      (tester) async {
    final norm = {
      'id': 'sheet-law',
      'title': 'Norma breve',
      'latestVersion': 'v1',
      'packUrl':
          'https://raw.githubusercontent.com/AngelJRM01/LexMemoria/legal-corpus-20261105/boe/test.json.gz',
      'packHash': 'h'
    };
    final unit = {
      'id': 'a1',
      'title': 'Artículo 1',
      'versions': [
        {
          'text':
              'El tribunal competente garantiza los derechos fundamentales mediante el procedimiento administrativo previsto para las personas interesadas.',
          'hash': 'h',
          'effectiveFrom': '20260101'
        }
      ]
    };
    final store = AppStore(await SharedPreferences.getInstance(), {
      'norms': [norm]
    });
    store.rememberPack(norm, [unit]);
    store.preparedDecks = [
      {...norm, 'count': 1}
    ];
    await tester.pumpWidget(MaterialApp(home: PreparedDecksPage(store: store)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elegir ejercicio'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Completar huecos').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Añadir tarjetas preparadas'));
    await tester.runAsync(() async {
      final end = DateTime.now().add(const Duration(seconds: 10));
      while (store.cards.isEmpty && DateTime.now().isBefore(end)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    await tester.pumpAndSettle();
    expect(store.cards, isNotEmpty);
    expect(store.cards.first.type, 'cloze');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });

  test(
      'renewal archives unedited v1 questions while retaining edits, states and history',
      () async {
    final norm = {
      'id': 'test-norm',
      'title': 'Norma de prueba',
      'latestVersion': 'v1',
      'packUrl':
          'https://raw.githubusercontent.com/AngelJRM01/LexMemoria/legal-corpus-20261105/boe/test.json.gz',
      'packHash': 'h'
    };
    final units = List.generate(
        2,
        (i) => {
              'id': 'a$i',
              'title': 'Artículo ${i + 1}',
              'versions': [
                {
                  'text':
                      'Los derechos fundamentales y las garantías constitucionales protegen la libertad personal mediante procedimientos administrativos.',
                  'hash': 'h$i',
                  'effectiveFrom': '20260101'
                }
              ]
            });
    String oldId(int i) => const Uuid().v5(
        '6ba7b811-9dad-11d1-80b4-00c04fd430c8',
        'lexmemoria:test-norm:v1:a$i:0:cloze-v1');
    final store = AppStore(await SharedPreferences.getInstance(), {
      'norms': [norm],
      'cards': [
        StudyCard(
                id: oldId(0),
                deck: 'D',
                front: 'Anterior',
                back: 'derechos',
                type: 'cloze',
                editorialState: 'source_literal')
            .toJson(),
        StudyCard(
                id: oldId(1),
                deck: 'D',
                front: 'Mi edición',
                back: 'derechos',
                type: 'cloze',
                editorialState: 'source_literal',
                revision: 2)
            .toJson()
      ],
      'session': {
        'ids': [oldId(1)],
        'index': 0
      },
      'states': {
        oldId(0): {'repetitions': 7}
      },
      'reviews': [
        {'cardId': oldId(0), 'rating': 3}
      ]
    });
    store.rememberPack(norm, units);
    final count = await store.installPreparedDeck(norm, format: 'cloze');
    expect(count, greaterThan(0));
    expect(store.cards.any((c) => c.id == oldId(0)), isFalse);
    expect(store.cards.any((c) => c.front == 'Mi edición'), isTrue);
    expect(store.list('supersededPreparedCards').single['id'], oldId(0));
    expect(store.state(oldId(0))['repetitions'], 7);
    expect(store.data['session']['ids'], [oldId(1)]);
    expect(store.list('reviews').length, 1);
    expect(jsonDecode(store.export())['data']['supersededPreparedCards'],
        isNotEmpty);
    expect(await store.installPreparedDeck(norm, format: 'cloze'), 0);
    store.dispose();
  });
}
