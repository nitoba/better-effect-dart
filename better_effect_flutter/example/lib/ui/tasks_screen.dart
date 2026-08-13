import 'package:better_effect_flutter/better_effect_flutter.dart';
import 'package:flutter/material.dart';

import '../domain/app_failure.dart';
import '../domain/task.dart';
import 'tasks_view_model.dart';

final class TasksApp extends StatelessWidget {
  const TasksApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'better_effect_flutter',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const TasksScreen(),
    );
  }
}

final class TasksScreen extends StatelessWidget {
  const TasksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return EffectViewModelBuilder<TasksViewModel>(
      create: (_, commands) => TasksViewModel(commands),
      builder: (context, viewModel, _) {
        return _TasksView(viewModel: viewModel);
      },
    );
  }
}

final class _ErrorState extends StatelessWidget {
  final String message;

  final Future<Exit<List<Task>, AppFailure>> Function() onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.error_outline, size: 56),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

final class _TasksView extends StatelessWidget {
  final TasksViewModel viewModel;

  const _TasksView({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return EffectCommandListener<Task, AppFailure>(
      command: viewModel.add,
      onSuccess: (context, task) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Added “${task.title}”.')));
      },
      onFailure: (context, error, _) => _showFailure(context, error),
      onDefect: (context, defect, stackTrace, _) {
        _showDefect(context, defect, stackTrace);
      },
      child: EffectCommandListener<Task, AppFailure>(
        command: viewModel.toggle,
        onFailure: (context, error, _) => _showFailure(context, error),
        onDefect: (context, defect, stackTrace, _) {
          _showDefect(context, defect, stackTrace);
        },
        child: Scaffold(
          appBar: AppBar(
            title: const Text('Typed Flutter tasks'),
            actions: <Widget>[
              EffectCommandBuilder<List<Task>, AppFailure>(
                command: viewModel.load,
                builder: (context, state, _) {
                  return IconButton(
                    tooltip: 'Refresh',
                    onPressed: state.isRunning
                        ? null
                        : () => viewModel.load.execute(),
                    icon: const Icon(Icons.refresh),
                  );
                },
              ),
            ],
          ),
          body: EffectCommandBuilder<List<Task>, AppFailure>(
            command: viewModel.load,
            builder: (context, state, _) {
              return _buildBody(context, state);
            },
          ),
          floatingActionButton: EffectCommandBuilder<Task, AppFailure>(
            command: viewModel.add,
            builder: (context, state, _) {
              return FloatingActionButton.extended(
                onPressed: state.isRunning
                    ? null
                    : () => _openAddDialog(context),
                icon: state.isRunning
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.add),
                label: const Text('Add task'),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    EffectCommandState<List<Task>, AppFailure> state,
  ) {
    final tasks = viewModel.tasks;

    if (state case EffectCommandRunning<List<Task>, AppFailure>(
      previous: null,
    )) {
      return const Center(child: CircularProgressIndicator());
    }

    // Or you can use the following code to show a loading indicator only when the tasks list is empty and the load command is running:
    // if (viewModel.load.isRunning && tasks.isEmpty) {
    //   return const Center(child: CircularProgressIndicator());
    // }

    if (state case EffectCommandFailure<List<Task>, AppFailure>(
      :final error,
      previous: null,
    )) {
      return _ErrorState(
        message: error.message,
        onRetry: viewModel.load.execute,
      );
    }

    if (state case EffectCommandDefect<List<Task>, AppFailure>(
      :final defect,
      previous: null,
    )) {
      return _ErrorState(
        message: 'Unexpected defect: $defect',
        onRetry: viewModel.load.execute,
      );
    }

    if (tasks.isEmpty) {
      return RefreshIndicator(
        onRefresh: () async {
          await viewModel.load.execute();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const <Widget>[
            SizedBox(height: 180),
            Icon(Icons.task_alt, size: 64),
            SizedBox(height: 16),
            Center(child: Text('No tasks yet.')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await viewModel.load.execute();
      },
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: tasks.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final task = tasks[index];

          return Card(
            child: CheckboxListTile(
              value: task.completed,
              title: Text(
                task.title,
                style: task.completed
                    ? const TextStyle(decoration: TextDecoration.lineThrough)
                    : null,
              ),
              onChanged: (_) => viewModel.toggle.execute(task.id),
            ),
          );
        },
      ),
    );
  }

  Future<void> _openAddDialog(BuildContext context) async {
    final controller = TextEditingController();

    final title = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New task'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(labelText: 'Title'),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );

    controller.dispose();

    if (title != null) {
      await viewModel.add.execute(title);
    }
  }

  void _showDefect(BuildContext context, Object defect, StackTrace stackTrace) {
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: defect,
        stack: stackTrace,
        context: ErrorDescription('while executing a task command'),
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('An unexpected error occurred.')),
    );
  }

  void _showFailure(BuildContext context, AppFailure failure) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(failure.message)));
  }
}
