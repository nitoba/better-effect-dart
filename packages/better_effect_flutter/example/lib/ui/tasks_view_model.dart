import 'dart:async';

import 'package:better_effect_flutter/better_effect_flutter.dart';

import '../data/task_repository.dart';
import '../domain/app_failure.dart';
import '../domain/task.dart';

final class TasksViewModel extends EffectViewModel {
  late final EffectCommand0<List<Task>, AppFailure> load;

  late final EffectCommand<String, Task, AppFailure> add;
  late final EffectCommand<TaskId, Task, AppFailure> toggle;
  List<Task> _tasks = const <Task>[];

  TasksViewModel(super.commands) {
    load = command<List<Task>, AppFailure>(
      _load,
      concurrency: EffectCommandConcurrency.latest,
      debugLabel: 'TasksViewModel.load',
      stateObserver: _onLoadState,
    );

    add = commandWithInput<String, Task, AppFailure>(
      _add,
      debugLabel: 'TasksViewModel.add',
      stateObserver: _onAddState,
    );

    toggle = commandWithInput<TaskId, Task, AppFailure>(
      _toggle,
      concurrency: EffectCommandConcurrency.queue,
      debugLabel: 'TasksViewModel.toggle',
      stateObserver: _onToggleState,
    );

    unawaited(load.execute());
  }

  bool get isEmpty => _tasks.isEmpty;

  List<Task> get tasks => _tasks;

  AppEffect<Task> _add(String title) => .result((use) async {
    final repository = use<TaskRepository>();
    return use.unwrap(repository.add(title));
  });

  AppEffect<List<Task>> _load() => .result((use) async {
    final repository = use<TaskRepository>();
    return use.unwrap(repository.all());
  });

  void _onAddState(EffectCommandState<Task, AppFailure> state) {
    if (state case EffectCommandSuccess<Task, AppFailure>(:final value)) {
      _tasks = List<Task>.unmodifiable(<Task>[..._tasks, value]);
      notifyListeners();
    }
  }

  void _onLoadState(EffectCommandState<List<Task>, AppFailure> state) {
    if (state case EffectCommandSuccess<List<Task>, AppFailure>(:final value)) {
      _tasks = List<Task>.unmodifiable(value);
      notifyListeners();
    }
  }

  void _onToggleState(EffectCommandState<Task, AppFailure> state) {
    if (state case EffectCommandSuccess<Task, AppFailure>(:final value)) {
      _tasks = List<Task>.unmodifiable(
        _tasks.map((task) => task.id == value.id ? value : task),
      );
      notifyListeners();
    }
  }

  AppEffect<Task> _toggle(TaskId id) => .result((use) async {
    final repository = use<TaskRepository>();
    return use.unwrap(repository.toggle(id));
  });
}
