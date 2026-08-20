import 'dart:async';

import 'package:better_effect/better_effect.dart';

/// Deterministic [EffectClock] controlled by the test.
///
/// Sleeps complete only when [advance] or [advanceTo] reaches their deadline.
/// Cancellation removes the pending sleep without advancing time.
final class ManualEffectClock implements EffectClock {
  ManualEffectClock([DateTime? initialTime])
    : _now = initialTime ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

  DateTime _now;
  final List<_ManualSleep> _pending = <_ManualSleep>[];

  @override
  DateTime now() => _now;

  /// Number of sleeps currently waiting for manual time.
  int get pendingSleepCount => _pending.length;

  /// Remaining durations in deadline order.
  List<Duration> get pendingDurations {
    final values = <Duration>[
      for (final sleep in _pending)
        sleep.deadline.isAfter(_now)
            ? sleep.deadline.difference(_now)
            : Duration.zero,
    ];
    values.sort();
    return List<Duration>.unmodifiable(values);
  }

  @override
  Future<void> sleep(Duration duration, CancellationSignal cancellation) async {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must not be negative');
    }

    cancellation.throwIfCancelled();
    if (duration == Duration.zero) {
      await Future<void>.value();
      cancellation.throwIfCancelled();
      return;
    }

    final pending = _ManualSleep(
      deadline: _now.add(duration),
      completer: Completer<void>.sync(),
    );
    _pending.add(pending);

    try {
      await Future.any<void>(<Future<void>>[
        pending.completer.future,
        cancellation.whenCancelled,
      ]);
      cancellation.throwIfCancelled();
    } finally {
      _pending.remove(pending);
    }
  }

  /// Move time forward and complete every sleep whose deadline was reached.
  Future<void> advance(Duration duration) async {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must not be negative');
    }
    await advanceTo(_now.add(duration));
  }

  /// Move time to [instant] and complete every due sleep.
  Future<void> advanceTo(DateTime instant) async {
    if (instant.isBefore(_now)) {
      throw ArgumentError.value(
        instant,
        'instant',
        'must not be earlier than the current manual time',
      );
    }

    _now = instant;
    final due = <_ManualSleep>[
      for (final sleep in _pending)
        if (!sleep.deadline.isAfter(_now)) sleep,
    ];
    due.sort((left, right) => left.deadline.compareTo(right.deadline));
    for (final sleep in due) {
      if (!sleep.completer.isCompleted) sleep.completer.complete();
    }

    await Future<void>.value();
  }
}

final class _ManualSleep {
  const _ManualSleep({required this.deadline, required this.completer});

  final DateTime deadline;
  final Completer<void> completer;
}
