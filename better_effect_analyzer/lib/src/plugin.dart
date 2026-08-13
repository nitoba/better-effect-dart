import 'package:analysis_server_plugin/plugin.dart';
import 'package:analysis_server_plugin/registry.dart';

import 'rules/discarded_effect.dart';
import 'rules/duplicate_service_binding.dart';
import 'rules/incompatible_provider.dart';
import 'rules/missing_binding_type_argument.dart';
import 'rules/repository_requests_repository.dart';
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
      ..registerWarningRule(UnawaitedEffectContextOperationRule())
      ..registerWarningRule(MissingBindingTypeArgumentRule())
      ..registerWarningRule(IncompatibleProviderRule())
      ..registerWarningRule(DuplicateServiceBindingRule())
      // Architecture rules are opt-in because not every Dart or Flutter project
      // follows the same layering conventions.
      ..registerLintRule(RepositoryRequestsRepositoryRule())
      ..registerLintRule(ViewModelRequestsServiceRule())
      ..registerLintRule(WidgetRequestsBusinessDependencyRule())
      ..registerLintRule(SingletonViewModelRule());
  }
}
