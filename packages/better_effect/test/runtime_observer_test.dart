import 'dart:async';

import 'package:better_effect/better_effect.dart';
import 'package:test/test.dart';

final class ObserverFailure implements Exception {
  const ObserverFailure(this.message);

  final String message;
}

abstract interface class Clock {
  String get now;
}

final class ClockLive implements Clock {
  const ClockLive(this.now);

  @override
  final String now;
}

final class MissingService {}

final class FirstResource {
  const FirstResource();
}

final class SecondResource {
  const SecondResource();
}

final class LocalResource {
  const LocalResource();
}

final class RequestContext {
  const RequestContext(this.id);

  final String id;
}

final class RequestRepository {
  const RequestRepository(this.clock, this.context);

  final Clock clock;
  final RequestContext context;

  String describe() => '${clock.now}:${context.id}';
}

final class _RecordingObserver extends RuntimeObserver {
  final events = <Object>[];

  Iterable<T> ofType<T>() => events.whereType<T>();

  @override
  void onExecutionStart(ExecutionStartEvent event) => events.add(event);

  @override
  void onExecutionEnd(ExecutionEndEvent event) => events.add(event);

  @override
  void onServiceResolve(ServiceResolveEvent event) => events.add(event);

  @override
  void onServiceAcquire(ServiceAcquireEvent event) => events.add(event);

  @override
  void onResourceRelease(ResourceReleaseEvent event) => events.add(event);

  @override
  void onInterruption(InterruptionEvent event) => events.add(event);

  @override
  void onCleanupFailure(CleanupFailureEvent event) => events.add(event);
}

final class _ThrowingObserver extends RuntimeObserver {
  Never _fail() => throw StateError('observer failed');

  @override
  void onExecutionStart(ExecutionStartEvent event) => _fail();

  @override
  void onExecutionEnd(ExecutionEndEvent event) => _fail();

  @override
  void onServiceResolve(ServiceResolveEvent event) => _fail();

  @override
  void onServiceAcquire(ServiceAcquireEvent event) => _fail();

  @override
  void onResourceRelease(ResourceReleaseEvent event) => _fail();

  @override
  void onInterruption(InterruptionEvent event) => _fail();

  @override
  void onCleanupFailure(CleanupFailureEvent event) => _fail();
}

void main() {
  group('managed execution events', () {
    test(
      'success, typed failure, defect and interruption end exactly once',
      () async {
        final observer = _RecordingObserver();
        final runtime = await Module(
          const <Binding>[],
        ).start(observers: <RuntimeObserver>[observer]);

        final success = await runtime.runExit(
          Effect<int, ObserverFailure>.succeed(1),
          executionLabel: 'success',
        );
        final failure = await runtime.runExit(
          Effect<int, ObserverFailure>.fail(const ObserverFailure('expected')),
          executionLabel: 'failure',
        );
        final defect = await runtime.runExit(
          Effect<int, ObserverFailure>.sync(() => throw StateError('defect')),
          executionLabel: 'defect',
        );

        final started = Completer<void>();
        final continuePhysical = Completer<void>();
        final interruptedExecution = runtime.execute(
          Effect<int, ObserverFailure>.result((use) async {
            started.complete();
            await use.cancellation.whenCancelled;
            await continuePhysical.future;
            return 4;
          }),
          label: 'interrupted',
        );
        await started.future;
        expect(interruptedExecution.interrupt(reason: 'test-owner'), isTrue);
        final interrupted = await interruptedExecution.exit;
        continuePhysical.complete();
        await runtime.close();

        expect(success, isA<ExitSuccess<int, ObserverFailure>>());
        expect(failure, isA<ExitFailure<int, ObserverFailure>>());
        expect(defect, isA<ExitDefect<int, ObserverFailure>>());
        expect(interrupted, isA<ExitInterrupted<int, ObserverFailure>>());

        final starts = observer.ofType<ExecutionStartEvent>().toList();
        final ends = observer.ofType<ExecutionEndEvent>().toList();
        expect(starts, hasLength(4));
        expect(ends, hasLength(4));
        expect(starts.map((event) => event.context.executionLabel), <String?>[
          'success',
          'failure',
          'defect',
          'interrupted',
        ]);
        expect(ends.map((event) => event.outcome.runtimeType), <Type>[
          ExitSuccess<int, ObserverFailure>,
          ExitFailure<int, ObserverFailure>,
          ExitDefect<int, ObserverFailure>,
          ExitInterrupted<int, ObserverFailure>,
        ]);
        expect(ends.every((event) => !event.duration.isNegative), isTrue);

        final interruptions = observer.ofType<InterruptionEvent>().toList();
        expect(interruptions, hasLength(1));
        expect(interruptions.single.reason, 'test-owner');
        expect(interruptions.single.source, InterruptionSource.executionOwner);
        expect(interruptions.single.publishesLogicalInterruption, isTrue);
      },
    );

    test('shutdown interruption is distinct from owner interruption', () async {
      final observer = _RecordingObserver();
      final started = Completer<void>();
      final runtime = await Module(
        const <Binding>[],
      ).start(observers: <RuntimeObserver>[observer]);
      final execution = runtime.execute(
        Effect<int, Never>.result((use) async {
          started.complete();
          await use.cancellation.whenCancelled;
          use.cancellation.throwIfCancelled();
          return 1;
        }),
      );

      await started.future;
      await runtime.close(
        gracePeriod: Duration.zero,
        interruptAfterGracePeriod: true,
      );

      expect(await execution.exit, isA<ExitInterrupted<int, Never>>());
      final event = observer.ofType<InterruptionEvent>().single;
      expect(event.reason, 'runtime-shutdown');
      expect(event.source, InterruptionSource.runtimeShutdown);
      expect(event.publishesLogicalInterruption, isFalse);
    });
  });

  group('service and resource events', () {
    test(
      'service requests expose success and missing dependency paths',
      () async {
        final observer = _RecordingObserver();
        final runtime = await Module([
          .instance<Clock>(const ClockLive('12:00')),
        ]).start(observers: <RuntimeObserver>[observer]);

        final success = await runtime.runExit(
          Effect<String, Never>.result((use) async => use<Clock>().now),
        );
        final missing = await runtime.runExit(Effect.service<MissingService>());
        await runtime.close();

        expect(success, isA<ExitSuccess<String, Never>>());
        expect(missing, isA<ExitDefect<MissingService, Never>>());

        final resolutions = observer.ofType<ServiceResolveEvent>().toList();
        expect(resolutions, hasLength(2));
        expect(resolutions.first.serviceType, Clock);
        expect(resolutions.first.succeeded, isTrue);
        expect(resolutions.first.resolutionPath, contains('Clock'));
        expect(resolutions.last.serviceType, MissingService);
        expect(resolutions.last.succeeded, isFalse);
        expect(
          resolutions.last.resolutionPath.join(' -> '),
          contains('MissingService'),
        );
        expect(resolutions.last.error, isNotNull);
      },
    );

    test(
      'acquisition and reverse release ordering identify ownership',
      () async {
        final observer = _RecordingObserver();
        final runtime = await Module(
          const <Binding>[],
        ).start(observers: <RuntimeObserver>[observer]);

        final exit = await runtime.runExit(
          Effect<int, Never>.result((use) async {
            await use.acquire(
              Effect<FirstResource, Never>.succeed(const FirstResource()),
              release: (_, _) {},
            );
            await use.acquire(
              Effect<SecondResource, Never>.succeed(const SecondResource()),
              release: (_, _) {},
            );
            return 1;
          }),
          executionLabel: 'resources',
        );
        await runtime.close();

        expect(exit, isA<ExitSuccess<int, Never>>());
        final acquisitions = observer.ofType<ServiceAcquireEvent>().toList();
        expect(acquisitions.map((event) => event.serviceType), <Type>[
          FirstResource,
          SecondResource,
        ]);
        expect(
          acquisitions.every(
            (event) =>
                event.source == ResourceAcquisitionSource.effect &&
                event.context.executionLabel == 'resources' &&
                event.succeeded,
          ),
          isTrue,
        );

        final releases = observer.ofType<ResourceReleaseEvent>().toList();
        expect(releases.map((event) => event.serviceType), <Type>[
          SecondResource,
          FirstResource,
        ]);
        expect(releases.every((event) => event.outcome == exit), isTrue);
      },
    );

    test(
      'execution-scoped Modules retain the managed execution identity',
      () async {
        final observer = _RecordingObserver();
        final runtime = await Module([
          .instance<Clock>(const ClockLive('root-clock')),
        ]).start(observers: <RuntimeObserver>[observer]);
        final requestModule = Module([
          .instance<RequestContext>(const RequestContext('req-1')),
          .provide<RequestRepository>(RequestRepository.new),
          .resource<LocalResource>(
            acquire: (_) async => const LocalResource(),
            release: (_, _) {},
          ),
        ]);

        final exit = await runtime.runExitWith(
          requestModule,
          Effect<String, Never>.result((use) async {
            use<LocalResource>();
            return use<RequestRepository>().describe();
          }),
          executionLabel: 'request',
        );
        await runtime.close();

        expect((exit as ExitSuccess<String, Never>).value, 'root-clock:req-1');
        final start = observer.ofType<ExecutionStartEvent>().single;
        final executionId = start.context.executionId;
        expect(executionId, greaterThan(0));
        expect(
          observer
              .ofType<ServiceAcquireEvent>()
              .where((event) => event.serviceType == LocalResource)
              .single
              .context
              .executionId,
          executionId,
        );
        expect(
          observer
              .ofType<ServiceResolveEvent>()
              .where((event) => event.serviceType == RequestRepository)
              .single
              .context
              .executionId,
          executionId,
        );
      },
    );
  });

  group('EffectLocal metadata', () {
    test(
      'typed batches expose selected metadata with nested override snapshots',
      () async {
        const requestId = EffectLocal<String>.metadata(
          'unknown-request',
          name: 'request.id',
        );
        const traceId = EffectLocal<String>.metadata(
          'unknown-trace',
          name: 'trace.id',
        );
        const secret = EffectLocal<String>('hidden', name: 'secret');
        final observer = _RecordingObserver();
        final runtime = await Module([
          .instance<Clock>(const ClockLive('clock')),
        ]).start(observers: <RuntimeObserver>[observer]);

        final program =
            Effect<String, Never>.result((use) async {
                  await use.unwrap(
                    Effect<String, Never>.result((nested) async {
                      return nested<Clock>().now;
                    }).withLocal(traceId, 'trace-inner'),
                  );
                  use<Clock>();
                  return '${use.local(requestId)}:${use.local(traceId)}:${use.local(secret)}';
                })
                .withLocals(<EffectLocalBinding>[
                  requestId.bind('req-123'),
                  traceId.bind('trace-outer'),
                  secret.bind('not-observable'),
                ])
                .map((value) => value);

        final exit = await runtime.runExit(program, executionLabel: 'metadata');
        await runtime.close();

        expect(
          (exit as ExitSuccess<String, Never>).value,
          'req-123:trace-outer:not-observable',
        );
        final startMetadata = observer
            .ofType<ExecutionStartEvent>()
            .single
            .context
            .localMetadata;
        final endMetadata = observer
            .ofType<ExecutionEndEvent>()
            .single
            .context
            .localMetadata;
        expect(startMetadata, <String, Object>{
          'request.id': 'req-123',
          'trace.id': 'trace-outer',
        });
        expect(endMetadata, startMetadata);
        expect(startMetadata, isNot(contains('secret')));

        final serviceMetadata = observer
            .ofType<ServiceResolveEvent>()
            .map((event) => event.context.localMetadata['trace.id'])
            .toList();
        expect(serviceMetadata, <Object?>['trace-inner', 'trace-outer']);
      },
    );
  });

  group('observer failure isolation', () {
    test(
      'every callback is isolated and later observers still receive events',
      () async {
        final recording = _RecordingObserver();
        final callbacks = <RuntimeObserverCallback>[];
        final runtime =
            await Module([.instance<Clock>(const ClockLive('clock'))]).start(
              observers: <RuntimeObserver>[_ThrowingObserver(), recording],
              observerErrorHandler: (failure) {
                callbacks.add(failure.callback);
                throw StateError('error handler also failed');
              },
            );

        final cleanupExit = await runtime.runExit(
          Effect<int, Never>.result((use) async {
            use<Clock>();
            await use.acquire(
              Effect<FirstResource, Never>.succeed(const FirstResource()),
              release: (_, _) => throw StateError('release failed'),
            );
            return 1;
          }),
          executionLabel: 'cleanup',
        );
        expect(cleanupExit, isA<ExitDefect<int, Never>>());

        final started = Completer<void>();
        final continuePhysical = Completer<void>();
        final interruptedExecution = runtime.execute(
          Effect<int, Never>.result((use) async {
            started.complete();
            await use.cancellation.whenCancelled;
            await continuePhysical.future;
            return 2;
          }),
          label: 'interruption',
        );
        await started.future;
        interruptedExecution.interrupt(reason: 'owner');
        expect(
          await interruptedExecution.exit,
          isA<ExitInterrupted<int, Never>>(),
        );
        continuePhysical.complete();
        await runtime.close();

        expect(callbacks.toSet(), RuntimeObserverCallback.values.toSet());
        expect(recording.ofType<ExecutionStartEvent>(), hasLength(2));
        expect(recording.ofType<ExecutionEndEvent>(), hasLength(2));
        expect(recording.ofType<ServiceResolveEvent>(), hasLength(1));
        expect(recording.ofType<ServiceAcquireEvent>(), hasLength(1));
        expect(recording.ofType<ResourceReleaseEvent>(), hasLength(1));
        expect(recording.ofType<CleanupFailureEvent>(), hasLength(1));
        expect(recording.ofType<InterruptionEvent>(), hasLength(1));
      },
    );

    test(
      'the no-observer fast path preserves ordinary Runtime semantics',
      () async {
        final runtime = await Module([
          .instance<Clock>(const ClockLive('clock')),
        ]).start();

        final exit = await runtime.runExit(
          Effect<String, Never>.result((use) async => use<Clock>().now),
        );
        await runtime.close();

        expect((exit as ExitSuccess<String, Never>).value, 'clock');
      },
    );
  });
}
