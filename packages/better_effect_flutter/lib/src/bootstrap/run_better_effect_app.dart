part of '../../better_effect_flutter.dart';

/// Starts an application-owned better_effect Runtime and mounts Flutter.
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
Future<void> runBetterEffectApp({
  required Module module,
  required Widget app,
  ResolverBackend? backend,
  EffectCommandObserver? observer,
  EffectCommandPolicyObserver? policyObserver,
  BetterEffectLifecyclePolicy lifecyclePolicy =
      const BetterEffectLifecyclePolicy.application(),
  @Deprecated(
    'Use lifecyclePolicy.closeOnApplicationExit. '
    'This compatibility parameter will be removed before 1.0.',
  )
  bool? closeRuntimeOnDetach,
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

  final effectivePolicy = BetterEffectLifecyclePolicy(
    closeOnWidgetDispose: lifecyclePolicy.closeOnWidgetDispose,
    closeOnApplicationExit:
        closeRuntimeOnDetach ?? lifecyclePolicy.closeOnApplicationExit,
    interruptExecutionsBeforeClose:
        lifecyclePolicy.interruptExecutionsBeforeClose,
    gracePeriod: lifecyclePolicy.gracePeriod,
  );

  try {
    runApp(
      BetterEffectProvider(
        runtime: runtime,
        observer: observer,
        policyObserver: policyObserver,
        ownership: BetterEffectRuntimeOwnership.application,
        lifecyclePolicy: effectivePolicy,
        onRuntimeCloseError: onRuntimeCloseError,
        child: app,
      ),
    );
  } catch (error, stackTrace) {
    await _BetterEffectCloseConfiguration(
      policy: effectivePolicy,
      onError: onRuntimeCloseError,
      ownerDescription: 'a Runtime after runApp failed',
    ).close(runtime);

    Error.throwWithStackTrace(error, stackTrace);
  }
}

/// Builds a fallback root when the application Runtime cannot start.
typedef BetterEffectStartupErrorBuilder =
    Widget Function(Object error, StackTrace stackTrace);
