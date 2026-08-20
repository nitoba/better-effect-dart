/// Test support for `package:better_effect`.
///
/// Import this library from test code instead of the main entrypoint when you
/// need Runtime harnesses, deterministic gates, event recording, Exit matchers,
/// or backend contract verification.
library;

export 'better_effect.dart';
export 'src/testing/exit_matchers.dart';
export 'src/testing/manual_effect_clock.dart';
export 'src/testing/recording_runtime_observer.dart';
export 'src/testing/resolver_backend_contract.dart';
export 'src/testing/test_primitives.dart';
export 'src/testing/test_runtime.dart';
