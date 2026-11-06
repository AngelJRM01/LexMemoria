import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/models.dart';
import 'package:lexmemoria/store.dart';
import 'package:lexmemoria/persistence.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('profile real catalogue and repeated card access', () async {
    SharedPreferences.setMockInitialValues({});
    final clock = Stopwatch()..start();
    final s = await AppStore.load(
        persistence:
            PreferencesPersistence(await SharedPreferences.getInstance()));
    final startup = clock.elapsedMicroseconds;
    s.data['cards'] = List.generate(
        20000,
        (i) => StudyCard(
                id: 'c$i', deck: 'D', front: 'Pregunta', back: 'Respuesta')
            .toJson());
    clock.reset();
    final initial = s.catalogue;
    final coldCatalogue = clock.elapsedMicroseconds;
    clock.reset();
    for (var i = 0; i < 100; i++) {
      expect(s.catalogue.length, initial.length);
    }
    final catalogueReads = clock.elapsedMicroseconds;
    clock.reset();
    for (var i = 0; i < 20; i++) {
      expect(s.cards.length, 20000);
    }
    final cardReads = clock.elapsedMicroseconds;
    for (final norm in s.bundledNorms.take(4)) {
      await s.downloadNorm(norm);
    }
    clock.reset();
    final reopened =
        await AppStore.load(persistence: PreferencesPersistence(s.prefs));
    final reopenTime = clock.elapsedMicroseconds;
    final openedPacks = reopened.bundledPacks.length;
    reopened.dispose();
    final report = {
      'startupMicroseconds': startup,
      'reopenFourSavedLawsMicroseconds': reopenTime,
      'lawsDecompressedBeforeHome': openedPacks,
      'catalogueColdMicroseconds': coldCatalogue,
      'catalogue100ReadsMicroseconds': catalogueReads,
      'cards20ReadsMicroseconds': cardReads,
      'norms': initial.length,
      'cards': 20000
    };
    final output = Platform.environment['LEXMEMORIA_PROFILE_REPORT'];
    if (output != null) File(output).writeAsStringSync(jsonEncode(report));
    // The benchmark records actual getters, with no machine-dependent timing assertion.
    stdout.writeln(jsonEncode(report));
    s.dispose();
  });
}
