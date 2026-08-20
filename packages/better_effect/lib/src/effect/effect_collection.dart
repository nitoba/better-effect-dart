part of '../../better_effect.dart';

typedef _IndexedCollectionFailure<E extends Object> = ({int index, E error});

typedef _IndexedCollectionDefect = ({
  int index,
  Object error,
  StackTrace stackTrace,
});

Effect<List<B>, E> _effectForEach<I, B extends Object, E extends Object>(
  Iterable<I> inputs,
  Effect<B, E> Function(I input) transform, {
  required int concurrency,
}) {
  if (concurrency <= 0) {
    throw ArgumentError.value(
      concurrency,
      'concurrency',
      'must be a positive finite integer',
    );
  }

  return Effect<List<B>, E>._((context) {
    return _runEffectCollection<I, B, E>(
      inputs: inputs,
      transform: transform,
      concurrency: concurrency,
      context: context,
    );
  });
}

Effect<List<B>, E> _effectForEachUnbounded<
  I,
  B extends Object,
  E extends Object
>(Iterable<I> inputs, Effect<B, E> Function(I input) transform) {
  return Effect<List<B>, E>._((context) {
    return _runEffectCollection<I, B, E>(
      inputs: inputs,
      transform: transform,
      concurrency: null,
      context: context,
    );
  });
}

Future<ResultDart<List<B>, E>>
_runEffectCollection<I, B extends Object, E extends Object>({
  required Iterable<I> inputs,
  required Effect<B, E> Function(I input) transform,
  required int? concurrency,
  required _RuntimeContext context,
}) async {
  context.cancellation.throwIfCancelled();

  // Materialization is intentionally inside the runner: constructing the
  // collection Effect neither traverses the input nor invokes the mapper.
  final inputValues = List<I>.of(inputs, growable: false);
  if (inputValues.isEmpty) {
    return Success<List<B>, E>(List<B>.unmodifiable(<B>[]));
  }

  final requestedWorkers = concurrency ?? inputValues.length;
  final workerCount = requestedWorkers < inputValues.length
      ? requestedWorkers
      : inputValues.length;
  final output = List<B?>.filled(inputValues.length, null, growable: false);
  final failures = <_IndexedCollectionFailure<E>>[];
  final defects = <_IndexedCollectionDefect>[];

  var nextIndex = 0;
  var stopScheduling = false;

  Future<void> worker() async {
    while (true) {
      if (stopScheduling || context.cancellation.isCancelled) {
        return;
      }

      if (nextIndex >= inputValues.length) {
        return;
      }

      // No await occurs between observing the queue and claiming the next
      // index, so starts remain FIFO in Dart's single-isolate event loop.
      final index = nextIndex++;

      try {
        final effect = transform(inputValues[index]);
        final result = await effect._run(context);
        result.fold<Object?>(
          (value) {
            output[index] = value;
            return null;
          },
          (error) {
            failures.add((index: index, error: error));
            stopScheduling = true;
            return null;
          },
        );
      } on _CancellationRequested {
        stopScheduling = true;
      } catch (error, stackTrace) {
        defects.add((index: index, error: error, stackTrace: stackTrace));
        stopScheduling = true;
      }
    }
  }

  await Future.wait<void>(<Future<void>>[
    for (var index = 0; index < workerCount; index++) worker(),
  ]);

  // Defects stay outside the typed failure channel. Input order, rather than
  // completion timing, selects between several defects already in flight.
  if (defects.isNotEmpty) {
    defects.sort((left, right) => left.index.compareTo(right.index));
    final defect = defects.first;
    Error.throwWithStackTrace(defect.error, defect.stackTrace);
  }

  // Owner interruption may already have published a logical ExitInterrupted;
  // shutdown interruption reaches the same boundary here after started work
  // has physically drained.
  context.cancellation.throwIfCancelled();

  // When several started operations fail, the lowest input index is the
  // authoritative typed failure. This is deterministic even when completion
  // order differs between runs.
  if (failures.isNotEmpty) {
    failures.sort((left, right) => left.index.compareTo(right.index));
    return Failure<List<B>, E>(failures.first.error);
  }

  return Success<List<B>, E>(
    List<B>.unmodifiable(<B>[for (final value in output) value as B]),
  );
}
