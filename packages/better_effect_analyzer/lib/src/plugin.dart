import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'fixes/lifecycle_fixes.dart';
import 'rules/closed_runtime_exposed.dart';
import 'rules/discarded_effect.dart';
import 'rules/discarded_effect_execution.dart';
import 'rules/duplicate_service_binding.dart';
import 'rules/effect_command_not_owned.dart';
import 'rules/incompatible_provider.dart';
import 'rules/missing_binding_type_argument.dart';
import 'rules/module_root_not_complete.dart';
import 'rules/repository_requests_repository.dart';
import 'rules/runtime_started_without_close.dart';
import 'rules/singleton_viewmodel.dart';
import 'rules/unawaited_effect_context_operation.dart';
import 'rules/viewmodel_requests_service.dart';
import 'rules/widget_requests_business_dependency.dart';

/// The official Dart Analysis Server plugin for better_effect.
final class BetterEffectAnalyzerPlugin extends Plugin {
  @override
  String get name => 'better_effect_analyzer';

  @override
  void register(PluginRegistry registry) {
    // Correctness rules are warnings and are enabled as soon as the plugin is
    // enabled in the top-level analysis_options.yaml.
    registry
      ..registerWarningRule(DiscardedEffectRule())
      ..registerWarningRule(DiscardedEffectExecutionRule())
      ..registerWarningRule(RuntimeStartedWithoutCloseRule())
      ..registerWarningRule(UnawaitedEffectContextOperationRule())
      ..registerWarningRule(MissingBindingTypeArgumentRule())
      ..registerWarningRule(IncompatibleProviderRule())
      ..registerWarningRule(DuplicateServiceBindingRule())
      // Architecture and conservative migration rules are opt-in because not
      // every Dart or Flutter project follows the same ownership conventions.
      ..registerLintRule(EffectCommandNotOwnedRule())
      ..registerLintRule(ClosedRuntimeExposedRule())
      ..registerLintRule(ModuleRootNotCompleteRule())
      ..registerLintRule(RepositoryRequestsRepositoryRule())
      ..registerLintRule(ViewModelRequestsServiceRule())
      ..registerLintRule(WidgetRequestsBusinessDependencyRule())
      ..registerLintRule(SingletonViewModelRule())
      // Safe, local transformations only. Architectural code is not generated
      // when ownership cannot be inferred.
      ..registerFixForRule(
        DiscardedEffectExecutionRule.code,
        AwaitDiscardedExecutionFix.new,
      )
      ..registerFixForRule(
        DiscardedEffectExecutionRule.code,
        ReturnDiscardedExecutionFix.new,
      )
      ..registerFixForRule(
        RuntimeStartedWithoutCloseRule.code,
        WrapRuntimeInTryFinallyFix.new,
      )
      ..registerFixForRule(
        EffectCommandNotOwnedRule.code,
        OwnEffectCommandFix.new,
      )
      ..registerFixForRule(
        ModuleRootNotCompleteRule.code,
        ConvertToCompleteModuleFix.new,
      );
  }
}
