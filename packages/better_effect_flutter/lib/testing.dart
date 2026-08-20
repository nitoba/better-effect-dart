/// Test support for `package:better_effect_flutter`.
///
/// This entrypoint re-exports core testing helpers and adds deterministic
/// Command-state, listener-delivery, and widget-boundary utilities.
library;

export 'package:better_effect/testing.dart';
export 'better_effect_flutter.dart';
export 'src/testing/better_effect_test_app.dart';
export 'src/testing/effect_command_listener_probe.dart';
export 'src/testing/effect_command_probe.dart';
export 'src/testing/effect_command_state_assertions.dart';
