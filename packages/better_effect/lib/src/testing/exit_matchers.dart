import 'package:better_effect/better_effect.dart';
import 'package:matcher/matcher.dart';

/// Match an [ExitSuccess] with optional value matching.
Matcher isExitSuccess<A extends Object, E extends Object>([
  Object? value = _unspecified,
]) {
  return _TypedExitMatcher<A, E>(
    kind: _ExitKind.success,
    payload: identical(value, _unspecified) ? null : wrapMatcher(value),
  );
}

/// Match an [ExitFailure] with optional typed-error matching.
Matcher isExitFailure<A extends Object, E extends Object>([
  Object? error = _unspecified,
]) {
  return _TypedExitMatcher<A, E>(
    kind: _ExitKind.failure,
    payload: identical(error, _unspecified) ? null : wrapMatcher(error),
  );
}

/// Match an [ExitDefect] with optional defect matching.
Matcher isExitDefect<A extends Object, E extends Object>([
  Object? defect = _unspecified,
]) {
  return _TypedExitMatcher<A, E>(
    kind: _ExitKind.defect,
    payload: identical(defect, _unspecified) ? null : wrapMatcher(defect),
  );
}

/// Match an [ExitInterrupted].
Matcher isExitInterrupted<A extends Object, E extends Object>() {
  return _TypedExitMatcher<A, E>(kind: _ExitKind.interrupted);
}

/// Extract a successful value or throw an assertion-oriented exception.
A expectExitSuccess<A extends Object, E extends Object>(Exit<A, E> exit) {
  return switch (exit) {
    ExitSuccess<A, E>(:final value) => value,
    _ => throw BetterEffectTestExpectationException(
      expected: 'ExitSuccess<$A, $E>',
      actual: exit,
    ),
  };
}

/// Extract a typed failure or throw an assertion-oriented exception.
E expectExitFailure<A extends Object, E extends Object>(Exit<A, E> exit) {
  return switch (exit) {
    ExitFailure<A, E>(:final error) => error,
    _ => throw BetterEffectTestExpectationException(
      expected: 'ExitFailure<$A, $E>',
      actual: exit,
    ),
  };
}

/// Extract a defect and stack trace or throw an assertion-oriented exception.
({Object defect, StackTrace stackTrace})
expectExitDefect<A extends Object, E extends Object>(Exit<A, E> exit) {
  return switch (exit) {
    ExitDefect<A, E>(:final defect, :final stackTrace) => (
      defect: defect,
      stackTrace: stackTrace,
    ),
    _ => throw BetterEffectTestExpectationException(
      expected: 'ExitDefect<$A, $E>',
      actual: exit,
    ),
  };
}

/// Assert an interrupted outcome without depending on a test framework.
void expectExitInterrupted<A extends Object, E extends Object>(
  Exit<A, E> exit,
) {
  if (exit is ExitInterrupted<A, E>) return;
  throw BetterEffectTestExpectationException(
    expected: 'ExitInterrupted<$A, $E>',
    actual: exit,
  );
}

const Object _unspecified = Object();

enum _ExitKind { success, failure, defect, interrupted }

final class _TypedExitMatcher<A extends Object, E extends Object>
    extends Matcher {
  const _TypedExitMatcher({required this.kind, this.payload});

  final _ExitKind kind;
  final Matcher? payload;

  @override
  bool matches(Object? item, Map<Object?, Object?> matchState) {
    final value = switch ((kind, item)) {
      (_ExitKind.success, ExitSuccess<A, E>(:final value)) => value,
      (_ExitKind.failure, ExitFailure<A, E>(:final error)) => error,
      (_ExitKind.defect, ExitDefect<A, E>(:final defect)) => defect,
      (_ExitKind.interrupted, ExitInterrupted<A, E>()) => _unspecified,
      _ => null,
    };

    if (value == null) {
      matchState['actual'] = item;
      return false;
    }

    final expectedPayload = payload;
    if (expectedPayload == null || identical(value, _unspecified)) {
      return true;
    }

    final nestedState = <Object?, Object?>{};
    final matched = expectedPayload.matches(value, nestedState);
    if (!matched) {
      matchState['payload'] = value;
      matchState['nested'] = nestedState;
    }
    return matched;
  }

  @override
  Description describe(Description description) {
    description.add(_description);
    final expectedPayload = payload;
    if (expectedPayload != null) {
      description.add(' with ').addDescriptionOf(expectedPayload);
    }
    return description;
  }

  @override
  Description describeMismatch(
    Object? item,
    Description mismatchDescription,
    Map<Object?, Object?> matchState,
    bool verbose,
  ) {
    final payloadValue = matchState['payload'];
    final expectedPayload = payload;
    if (payloadValue != null && expectedPayload != null) {
      mismatchDescription.add('had payload ').addDescriptionOf(payloadValue);
      return expectedPayload.describeMismatch(
        payloadValue,
        mismatchDescription,
        matchState['nested'] as Map<Object?, Object?>? ?? const {},
        verbose,
      );
    }

    return mismatchDescription.add('was ').addDescriptionOf(item);
  }

  String get _description => switch (kind) {
    _ExitKind.success => 'ExitSuccess<$A, $E>',
    _ExitKind.failure => 'ExitFailure<$A, $E>',
    _ExitKind.defect => 'ExitDefect<$A, $E>',
    _ExitKind.interrupted => 'ExitInterrupted<$A, $E>',
  };
}

/// Framework-independent failure used by typed Exit extractors.
final class BetterEffectTestExpectationException implements Exception {
  const BetterEffectTestExpectationException({
    required this.expected,
    required this.actual,
  });

  final String expected;
  final Object actual;

  @override
  String toString() => 'Expected $expected, but received $actual.';
}
