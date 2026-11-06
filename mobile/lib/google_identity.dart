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

class NativeGoogleIdentity implements GoogleIdentity {
  static const configured = bool.fromEnvironment('LEXMEMORIA_GOOGLE_ENABLED');
  static const project = String.fromEnvironment(
      'LEXMEMORIA_FIREBASE_PROJECT_ID',
      defaultValue: 'lexmemoria-aa86a');
  static Future<void>? _initialization;
  @override
  bool get available =>
      configured && !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _initialize() async {
    try {
      await (_initialization ??= () async {
        final app = Firebase.apps.isEmpty
            ? await Firebase.initializeApp()
            : Firebase.app();
        if (app.options.projectId != project) {
          throw StateError(
              'La configuración de acceso no corresponde a esta aplicación.');
        }
        await GoogleSignIn.instance.initialize();
      }());
    } catch (_) {
      _initialization = null;
      rethrow;
    }
  }

  @override
  Future<String?> authenticate() async {
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

Future<bool> connectGoogleIdentity(
    AppStore store, GoogleIdentity identity, RemoteSync remote,
    {bool confirmAccountChange = false}) async {
  if (!identity.available) {
    throw StateError('Google no está configurado en esta versión.');
  }
  final server = store.apiBase;
  final current = store.data['remoteUserId'];
  final owner = store.data['localDataOwnerId'];
  final token = await identity.authenticate();
  if (token == null) return false;
  if (store.apiBase != server ||
      store.data['remoteUserId'] != current ||
      store.data['localDataOwnerId'] != owner) {
    throw StateError(
        'La cuenta o el servidor ha cambiado. Inicia el acceso de nuevo.');
  }
  await remote.connectGoogle(token, confirmAccountChange: confirmAccountChange);
  return true;
}
