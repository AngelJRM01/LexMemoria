import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexmemoria/collaboration.dart';
import 'package:lexmemoria/store.dart';

void main() {
  testWidgets('V1 keeps private sharing entries and removes public discovery',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = AppStore(await SharedPreferences.getInstance(), {});
    await tester.pumpWidget(MaterialApp(home: CollaborationPage(store: store)));
    expect(publicDeckPublicationEnabled, isFalse);
    expect(find.text('Explorar mazos públicos'), findsNothing);
    expect(find.text('Compartir mis mazos'), findsOneWidget);
    expect(find.text('Mazos compartidos conmigo'), findsOneWidget);
    expect(find.text('Grupos privados'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
  });
}
