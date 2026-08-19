import 'package:better_effect_analyzer/src/rules/viewmodel_requests_service.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'rule_test_support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(ViewModelRequestsServiceTest);
  });
}

@reflectiveTest
final class ViewModelRequestsServiceTest extends BetterEffectRuleTest {
  @override
  void setUp() {
    rule = ViewModelRequestsServiceRule();
    super.setUp();
  }

  Future<void> test_reportsLowLevelServiceRequest() async {
    const source = r'''
import 'package:better_effect_flutter/better_effect_flutter.dart';

final class AppFailure implements Exception {}
abstract interface class HomeApiClient {}

final class HomeViewModel extends EffectViewModel {
  Effect<int, AppFailure> load() => .result((use) async {
    final api = use<HomeApiClient>();
    return api.hashCode;
  });
}
''';

    final offset = source.indexOf('use<HomeApiClient>()');
    await assertDiagnostics(source, [
      lint(offset, 'use<HomeApiClient>()'.length),
    ]);
  }

  Future<void> test_reportsDotShorthandStaticServiceRequest() async {
    const source = r'''
import 'package:better_effect_flutter/better_effect_flutter.dart';

abstract interface class HomeApiClient {}

final class HomeViewModel extends EffectViewModel {
  Effect<HomeApiClient, Never> dependency() => .service<HomeApiClient>();
}
''';

    final offset = source.indexOf('.service<HomeApiClient>()');
    await assertDiagnostics(source, [
      lint(offset, '.service<HomeApiClient>()'.length),
    ]);
  }

  Future<void> test_allowsRepositoryRequest() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect_flutter/better_effect_flutter.dart';

final class AppFailure implements Exception {}
abstract interface class HomeRepository {}

final class HomeViewModel extends EffectViewModel {
  Effect<int, AppFailure> load() => .result((use) async {
    final repository = use<HomeRepository>();
    return repository.hashCode;
  });
}
''');
  }
}
