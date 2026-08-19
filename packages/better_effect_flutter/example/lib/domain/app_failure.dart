import 'package:better_effect_flutter/better_effect_flutter.dart';

import 'task.dart';

sealed class AppFailure implements Exception {
  const AppFailure();

  String get message;
}

final class TaskValidationFailure extends AppFailure {
  const TaskValidationFailure(this.message);

  @override
  final String message;

  @override
  String toString() => 'TaskValidationFailure($message)';
}

final class TaskNotFound extends AppFailure {
  const TaskNotFound(this.id);

  final TaskId id;

  @override
  String get message => 'Task ${id.value} was not found.';

  @override
  String toString() => 'TaskNotFound(${id.value})';
}

final class TaskStorageFailure extends AppFailure {
  const TaskStorageFailure({
    required this.cause,
    required this.stackTrace,
  });

  final Exception cause;
  final StackTrace stackTrace;

  @override
  String get message => 'Could not access the task storage.';

  @override
  String toString() => 'TaskStorageFailure($cause)';
}

typedef AppEffect<A extends Object> = Effect<A, AppFailure>;
