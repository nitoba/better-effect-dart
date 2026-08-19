import 'package:better_effect_flutter/better_effect_flutter.dart';
import 'package:better_effect_flutter_example/data/task_repository.dart';
import 'package:better_effect_flutter_example/domain/app_failure.dart';
import 'package:better_effect_flutter_example/domain/task.dart';
import 'package:better_effect_flutter_example/ui/tasks_view_model.dart';
import 'package:flutter_test/flutter_test.dart';

final class FakeTaskRepository implements TaskRepository {
  final List<Task> tasks = <Task>[
    const Task(id: TaskId(1), title: 'First', completed: false),
  ];

  @override
  AppEffect<Task> add(String title) => .sync(() {
    final task = Task(
      id: TaskId(tasks.length + 1),
      title: title,
      completed: false,
    );
    tasks.add(task);
    return task;
  });

  @override
  AppEffect<List<Task>> all() => .succeed(List<Task>.unmodifiable(tasks));

  @override
  AppEffect<Task> toggle(TaskId id) => .sync(() {
    final index = tasks.indexWhere((task) => task.id == id);
    final current = tasks[index];
    final updated = current.copyWith(completed: !current.completed);
    tasks[index] = updated;
    return updated;
  });
}

void main() {
  test('ViewModel projects EffectCommand successes into UI state', () async {
    final repository = FakeTaskRepository();
    final runtime = await Module([
      .instance<TaskRepository>(repository),
    ]).start();
    final viewModel = TasksViewModel(EffectCommands(runtime));

    // Await the latest load requested after the constructor-triggered load.
    await viewModel.load.execute();
    expect(viewModel.tasks.single.title, 'First');

    await viewModel.add.execute('Second');
    expect(viewModel.tasks.length, 2);

    await viewModel.toggle.execute(const TaskId(1));
    expect(viewModel.tasks.first.completed, isTrue);

    viewModel.dispose();
    await runtime.close();
  });
}
