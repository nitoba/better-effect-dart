import 'package:better_effect_flutter/better_effect_flutter.dart';

/// Return a successful Command value or throw a descriptive test exception.
A expectCommandSuccess<A extends Object, E extends Object>(
  EffectCommandState<A, E> state,
) {
  return switch (state) {
    EffectCommandSuccess<A, E>(:final value) => value,
    _ => throw EffectCommandTestExpectationException(
      expected: 'EffectCommandSuccess<$A, $E>',
      actual: state,
    ),
  };
}

/// Return a typed Command failure or throw a descriptive test exception.
E expectCommandFailure<A extends Object, E extends Object>(
  EffectCommandState<A, E> state,
) {
  return switch (state) {
    EffectCommandFailure<A, E>(:final error) => error,
    _ => throw EffectCommandTestExpectationException(
      expected: 'EffectCommandFailure<$A, $E>',
      actual: state,
    ),
  };
}

/// Return a Command defect and stack trace or throw a test exception.
({Object defect, StackTrace stackTrace}) expectCommandDefect<
  A extends Object,
  E extends Object
>(EffectCommandState<A, E> state) {
  return switch (state) {
    EffectCommandDefect<A, E>(:final defect, :final stackTrace) => (
      defect: defect,
      stackTrace: stackTrace,
    ),
    _ => throw EffectCommandTestExpectationException(
      expected: 'EffectCommandDefect<$A, $E>',
      actual: state,
    ),
  };
}

EffectCommandIdle<A, E> expectCommandIdle<A extends Object, E extends Object>(
  EffectCommandState<A, E> state,
) {
  if (state is EffectCommandIdle<A, E>) return state;
  throw EffectCommandTestExpectationException(
    expected: 'EffectCommandIdle<$A, $E>',
    actual: state,
  );
}

EffectCommandRunning<A, E> expectCommandRunning<
  A extends Object,
  E extends Object
>(EffectCommandState<A, E> state) {
  if (state is EffectCommandRunning<A, E>) return state;
  throw EffectCommandTestExpectationException(
    expected: 'EffectCommandRunning<$A, $E>',
    actual: state,
  );
}

EffectCommandInterrupted<A, E> expectCommandInterrupted<
  A extends Object,
  E extends Object
>(EffectCommandState<A, E> state) {
  if (state is EffectCommandInterrupted<A, E>) return state;
  throw EffectCommandTestExpectationException(
    expected: 'EffectCommandInterrupted<$A, $E>',
    actual: state,
  );
}

final class EffectCommandTestExpectationException implements Exception {
  const EffectCommandTestExpectationException({
    required this.expected,
    required this.actual,
  });

  final String expected;
  final Object actual;

  @override
  String toString() => 'Expected $expected, but received $actual.';
}
