import 'package:better_effect/better_effect.dart';
import 'package:test/test.dart';

sealed class TestFailure implements Exception {
  const TestFailure();
}

final class FirstFailure extends TestFailure {
  const FirstFailure(this.message);

  final String message;
}

final class SecondFailure extends TestFailure {
  const SecondFailure(this.message);

  final String message;
}

final class TestException implements Exception {
  const TestException(this.message);

  final String message;
}

void main() {
  final emptyModule = Module(const <Binding>[]);

  group('Effect.result', () {
    test('returns a successful Result', () async {
      final effect = Effect<int, TestFailure>.result((use) async => 42);

      final result = await emptyModule.run(effect);

      expect(result.getOrNull(), 42);
      expect(result.isSuccess(), isTrue);
    });

    test('propagates an inner Effect failure', () async {
      final effect = Effect<int, TestFailure>.result((use) async {
        final value = await use.unwrap(Effect<int, FirstFailure>.succeed(10));

        await use.unwrap(
          Effect<Unit, SecondFailure>.fail(const SecondFailure('stopped')),
        );

        return value;
      });

      final result = await emptyModule.run(effect);

      expect(result.isError(), isTrue);
      expect(result.exceptionOrNull(), isA<SecondFailure>());
    });

    test('propagates result_dart failures', () async {
      final effect = Effect<int, TestFailure>.result((use) async {
        return use.result(
          const Failure<int, FirstFailure>(FirstFailure('result failure')),
        );
      });

      final result = await emptyModule.run(effect);

      expect(result.exceptionOrNull(), isA<FirstFailure>());
    });

    test('fails explicitly through Never', () async {
      final effect = Effect<int, TestFailure>.result((use) async {
        use.fail(const FirstFailure('explicit failure'));
      });

      final result = await emptyModule.run(effect);

      expect(result.exceptionOrNull(), isA<FirstFailure>());
    });
  });

  group('exception boundaries', () {
    test('tryAsync maps Exception into the typed failure channel', () async {
      final effect = Effect<int, TestFailure>.tryAsync(
        () => throw const TestException('boom'),
        onError: (error, stackTrace) => FirstFailure(error.toString()),
      );

      final result = await emptyModule.run(effect);

      expect(result.exceptionOrNull(), isA<FirstFailure>());
    });

    test('unhandled exceptions are preserved as defects', () async {
      final effect = Effect<int, TestFailure>.sync(
        () => throw const TestException('defect'),
      );

      final exit = await emptyModule.runExit(effect);

      expect(exit, isA<ExitDefect<int, TestFailure>>());
    });
  });

  group('operators', () {
    test('map, tap, and mapError preserve Effect semantics', () async {
      var inspected = 0;

      final effect = Effect<int, FirstFailure>.succeed(20)
          .map((value) => value * 2)
          .tap((value) {
            inspected = value;
          })
          .mapError<TestFailure>((error) => error);

      final result = await emptyModule.run(effect);

      expect(result.getOrNull(), 40);
      expect(inspected, 40);
    });

    test('flatMap sequences effects', () async {
      final effect = Effect<int, TestFailure>.succeed(
        20,
      ).flatMap((value) => Effect<String, TestFailure>.succeed('value:$value'));

      final result = await emptyModule.run(effect);

      expect(result.getOrNull(), 'value:20');
    });

    test('catchAll can recover into another error type', () async {
      final effect = Effect<int, FirstFailure>.fail(
        const FirstFailure('recover'),
      ).catchAll<SecondFailure>((_) => Effect<int, SecondFailure>.succeed(99));

      final result = await emptyModule.run(effect);

      expect(result.getOrNull(), 99);
    });

    test('zip returns a record', () async {
      final effect = Effect.zip(
        Effect<int, TestFailure>.succeed(1),
        Effect<String, TestFailure>.succeed('two'),
      );

      final result = await emptyModule.run(effect);
      final value = result.getOrThrow();
      final (number, text) = value;

      expect(number, 1);
      expect(text, 'two');
    });

    test('either moves typed failure into the success value', () async {
      final effect = Effect<int, TestFailure>.fail(
        const FirstFailure('as value'),
      ).either();

      final result = await emptyModule.run(effect);
      final nested = result.getOrThrow();

      expect(nested.exceptionOrNull(), isA<FirstFailure>());
    });
  });
}
