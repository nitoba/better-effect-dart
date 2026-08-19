import 'package:better_effect_analyzer/src/rules/repository_requests_repository.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import 'rule_test_support.dart';

void main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(RepositoryRequestsRepositoryTest);
  });
}

@reflectiveTest
final class RepositoryRequestsRepositoryTest extends BetterEffectRuleTest {
  @override
  void setUp() {
    rule = RepositoryRequestsRepositoryRule();
    super.setUp();
  }

  Future<void> test_reportsCrossRepositoryRequest() async {
    const source = r'''
import 'package:better_effect/better_effect.dart';

final class AppFailure implements Exception {}
abstract interface class UserRepository {}
abstract interface class BookingRepository {}

final class BookingRepositoryLive implements BookingRepository {
  Effect<int, AppFailure> load() => .result((use) async {
    final users = use<UserRepository>();
    return users.hashCode;
  });
}
''';

    final offset = source.indexOf('use<UserRepository>()');
    await assertDiagnostics(source, [
      lint(offset, 'use<UserRepository>()'.length),
    ]);
  }

  Future<void> test_reportsDotShorthandStaticServiceRequest() async {
    const source = r'''
import 'package:better_effect/better_effect.dart';

abstract interface class UserRepository {}
abstract interface class BookingRepository {}

final class BookingRepositoryLive implements BookingRepository {
  Effect<UserRepository, Never> dependency() => .service<UserRepository>();
}
''';

    final offset = source.indexOf('.service<UserRepository>()');
    await assertDiagnostics(source, [
      lint(offset, '.service<UserRepository>()'.length),
    ]);
  }

  Future<void> test_allowsOwnRepositoryContractRequest() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect/better_effect.dart';

final class AppFailure implements Exception {}
abstract interface class UserRepository {}

final class UserRepositoryLive implements UserRepository {
  Effect<int, AppFailure> load() => .result((use) async {
    final decorated = use<UserRepository>();
    return decorated.hashCode;
  });
}
''');
  }

  Future<void> test_allowsServiceRequestFromRepository() async {
    await assertNoDiagnostics(r'''
import 'package:better_effect/better_effect.dart';

final class AppFailure implements Exception {}
abstract interface class BookingApiClient {}
abstract interface class BookingRepository {}

final class BookingRepositoryLive implements BookingRepository {
  Effect<int, AppFailure> load() => .result((use) async {
    final api = use<BookingApiClient>();
    return api.hashCode;
  });
}
''');
  }
}
