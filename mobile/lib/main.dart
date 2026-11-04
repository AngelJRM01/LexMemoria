import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'store.dart';
import 'shell.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final store = await AppStore.load();
    runApp(LexMemoria(store: store));
  } catch (_) {
    runApp(const MaterialApp(home: Scaffold(body: Center(child: Padding(
      padding: EdgeInsets.all(32), child: Text('No se han podido leer los datos locales. No se han borrado. Conserva los datos de la aplicación y contacta con soporte antes de restablecerla.'))))));
  }
}

class LexMemoria extends StatelessWidget {
  final AppStore store;
  const LexMemoria({super.key, required this.store});
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: store, builder: (context, _) {
    ThemeData theme(Brightness brightness) {
      final dark = brightness == Brightness.dark;
      final scheme = ColorScheme.fromSeed(seedColor: const Color(0xff17365d), brightness: brightness,
        primary: dark ? const Color(0xffa8c8f2) : const Color(0xff17365d),
        secondary: const Color(0xff0e9f91), surface: dark ? const Color(0xff101c2b) : const Color(0xfff8fafc));
      return ThemeData(useMaterial3: true, colorScheme: scheme, scaffoldBackgroundColor: scheme.surface,
        appBarTheme: AppBarTheme(backgroundColor: scheme.surface, centerTitle: false),
        inputDecorationTheme: InputDecorationTheme(filled: true, fillColor: dark ? const Color(0xff1e2b3c) : Colors.white,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xffdfe5ed)))),
        filledButtonTheme: FilledButtonThemeData(style: FilledButton.styleFrom(minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)))),
        textTheme: ThemeData(brightness: brightness).textTheme.copyWith(
          headlineLarge: TextStyle(fontSize: 34, fontWeight: FontWeight.w700, letterSpacing: -1, color: scheme.primary),
          headlineMedium: TextStyle(fontSize: 27, fontWeight: FontWeight.w700, letterSpacing: -.7, color: scheme.primary),
          titleLarge: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: scheme.primary),
          bodyLarge: const TextStyle(fontSize: 17, height: 1.6), bodyMedium: const TextStyle(fontSize: 15, height: 1.5)));
    }
    return MaterialApp(title: 'LexMemoria', debugShowCheckedModeBanner: false,
      locale: const Locale('es'), supportedLocales: const [Locale('es')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: theme(Brightness.light), darkTheme: theme(Brightness.dark),
      themeMode: store.dark ? ThemeMode.dark : ThemeMode.light,
      home: store.onboarded ? AppShell(store: store) : WelcomePage(store: store));
  });
}
