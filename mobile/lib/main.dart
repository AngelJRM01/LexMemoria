import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'store.dart';
import 'shell.dart';
import 'startup.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const AppBootstrap());
}

class AppBootstrap extends StatefulWidget {
  final Future<AppStore> Function()? storeLoader;
  const AppBootstrap({super.key, this.storeLoader});
  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  late Future<AppStore> loading;
  @override
  void initState() {
    super.initState();
    loading = load();
  }

  Future<AppStore> load() => widget.storeLoader?.call() ?? AppStore.load();
  @override
  Widget build(BuildContext context) => FutureBuilder<AppStore>(
      future: loading,
      builder: (context, snapshot) {
        if (snapshot.hasData) return LexMemoria(store: snapshot.data!);
        final error = snapshot.error;
        final code = error is StartupFailure ? error.code : 'STARTUP_UNKNOWN';
        const mode = kReleaseMode
            ? 'release'
            : kProfileMode
                ? 'profile'
                : 'debug';
        final diagnostic = 'LexMemoria 0.4.1+7 · $mode · $code';
        return MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
                body: SafeArea(
                    child: Center(
              child: SingleChildScrollView(
                  padding: const EdgeInsets.all(28),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 560),
                    child: snapshot.hasError
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                const Icon(Icons.lock_outline, size: 40),
                                const SizedBox(height: 20),
                                const Text('No se ha podido iniciar LexMemoria',
                                    style: TextStyle(
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 16),
                                const Text(
                                    'No se han borrado tus datos. No desinstales la aplicación ni borres su almacenamiento. Puedes reintentar o compartir este código para diagnosticar el problema.'),
                                const SizedBox(height: 16),
                                SelectableText(diagnostic),
                                const SizedBox(height: 24),
                                Wrap(spacing: 12, runSpacing: 12, children: [
                                  FilledButton(
                                      onPressed: () => setState(() {
                                            loading = load();
                                          }),
                                      child: const Text('Reintentar')),
                                  OutlinedButton(
                                      onPressed: () => Clipboard.setData(
                                          ClipboardData(text: diagnostic)),
                                      child: const Text('Copiar diagnóstico')),
                                ]),
                              ])
                        : const Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 20),
                                Text('Abriendo tu espacio de estudio…')
                              ]),
                  )),
            ))));
      });
}

class LexMemoria extends StatelessWidget {
  final AppStore store;
  const LexMemoria({super.key, required this.store});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        ThemeData theme(Brightness brightness) {
          final dark = brightness == Brightness.dark;
          final scheme = ColorScheme.fromSeed(
              seedColor: const Color(0xff17365d),
              brightness: brightness,
              primary: dark ? const Color(0xffa8c8f2) : const Color(0xff17365d),
              secondary: const Color(0xff0e9f91),
              surface:
                  dark ? const Color(0xff101c2b) : const Color(0xfff8fafc));
          return ThemeData(
              useMaterial3: true,
              colorScheme: scheme,
              scaffoldBackgroundColor: scheme.surface,
              appBarTheme: AppBarTheme(
                  backgroundColor: scheme.surface, centerTitle: false),
              inputDecorationTheme: InputDecorationTheme(
                  filled: true,
                  fillColor: dark ? const Color(0xff1e2b3c) : Colors.white,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xffdfe5ed)))),
              filledButtonTheme: FilledButtonThemeData(
                  style: FilledButton.styleFrom(
                      minimumSize: const Size(48, 52),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)))),
              textTheme: ThemeData(brightness: brightness).textTheme.copyWith(
                  headlineLarge: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -1,
                      color: scheme.primary),
                  headlineMedium: TextStyle(
                      fontSize: 27,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.7,
                      color: scheme.primary),
                  titleLarge: TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                      color: scheme.primary),
                  bodyLarge: const TextStyle(fontSize: 17, height: 1.6),
                  bodyMedium: const TextStyle(fontSize: 15, height: 1.5)));
        }

        return MaterialApp(
            title: 'LexMemoria',
            debugShowCheckedModeBanner: false,
            locale: const Locale('es'),
            supportedLocales: const [Locale('es')],
            localizationsDelegates: GlobalMaterialLocalizations.delegates,
            theme: theme(Brightness.light),
            darkTheme: theme(Brightness.dark),
            themeMode: store.dark ? ThemeMode.dark : ThemeMode.light,
            home: store.onboarded
                ? AppShell(store: store)
                : WelcomePage(store: store));
      });
}
