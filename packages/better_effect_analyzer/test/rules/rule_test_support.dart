import 'package:analyzer_testing/analysis_rule/analysis_rule.dart';

const _betterEffectFlutterSource = r'''
library;

import 'package:better_effect/better_effect.dart';
import 'package:flutter/widgets.dart';

export 'package:better_effect/better_effect.dart';

abstract interface class EffectCommandDisposable {
  bool get isDisposed;
  void dispose();
}

abstract class EffectCommandBase<A extends Object, E extends Object>
    implements EffectCommandDisposable {}

final class EffectCommand0<A extends Object, E extends Object>
    extends EffectCommandBase<A, E> {
  EffectCommand0();
}

final class EffectCommand<I, A extends Object, E extends Object>
    extends EffectCommandBase<A, E> {
  EffectCommand();
}

final class EffectCommands {
  EffectCommand0<A, E> call<A extends Object, E extends Object>(
    Effect<A, E> Function() action,
  ) => EffectCommand0<A, E>();

  EffectCommand<I, A, E> withInput<I, A extends Object, E extends Object>(
    Effect<A, E> Function(I input) action,
  ) => EffectCommand<I, A, E>();
}

mixin EffectCommandOwner on ChangeNotifier {
  T ownCommand<T extends EffectCommandDisposable>(T command) => command;
}

abstract class EffectViewModel extends ChangeNotifier
    with EffectCommandOwner {
  EffectViewModel([EffectCommands? commands])
    : commands = commands ?? EffectCommands();
  final EffectCommands commands;

  EffectCommand0<A, E> command<A extends Object, E extends Object>(
    Effect<A, E> Function() action,
  ) => ownCommand(commands<A, E>(action));

  EffectCommand<I, A, E>
  commandWithInput<I, A extends Object, E extends Object>(
    Effect<A, E> Function(I input) action,
  ) => ownCommand(commands.withInput<I, A, E>(action));
}

final class BetterEffectProvider extends Widget {
  BetterEffectProvider({required Runtime runtime, required Widget child});
  BetterEffectProvider.value({required Runtime runtime, required Widget child});
}

final class BetterEffectBootstrap extends Widget {
  BetterEffectBootstrap({required Module module, required Widget child});
}

Future<void> runBetterEffectApp({
  required Module module,
  required Widget app,
}) async {}

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
    required FutureOr<void> Function(R, Object) release,
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

sealed class Exit<A extends Object, E extends Object> {}

abstract interface class EffectExecution<A extends Object, E extends Object> {
  Future<Exit<A, E>> get exit;
}

final class Runtime {
  Future<void> close() async {}
  bool get isClosed => false;
  Object get state => Object();

  EffectExecution<A, E> execute<A extends Object, E extends Object>(
    Effect<A, E> effect,
  ) => throw UnimplementedError();
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
    required FutureOr<void> Function(T, Object) release,
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
  factory Module.complete(Iterable<Binding> bindings) => Module(bindings);
  factory Module.merge(Iterable<Module> modules) => Module(const []);
  Module overrideWith(Iterable<Binding> overrides) => this;
  Future<Runtime> start() async => Runtime();
}
''';

const _flutterWidgetsSource = r'''
library;

abstract interface class Listenable {}

class ChangeNotifier implements Listenable {
  void dispose() {}
}

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
