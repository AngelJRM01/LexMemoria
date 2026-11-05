/// Public, non-sensitive startup diagnostics. Never include keys, database
/// contents, native exception messages or credential values in the UI or logs.
class StartupFailure extends StateError {
  final String code;
  StartupFailure(this.code)
      : super('No se ha podido completar el inicio ($code).');
}

Future<T> startupStep<T>(String code, Future<T> Function() action) async {
  try {
    return await action();
  } catch (_) {
    throw StartupFailure(code);
  }
}
