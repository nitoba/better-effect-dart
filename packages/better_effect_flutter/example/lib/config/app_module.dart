import 'package:better_effect_flutter/better_effect_flutter.dart';

import '../data/task_repository.dart';
import '../data/task_service.dart';

final appModule = Module([
  .provide<TaskService>(InMemoryTaskService.new),
  .provide<TaskRepository>(TaskRepositoryLive.new),
]);
