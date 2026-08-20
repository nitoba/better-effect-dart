import 'dart:async';

import 'package:better_effect/better_effect.dart';
import 'package:test/test.dart';

abstract interface class RootClock {
  String get value;
}

final class RootClockLive implements RootClock {
  const RootClockLive(this.value);

  @override
  final String value;
}

final class RequestContext {
  const RequestContext(this.requestId);

  final String requestId;
}

final class RequestRepository {
  const RequestRepository(this.clock, this.context);

  final RootClock clock;
  final RequestContext context;

  String describe() => '${clock.value}:${context.requestId}';
}

abstract interface class Message {
  String get value;
}

final class MessageValue implements Message {
  const MessageValue(this.value);

  @override
  final String value;
}

final class Endpoint {
  const Endpoint(this.value);

  final String value;
}

const executionEndpoint = ServiceKey<Endpoint>('execution-endpoint');

final class RootResource {
  const RootResource();
}

final class FirstLocalResource {
  const FirstLocalResource();
}

final class SecondLocalResource {
  const SecondLocalResource();
}

final class EffectResource {
  const EffectResource();
}

final class FailingLocalResource {
  const FailingLocalResource();
}

final class ExecutionSession {
  const ExecutionSession(this.id);

  final int id;
}

final class TimeoutFailure implements Exception {
  const TimeoutFailure();
}

final class _NonOverlayBackend implements ResolverBackend {
  bool committed = false;
  bool closed = false;

  @override
  Future<void> activate() async {
    committed = true;
  }

  @override
  Future<void> close() async {
    closed = true;
  }

  @override
  void commit() {
    committed = true;
  }

  @override
  void register<T extends Object>(
    Function constructor, {
    required Lifetime lifetime,
    String? key,
  }) {}

  @override
  void registerInstance<T extends Object>(T instance, {String? key}) {}

  @override
  T resolve<T extends Object>({String? key}) {
    throw StateError('$T is not registered.');
  }
}

void main() {
  test(
    'local providers shadow root while constructors use local and root services',
    () async {
      final rootMessage = const MessageValue('root');
      final rootEndpoint = const Endpoint('root-key');
      final runtime = await Module([
        .instance<RootClock>(const RootClockLive('clock')),
        .instance<Message>(rootMessage),
        .instance<Endpoint>(rootEndpoint, key: executionEndpoint),
      ]).start();
      final requestModule = Module([
        .instance<RequestContext>(const RequestContext('request-123')),
        .instance<Message>(const MessageValue('local')),
        .instance<Endpoint>(
          const Endpoint('local-key'),
          key: executionEndpoint,
        ),
        .provide<RequestRepository>(RequestRepository.new),
      ]);

      try {
        final result = await runtime.runWith(
          requestModule,
          Effect<(String, String, String, String), Never>.result((use) async {
            final repository = use<RequestRepository>();
            return (
              repository.describe(),
              use<RootClock>().value,
              use<Message>().value,
              use(executionEndpoint).value,
            );
          }),
          executionLabel: 'request',
        );

        expect(result.getOrThrow(), (
          'clock:request-123',
          'clock',
          'local',
          'local-key',
        ));
        expect(runtime.services<Message>(), same(rootMessage));
        expect(runtime.services(executionEndpoint), same(rootEndpoint));
      } finally {
        await runtime.close();
      }
    },
  );

  test('execution resources close before local and root resources', () async {
    final events = <String>[];
    final observedOutcomes = <Exit<Object, Object>>[];
    final runtime = await Module([
      .resource<RootResource>(
        acquire: (_) async {
          events.add('acquire:root');
          return const RootResource();
        },
        release: (_, exit) {
          events.add('release:root');
          observedOutcomes.add(exit);
        },
      ),
    ]).start();
    final localModule = Module([
      .resource<FirstLocalResource>(
        acquire: (_) async {
          events.add('acquire:first-local');
          return const FirstLocalResource();
        },
        release: (_, exit) {
          events.add('release:first-local');
          observedOutcomes.add(exit);
        },
      ),
      .resource<SecondLocalResource>(
        acquire: (services) async {
          services<FirstLocalResource>();
          events.add('acquire:second-local');
          return const SecondLocalResource();
        },
        release: (_, exit) {
          events.add('release:second-local');
          observedOutcomes.add(exit);
        },
      ),
    ]);

    final exit = await runtime.runExitWith(
      localModule,
      Effect<int, Never>.result((use) async {
        use<RootResource>();
        use<SecondLocalResource>();
        await use.acquire(
          Effect<EffectResource, Never>.sync(() {
            events.add('acquire:effect');
            return const EffectResource();
          }),
          release: (_, outcome) {
            events.add('release:effect');
            observedOutcomes.add(outcome);
          },
        );
        return 42;
      }),
    );

    expect(exit, isA<ExitSuccess<int, Never>>());
    expect(events, <String>[
      'acquire:root',
      'acquire:first-local',
      'acquire:second-local',
      'acquire:effect',
      'release:effect',
      'release:second-local',
      'release:first-local',
    ]);
    expect(observedOutcomes, hasLength(3));
    expect(observedOutcomes, everyElement(same(exit)));
    expect(runtime.services<RootResource>(), isA<RootResource>());

    await runtime.close();

    expect(events.last, 'release:root');
    expect(observedOutcomes.last, isA<ExitInterrupted<Object, Object>>());
  });

  test('partial local startup failure releases acquired resources', () async {
    final events = <String>[];
    Exit<Object, Object>? releaseOutcome;
    var effectStarted = false;
    final runtime = await Module([
      .instance<RootClock>(const RootClockLive('root')),
    ]).start();
    final localModule = Module([
      .resource<FirstLocalResource>(
        acquire: (_) async {
          events.add('acquire:first');
          return const FirstLocalResource();
        },
        release: (_, exit) {
          events.add('release:first');
          releaseOutcome = exit;
        },
      ),
      .resource<FailingLocalResource>(
        acquire: (_) async {
          events.add('acquire:failing');
          throw StateError('local-startup-failed');
        },
        release: (_, _) {
          events.add('release:unreachable');
        },
      ),
    ]);

    try {
      final exit = await runtime.runExitWith(
        localModule,
        Effect<int, Never>.sync(() {
          effectStarted = true;
          return 1;
        }),
      );

      expect(exit, isA<ExitDefect<int, Never>>());
      final defect = (exit as ExitDefect<int, Never>).defect;
      expect(defect, isA<ResourceAcquisitionException>());
      expect(
        (defect as ResourceAcquisitionException).serviceType,
        FailingLocalResource,
      );
      expect(defect.cause, isA<StateError>());
      expect(effectStarted, isFalse);
      expect(events, <String>[
        'acquire:first',
        'acquire:failing',
        'release:first',
      ]);
      expect(releaseOutcome, same(exit));
      expect(runtime.services<RootClock>().value, 'root');
    } finally {
      await runtime.close();
    }
  });

  test(
    'timeout keeps local resources alive until source physical completion',
    () async {
      final started = Completer<void>();
      final continueExecution = Completer<void>();
      var released = false;
      final runtime = await Module(const <Binding>[]).start();
      final localModule = Module([
        .resource<ExecutionSession>(
          acquire: (_) async => const ExecutionSession(1),
          release: (_, _) {
            released = true;
          },
        ),
      ]);
      final execution = runtime.executeWith(
        localModule,
        Effect<int, TimeoutFailure>.result((use) async {
          use<ExecutionSession>();
          started.complete();
          await continueExecution.future;
          return 42;
        }).timeout(Duration.zero, onTimeout: TimeoutFailure.new),
        label: 'timeout-local-module',
      );

      await started.future;
      final exit = await execution.exit;

      expect(exit, isA<ExitFailure<int, TimeoutFailure>>());
      expect(execution.label, 'timeout-local-module');
      expect(execution.isRunning, isTrue);
      expect(released, isFalse);

      continueExecution.complete();
      await runtime.close();

      expect(execution.isRunning, isFalse);
      expect(released, isTrue);
    },
  );

  test(
    'interruption keeps local resources until physical completion',
    () async {
      final started = Completer<void>();
      final continueExecution = Completer<void>();
      final observedReason = Completer<Object?>();
      var released = false;
      final runtime = await Module(const <Binding>[]).start();
      final localModule = Module([
        .resource<ExecutionSession>(
          acquire: (_) async => const ExecutionSession(1),
          release: (_, _) {
            released = true;
          },
        ),
      ]);
      final execution = runtime.executeWith(
        localModule,
        Effect<int, Never>.result((use) async {
          use<ExecutionSession>();
          started.complete();
          await use.cancellation.whenCancelled;
          observedReason.complete(use.cancellation.reason);
          await continueExecution.future;
          return 42;
        }),
      );

      await started.future;
      expect(execution.interrupt(reason: 'request-ended'), isTrue);

      expect(await execution.exit, isA<ExitInterrupted<int, Never>>());
      expect(await observedReason.future, 'request-ended');
      expect(released, isFalse);

      continueExecution.complete();
      await runtime.close();

      expect(released, isTrue);
    },
  );

  test('concurrent executions use isolated local environments', () async {
    var nextSession = 0;
    final releases = <int>[];
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    final continueFirst = Completer<void>();
    final continueSecond = Completer<void>();
    final runtime = await Module(const <Binding>[]).start();
    final localModule = Module([
      .resource<ExecutionSession>(
        acquire: (_) async => ExecutionSession(++nextSession),
        release: (session, _) {
          releases.add(session.id);
        },
      ),
    ]);

    Effect<int, Never> operation(
      Completer<void> started,
      Completer<void> gate,
    ) {
      return Effect<int, Never>.result((use) async {
        final session = use<ExecutionSession>();
        started.complete();
        await gate.future;
        return session.id;
      });
    }

    final first = runtime.executeWith(
      localModule,
      operation(firstStarted, continueFirst),
    );
    final second = runtime.executeWith(
      localModule,
      operation(secondStarted, continueSecond),
    );

    await Future.wait<void>([firstStarted.future, secondStarted.future]);
    expect(nextSession, 2);

    continueSecond.complete();
    continueFirst.complete();

    final firstExit = (await first.exit) as ExitSuccess<int, Never>;
    final secondExit = (await second.exit) as ExitSuccess<int, Never>;

    expect({firstExit.value, secondExit.value}, <int>{1, 2});
    await runtime.close();
    expect(releases.toSet(), <int>{1, 2});
  });

  test(
    'Runtime.close waits for execution-local physical work before root cleanup',
    () async {
      final events = <String>[];
      final started = Completer<void>();
      final cancellationObserved = Completer<Object?>();
      final continueExecution = Completer<void>();
      final runtime = await Module([
        .resource<RootResource>(
          acquire: (_) async => const RootResource(),
          release: (_, _) {
            events.add('release:root');
          },
        ),
      ]).start();
      final localModule = Module([
        .resource<ExecutionSession>(
          acquire: (_) async => const ExecutionSession(1),
          release: (_, _) {
            events.add('release:local');
          },
        ),
      ]);
      final execution = runtime.executeWith(
        localModule,
        Effect<int, Never>.result((use) async {
          use<RootResource>();
          use<ExecutionSession>();
          started.complete();
          await use.cancellation.whenCancelled;
          cancellationObserved.complete(use.cancellation.reason);
          await continueExecution.future;
          return 42;
        }),
      );

      await started.future;
      final closing = runtime.close(
        gracePeriod: Duration.zero,
        interruptAfterGracePeriod: true,
      );

      expect(await cancellationObserved.future, 'runtime-shutdown');
      expect(events, isEmpty);
      expect(runtime.state, RuntimeState.closing);

      continueExecution.complete();
      expect(await execution.exit, isA<ExitSuccess<int, Never>>());
      await closing;

      expect(events, <String>['release:local', 'release:root']);
      expect(runtime.state, RuntimeState.closed);
    },
  );

  test('custom backends opt into execution overlays explicitly', () async {
    final backend = _NonOverlayBackend();
    final runtime = await Module(const <Binding>[]).start(backend: backend);

    final exit = await runtime.runExitWith(
      Module(const <Binding>[]),
      Effect<int, Never>.succeed(1),
    );

    expect(exit, isA<ExitDefect<int, Never>>());
    expect(
      (exit as ExitDefect<int, Never>).defect,
      isA<ResolverBackendOverlayUnsupportedException>(),
    );

    await runtime.close();
    expect(backend.closed, isTrue);
  });
}
