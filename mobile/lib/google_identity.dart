import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'remote.dart';
import 'store.dart';

abstract interface class GoogleIdentity {
  bool get available;

  /// A Firebase ID token (not the raw Google token); null means user cancelled.
  Future<String?> authenticate();
}

abstract interface class FirebaseAccountIdentity implements GoogleIdentity {
  Future<bool> deleteAccount(
      Future<void> Function(String token, String subject) deleteBackend,
      {String? expectedSubject});
}

Future<FirebaseApp>? _identityFirebaseInitialization;
Future<FirebaseApp> initializeIdentityFirebase() async {
  try {
    final app = await (_identityFirebaseInitialization ??=
        Firebase.apps.isNotEmpty
            ? Future.value(Firebase.app())
            : Firebase.initializeApp(
                options: !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS
                    ? const FirebaseOptions(
                        apiKey: String.fromEnvironment(
                            'LEXMEMORIA_IOS_FIREBASE_API_KEY'),
                        appId: String.fromEnvironment(
                            'LEXMEMORIA_IOS_FIREBASE_APP_ID'),
                        messagingSenderId: String.fromEnvironment(
                            'LEXMEMORIA_IOS_FIREBASE_SENDER_ID'),
                        projectId: NativeGoogleIdentity.project,
                        iosBundleId: 'es.lexmemoria.app',
                        iosClientId: String.fromEnvironment(
                            'LEXMEMORIA_IOS_GOOGLE_CLIENT_ID'))
                    : null));
    if (app.options.projectId != NativeGoogleIdentity.project) {
      throw StateError(
          'La configuración de acceso no corresponde a esta aplicación.');
    }
    return app;
  } catch (_) {
    _identityFirebaseInitialization = null;
    rethrow;
  }
}

class NativeGoogleIdentity implements FirebaseAccountIdentity {
  static const configured = bool.fromEnvironment('LEXMEMORIA_GOOGLE_ENABLED');
  static const project = String.fromEnvironment(
      'LEXMEMORIA_FIREBASE_PROJECT_ID',
      defaultValue: 'lexmemoria-aa86a');
  static Future<void>? _initialization;
  @override
  bool get available =>
      configured &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          (defaultTargetPlatform == TargetPlatform.iOS &&
              NativeAppleIdentity.configured));

  Future<void> _initialize() async {
    try {
      await (_initialization ??= () async {
        await initializeIdentityFirebase();
        await GoogleSignIn.instance.initialize(
            clientId: defaultTargetPlatform == TargetPlatform.iOS
                ? const String.fromEnvironment(
                    'LEXMEMORIA_IOS_GOOGLE_CLIENT_ID')
                : null);
      }());
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  @override
  Future<String?> authenticate() => _authenticate();

  @override
  Future<bool> deleteAccount(
          Future<void> Function(String token, String subject) deleteBackend,
          {String? expectedSubject}) async =>
      await _authenticate(operation: (token, user) async {
        if (expectedSubject != null && user.uid != expectedSubject) {
          throw StateError(
              'Selecciona la misma cuenta de Google cuya eliminación quedó pendiente.');
        }
        await deleteBackend(token, user.uid);
        try {
          await user.delete();
        } catch (_) {
          throw StateError(
              'Los datos del servidor están eliminados. Vuelve a identificarte para completar la eliminación de la identidad Firebase.');
        }
      }) !=
      null;

  Future<String?> _authenticate(
      {Future<void> Function(String token, User user)? operation}) async {
    if (!available) {
      throw StateError('Google no está configurado en esta versión.');
    }
    try {
      await _initialize();
      // Always start an explicit selection; a cached provider identity alone
      // must never silently attach another local study account.
      await FirebaseAuth.instance.signOut();
      await GoogleSignIn.instance.signOut();
      final account = await GoogleSignIn.instance.authenticate();
      final googleToken = account.authentication.idToken;
      if (googleToken == null) {
        throw StateError('Google no ha completado la identificación.');
      }
      final signed = await FirebaseAuth.instance.signInWithCredential(
          GoogleAuthProvider.credential(idToken: googleToken));
      final token = await signed.user?.getIdToken(true);
      if (token == null || token.isEmpty) {
        throw StateError('No se pudo verificar el acceso. Reintenta.');
      }
      if (operation != null) await operation(token, signed.user!);
      return token;
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) return null;
      throw StateError(
          'No se pudo completar el acceso con Google. Reintenta o contacta con soporte.');
    } on FirebaseAuthException catch (error) {
      if (error.code == 'network-request-failed') {
        throw StateError(
            'No se pudo conectar con Google. Comprueba tu conexión.');
      }
      throw StateError(
          'No se pudo verificar la cuenta de Google. Reintenta o contacta con soporte.');
    } on FirebaseException {
      throw StateError(
          'El acceso con Google no está disponible en esta versión.');
    } finally {
      // LexMemoria keeps only its own backend session in its secure vault.
      // Discard temporary Firebase/provider sessions after obtaining the token.
      if (Firebase.apps.isNotEmpty) {
        try {
          await FirebaseAuth.instance.signOut();
        } catch (_) {}
      }
      if (_initialization != null) {
        try {
          await GoogleSignIn.instance.signOut();
        } catch (_) {}
      }
    }
  }
}

class NativeAppleIdentity implements FirebaseAccountIdentity {
  static const configured =
      bool.fromEnvironment('LEXMEMORIA_IOS_IDENTITY_ENABLED');
  @override
  bool get available =>
      configured && !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;
  @override
  Future<String?> authenticate() => _authenticate();

  @override
  Future<bool> deleteAccount(
          Future<void> Function(String token, String subject) deleteBackend,
          {String? expectedSubject}) async =>
      await _authenticate(operation: (token, signed) async {
        final user = signed.user!;
        if (expectedSubject != null && user.uid != expectedSubject) {
          throw StateError(
              'Selecciona la misma cuenta Apple cuya eliminación quedó pendiente.');
        }
        final authorizationCode = signed.additionalUserInfo?.authorizationCode;
        if (authorizationCode == null || authorizationCode.isEmpty) {
          throw StateError(
              'Apple no proporcionó el código para revocar el acceso. Reintenta.');
        }
        await deleteBackend(token, user.uid);
        try {
          await FirebaseAuth.instance
              .revokeTokenWithAuthorizationCode(authorizationCode);
          await user.delete();
        } catch (_) {
          throw StateError(
              'Los datos remotos se han eliminado. Vuelve a identificarte con Apple para completar la revocación y eliminación de la identidad.');
        }
      }) !=
      null;

  Future<String?> _authenticate(
      {Future<void> Function(String token, UserCredential signed)?
          operation}) async {
    if (!available) {
      throw StateError('Apple no está configurado en esta versión.');
    }
    try {
      await initializeIdentityFirebase();
      await FirebaseAuth.instance.signOut();
      final provider = AppleAuthProvider()..addScope('email');
      // FlutterFire uses native ASAuthorizationAppleIDProvider, nonce and Firebase exchange.
      final signed = await FirebaseAuth.instance.signInWithProvider(provider);
      final token = await signed.user?.getIdToken(true);
      if (token == null || token.isEmpty) {
        throw StateError('Apple no ha completado la identificación.');
      }
      if (operation != null) await operation(token, signed);
      return token;
    } on FirebaseAuthException catch (error) {
      if (['canceled', 'cancelled', 'web-context-canceled', 'user-cancelled']
          .contains(error.code)) {
        return null;
      }
      throw StateError(
          'No se pudo completar el acceso con Apple. Comprueba la conexión y reintenta.');
    } on FirebaseException {
      throw StateError(
          'El acceso con Apple no está disponible en esta configuración.');
    } finally {
      if (Firebase.apps.isNotEmpty) {
        try {
          await FirebaseAuth.instance
              .signOut()
              .timeout(const Duration(seconds: 5));
        } catch (_) {}
      }
    }
  }
}

Future<bool> connectGoogleIdentity(
    AppStore store, GoogleIdentity identity, RemoteSync remote,
    {bool confirmAccountChange = false,
    Duration authenticationTimeout = const Duration(seconds: 90),
    String provider = 'google'}) async {
  if (!['google', 'apple'].contains(provider)) {
    throw ArgumentError('Proveedor no admitido');
  }
  final label = provider == 'apple' ? 'Apple' : 'Google';
  if (!identity.available) {
    throw StateError('$label no está configurado en esta versión.');
  }
  final server = store.apiBase;
  final current = store.data['remoteUserId'];
  final owner = store.data['localDataOwnerId'];
  final token = await identity.authenticate().timeout(authenticationTimeout,
      onTimeout: () => throw TimeoutException(
          '$label no ha terminado el acceso. Reintenta; no se han enviado tus datos de estudio.'));
  if (token == null) return false;
  if (store.apiBase != server ||
      store.data['remoteUserId'] != current ||
      store.data['localDataOwnerId'] != owner) {
    throw StateError(
        'La cuenta o el servidor ha cambiado. Inicia el acceso de nuevo.');
  }
  await remote.connectGoogle(token,
      confirmAccountChange: confirmAccountChange, provider: provider);
  return true;
}
