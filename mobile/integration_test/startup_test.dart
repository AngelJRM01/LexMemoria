import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lexmemoria/main.dart';
import 'package:lexmemoria/store.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native encrypted store opens and retains data after reopening', (tester) async {
    // Use the actual Android/iOS plugins. Do not replace SQLCipher or Keystore
    // with preference mocks: those mocks cannot expose native startup failures.
    final first = await AppStore.load();
    final existed = first.data.containsKey('startupIntegrationProbe');
    final before = first.data['startupIntegrationProbe'];
    first.data['startupIntegrationProbe'] = 'native-reopen-probe';
    await first.save();
    await first.persistence.close();
    final reopened = await AppStore.load();
    try {
      expect(reopened.data['startupIntegrationProbe'], 'native-reopen-probe');
      expect(reopened.bundledNorms, hasLength(20));
      await tester.pumpWidget(LexMemoria(store: reopened));
      await tester.pumpAndSettle();
      expect(find.textContaining('No se ha podido iniciar'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      if (existed) {
        reopened.data['startupIntegrationProbe'] = before;
      } else {
        reopened.data.remove('startupIntegrationProbe');
      }
      await reopened.save();
      await reopened.persistence.close();
    }
  });
}
