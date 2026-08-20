import 'package:better_effect/testing.dart';
import 'package:test/test.dart';

final class CollectionConstructionFailure implements Exception {
  const CollectionConstructionFailure();
}

void main() {
  group('Effect collection construction', () {
    test('Effect.all traverses and executes its source lazily', () async {
      var traversals = 0;
      var executions = 0;

      Iterable<Effect<int, CollectionConstructionFailure>> source() sync* {
        traversals++;
        yield Effect<int, CollectionConstructionFailure>.sync(() {
          executions++;
          return 1;
        });
        yield Effect<int, CollectionConstructionFailure>.sync(() {
          executions++;
          return 2;
        });
      }

      final effect = Effect.all<int, CollectionConstructionFailure>(source());

      expect(traversals, 0);
      expect(executions, 0);

      final values = expectExitSuccess(
        await Module(const <Binding>[]).runExit(effect),
      );

      expect(traversals, 1);
      expect(executions, 2);
      expect(values, <int>[1, 2]);
    });

    test(
      'Iterable traversal stays lazy and a thrown value remains a defect',
      () async {
        var traversals = 0;
        var mappings = 0;

        Iterable<int> brokenInput() sync* {
          traversals++;
          yield 1;
          throw StateError('iterable-defect');
        }

        final effect = Effect.forEach(brokenInput(), (value) {
          mappings++;
          return Effect<int, CollectionConstructionFailure>.succeed(value);
        });

        expect(traversals, 0);
        expect(mappings, 0);

        final exit = await Module(const <Binding>[]).runExit(effect);
        final defect = expectExitDefect(exit).defect;

        expect(traversals, 1);
        expect(mappings, 0);
        expect(defect, isA<StateError>());
        expect((defect as StateError).message, 'iterable-defect');
      },
    );

    test('a mapper defect stops later inputs from starting', () async {
      final started = <int>[];
      final effect = Effect.forEach(const <int>[0, 1, 2], (value) {
        started.add(value);
        if (value == 0) {
          throw StateError('mapper-defect');
        }
        return Effect<int, CollectionConstructionFailure>.succeed(value);
      }, concurrency: 1);

      final exit = await Module(const <Binding>[]).runExit(effect);
      final defect = expectExitDefect(exit).defect;

      expect(started, <int>[0]);
      expect(defect, isA<StateError>());
      expect((defect as StateError).message, 'mapper-defect');
    });
  });
}
