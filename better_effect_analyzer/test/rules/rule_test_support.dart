import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';

const _betterEffectFlutterSource = r'''
library;

import 'package:better_effect/better_effect.dart';
import 'package:flutter/widgets.dart';

export 'package:better_effect/better_effect.dart';

abstract base class EffectViewModel extends ChangeNotifier {}

extension BetterEffectBuildContext on BuildContext {
  T readEffectService<T extends Object>() => throw UnimplementedError();
}
''';

const _betterEffectSource = r'''
library;

import 'dart:async';

final class ServiceKey<T extends Object> {
  const ServiceKey(this.name);
  final String name;
}

abstract interface class EffectContext<E extends Object> {
  T call<T extends Object>([ServiceKey<T>? key]);
  T service<T extends Object>([ServiceKey<T>? key]);
  Future<A> unwrap<A extends Object, F extends E>(Effect<A, F> effect);
  Future<A> result<A extends Object, F extends E>(Object source);
  Future<A> tryAsync<A extends Object, F extends E>(
    FutureOr<A> Function() operation, {
    required F Function(Exception, StackTrace) onError,
  });
  Future<R> acquire<R extends Object, F extends E>(
    Effect<R, F> acquisition, {
    required FutureOr<void> Function(R) release,
  });
  Never fail<F extends E>(F error);
}

typedef EffectBody<A extends Object, E extends Object> = FutureOr<A> Function(
  EffectContext<E> use,
);

final class Effect<A extends Object, E extends Object> {
  const Effect._();

  factory Effect.result(EffectBody<A, E> body) => Effect<A, E>._();
  factory Effect.succeed(A value) => Effect<A, E>._();
  factory Effect.fail(E error) => Effect<A, E>._();

  static Effect<T, Never> service<T extends Object>([
    ServiceKey<T>? key,
  ]) => Effect<T, Never>._();
}

enum Lifetime { factory, singleton, lazySingleton }

sealed class Binding {
  const Binding();

  static Binding provide<T extends Object>(
    Function constructor, {
    Lifetime lifetime = Lifetime.lazySingleton,
    ServiceKey<T>? key,
  }) => const _Binding();

  static Binding factory<T extends Object>(
    Function constructor, {
    ServiceKey<T>? key,
  }) => const _Binding();

  static Binding singleton<T extends Object>(
    Function constructor, {
    ServiceKey<T>? key,
  }) => const _Binding();

  static Binding lazySingleton<T extends Object>(
    Function constructor, {
    ServiceKey<T>? key,
  }) => const _Binding();

  static Binding instance<T extends Object>(
    T value, {
    ServiceKey<T>? key,
  }) => const _Binding();

  static Binding resource<T extends Object>({
    required FutureOr<T> Function(Services) acquire,
    required FutureOr<void> Function(T) release,
    ServiceKey<T>? key,
  }) => const _Binding();
}

final class _Binding extends Binding {
  const _Binding();
}

final class Services {
  T call<T extends Object>([ServiceKey<T>? key]) => throw UnimplementedError();
  T get<T extends Object>([ServiceKey<T>? key]) => throw UnimplementedError();
}

final class Module {
  Module(Iterable<Binding> bindings);
  factory Module.merge(Iterable<Module> modules) => Module(const []);
  Module overrideWith(Iterable<Binding> overrides) => this;
}
''';

const _flutterWidgetsSource = r'''
library;

abstract interface class Listenable {}

class ChangeNotifier implements Listenable {}

abstract class BuildContext {}

abstract class Widget {}

abstract class StatelessWidget extends Widget {
  Widget build(BuildContext context);
}

abstract class StatefulWidget extends Widget {}

abstract class State<T extends StatefulWidget> {
  Widget build(BuildContext context);
}
''';

abstract class BetterEffectRuleTest extends AnalysisRuleTest {
  @override
  void setUp() {
    newPackage(
      'better_effect',
    ).addFile('lib/better_effect.dart', _betterEffectSource);

    newPackage('flutter').addFile('lib/widgets.dart', _flutterWidgetsSource);

    newPackage(
      'better_effect_flutter',
    ).addFile('lib/better_effect_flutter.dart', _betterEffectFlutterSource);

    super.setUp();
  }
}
