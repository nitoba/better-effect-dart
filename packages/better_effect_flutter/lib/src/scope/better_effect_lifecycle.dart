part of '../../better_effect_flutter.dart';

/// Declares who owns a Runtime placed in the Flutter tree.
enum BetterEffectRuntimeOwnership {
  /// Another boundary owns the Runtime and this widget must never close it.
  external,

  /// The widget owns the Runtime until disposal or intentional replacement.
  widget,

  /// The application root owns the Runtime and also coordinates exit events.
  application,
}

/// Controls when and how an owned Runtime shuts down.
final class BetterEffectLifecyclePolicy {
  const BetterEffectLifecyclePolicy({
    this.closeOnWidgetDispose = true,
    this.closeOnApplicationExit = true,
    this.interruptExecutionsBeforeClose = true,
    this.gracePeriod = Duration.zero,
  });

  /// A policy for externally owned Runtimes.
  const BetterEffectLifecyclePolicy.external()
    : closeOnWidgetDispose = false,
      closeOnApplicationExit = false,
      interruptExecutionsBeforeClose = false,
      gracePeriod = Duration.zero;

  /// A policy for Runtimes owned only by one widget subtree.
  const BetterEffectLifecyclePolicy.widget({
    this.interruptExecutionsBeforeClose = true,
    this.gracePeriod = Duration.zero,
  }) : closeOnWidgetDispose = true,
       closeOnApplicationExit = false;

  /// The default policy for an application root Runtime.
  const BetterEffectLifecyclePolicy.application({
    this.closeOnWidgetDispose = true,
    this.closeOnApplicationExit = true,
    this.interruptExecutionsBeforeClose = true,
    this.gracePeriod = Duration.zero,
  });

  /// Close an owned Runtime when its widget owner leaves the tree.
  final bool closeOnWidgetDispose;

  /// Close an application-owned Runtime for exit requests and host detach.
  ///
  /// Cancelable exit requests are available on supported desktop platforms.
  /// Flutter's detach callback is currently specific to iOS and Android.
  final bool closeOnApplicationExit;

  /// Ask active Effects to stop cooperatively after [gracePeriod].
  final bool interruptExecutionsBeforeClose;

  /// Time to drain active work before cooperative interruption is requested.
  ///
  /// Negative values are rejected by [Runtime.close] when shutdown begins.
  final Duration gracePeriod;
}

final class _BetterEffectCloseConfiguration {
  const _BetterEffectCloseConfiguration({
    required this.policy,
    required this.onError,
    required this.ownerDescription,
  });

  final BetterEffectLifecyclePolicy policy;
  final void Function(Object error, StackTrace stackTrace)? onError;
  final String ownerDescription;

  Future<void> close(Runtime runtime) async {
    try {
      await runtime.close(
        gracePeriod: policy.gracePeriod,
        interruptAfterGracePeriod: policy.interruptExecutionsBeforeClose,
      );
    } catch (error, stackTrace) {
      final handler = onError;
      if (handler != null) {
        try {
          handler(error, stackTrace);
        } catch (handlerError, handlerStackTrace) {
          FlutterError.reportError(
            FlutterErrorDetails(
              exception: handlerError,
              stack: handlerStackTrace,
              library: 'better_effect_flutter',
              context: ErrorDescription(
                'while reporting a failure closing $ownerDescription',
              ),
              informationCollector: () sync* {
                yield ErrorDescription('Original close failure: $error');
              },
            ),
          );
        }
        return;
      }

      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'better_effect_flutter',
          context: ErrorDescription('while closing $ownerDescription'),
        ),
      );
    }
  }
}
