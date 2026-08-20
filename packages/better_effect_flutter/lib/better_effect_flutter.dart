/// Flutter MVVM integration for `better_effect`.
///
/// The Dart-only core is re-exported so applications normally need one import:
///
/// ```dart
/// import 'package:better_effect_flutter/better_effect_flutter.dart';
/// ```
library;

import 'dart:async';
import 'dart:collection';
import 'dart:ui' show AppExitResponse;

import 'package:better_effect/better_effect.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

export 'package:better_effect/better_effect.dart';

part 'src/bootstrap/run_better_effect_app.dart';
part 'src/command/command_policy.dart';
part 'src/command/effect_command.dart';
part 'src/command/effect_command_concurrency.dart';
part 'src/command/effect_command_state.dart';
part 'src/command/effect_command_transition.dart';
part 'src/command/effect_commands.dart';
part 'src/context/build_context_extensions.dart';
part 'src/scope/better_effect_bootstrap.dart';
part 'src/scope/better_effect_lifecycle.dart';
part 'src/scope/better_effect_provider.dart';
part 'src/scope/better_effect_scope.dart';
part 'src/view_model/effect_command_owner.dart';
part 'src/view_model/effect_view_model.dart';
part 'src/view_model/effect_view_model_builder.dart';
part 'src/widgets/effect_command_builder.dart';
part 'src/widgets/effect_command_consumer.dart';
part 'src/widgets/effect_command_listener.dart';
