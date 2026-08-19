import '../domain/app_failure.dart';
import '../domain/task.dart';
import 'task_service.dart';

abstract interface class TaskRepository {
  AppEffect<Task> add(String title);

  AppEffect<List<Task>> all();

  AppEffect<Task> toggle(TaskId id);
}

final class TaskRepositoryLive implements TaskRepository {
  @override
  AppEffect<Task> add(String title) => .result((use) async {
    final normalized = title.trim();
    if (normalized.isEmpty) {
      use.fail(const TaskValidationFailure('Give the task a title.'));
    }

    final service = use<TaskService>();
    final task = await use.tryAsync(
      () => service.addTask(normalized),
      onError: _mapServiceFailure,
    );

    return task.toDomain();
  });

  @override
  AppEffect<List<Task>> all() => .result((use) async {
    final service = use<TaskService>();

    final tasks = await use.tryAsync(
      service.fetchTasks,
      onError: _mapServiceFailure,
    );

    return tasks.map((task) => task.toDomain()).toList(growable: false);
  });

  @override
  AppEffect<Task> toggle(TaskId id) => .result((use) async {
    final service = use<TaskService>();
    final task = await use.tryAsync(
      () => service.toggleTask(id),
      onError: _mapServiceFailure,
    );

    return task.toDomain();
  });

  static AppFailure _mapServiceFailure(Exception error, StackTrace stackTrace) {
    return switch (error) {
      TaskMissingException(:final id) => TaskNotFound(id),
      _ => TaskStorageFailure(cause: error, stackTrace: stackTrace),
    };
  }
}
