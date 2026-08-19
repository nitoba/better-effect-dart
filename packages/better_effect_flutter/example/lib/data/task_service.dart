import '../domain/task.dart';

abstract interface class TaskService {
  Future<List<TaskDto>> fetchTasks();

  Future<TaskDto> addTask(String title);

  Future<TaskDto> toggleTask(TaskId id);
}

final class TaskServiceException implements Exception {
  const TaskServiceException(this.message);

  final String message;

  @override
  String toString() => 'TaskServiceException($message)';
}

final class TaskMissingException implements Exception {
  const TaskMissingException(this.id);

  final TaskId id;
}

final class TaskDto {
  const TaskDto({
    required this.id,
    required this.title,
    required this.completed,
  });

  final int id;
  final String title;
  final bool completed;

  Task toDomain() {
    return Task(id: TaskId(id), title: title, completed: completed);
  }
}

final class InMemoryTaskService implements TaskService {
  InMemoryTaskService()
    : _tasks = <TaskDto>[
        const TaskDto(
          id: 1,
          title: 'Read the Flutter architecture guide',
          completed: true,
        ),
        const TaskDto(id: 2, title: 'Compose a typed Effect', completed: false),
      ];

  final List<TaskDto> _tasks;

  @override
  Future<List<TaskDto>> fetchTasks() async {
    await Future<void>.delayed(const Duration(milliseconds: 350));
    return List<TaskDto>.unmodifiable(_tasks);
  }

  @override
  Future<TaskDto> addTask(String title) async {
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final task = TaskDto(id: _tasks.length + 1, title: title, completed: false);
    _tasks.add(task);
    return task;
  }

  @override
  Future<TaskDto> toggleTask(TaskId id) async {
    await Future<void>.delayed(const Duration(milliseconds: 180));

    final index = _tasks.indexWhere((task) => task.id == id.value);
    if (index < 0) {
      throw TaskMissingException(id);
    }

    final current = _tasks[index];
    final updated = TaskDto(
      id: current.id,
      title: current.title,
      completed: !current.completed,
    );
    _tasks[index] = updated;
    return updated;
  }
}
