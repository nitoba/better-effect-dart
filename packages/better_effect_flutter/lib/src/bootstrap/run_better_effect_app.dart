part of '../../better_effect_flutter.dart';

/// Starts a long-lived better_effect Runtime and mounts the Flutter application.
///
/// This is the shortest application bootstrap:
///
/// ```dart
/// Future<void> main() {
///   return runBetterEffectApp(
///     module: appModule,
///     app: const App(),
///   );
/// }
/// ```
///
/// The Runtime is exposed through [BetterEffectScope] and closed by
/// [BetterEffectProvider] when the root is disposed or the Flutter view detaches.
Future<void> runBetterEffectApp({
  required Module module,
  required Widget app,
  ResolverBackend? backend,
  EffectCommandObserver? observer,
  bool closeRuntimeOnDetach = true,
  BetterEffectStartupErrorBuilder? startupErrorBuilder,
  void Function(Object error, StackTrace stackTrace)? onRuntimeCloseError,
}) async {
  WidgetsFlutterBinding.ensureInitialized();

  late final Runtime runtime;

  try {
    runtime = await module.start(backend: backend);
  } catch (error, stackTrace) {
    final builder = startupErrorBuilder;
    if (builder == null) {
      Error.throwWithStackTrace(error, stackTrace);
    }

    runApp(builder(error, stackTrace));
    return;
  }

  try {
    runApp(
      BetterEffectProvider(
        runtime: runtime,
        observer: observer,
        closeRuntimeOnDetach: closeRuntimeOnDetach,
        onRuntimeCloseError: onRuntimeCloseError,
        child: app,
      ),
    );
  } catch (error, stackTrace) {
    try {
      await runtime.close();
    } catch (closeError, closeStackTrace) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: closeError,
          stack: closeStackTrace,
          library: 'better_effect_flutter',
          context: ErrorDescription(
            'while closing a Runtime after runApp failed',
          ),
        ),
      );
    }

    Error.throwWithStackTrace(error, stackTrace);
  }
}

/// Builds a fallback root when the application Runtime cannot start.
typedef BetterEffectStartupErrorBuilder =
    Widget Function(Object error, StackTrace stackTrace);
