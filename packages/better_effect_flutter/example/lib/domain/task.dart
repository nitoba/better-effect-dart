final class Task {
  final TaskId id;

  final String title;
  final bool completed;
  const Task({required this.id, required this.title, required this.completed});

  @override
  int get hashCode => Object.hash(id, title, completed);

  @override
  bool operator ==(Object other) {
    return other is Task &&
        other.id == id &&
        other.title == title &&
        other.completed == completed;
  }

  Task copyWith({String? title, bool? completed}) {
    return Task(
      id: id,
      title: title ?? this.title,
      completed: completed ?? this.completed,
    );
  }
}

extension type const TaskId(int value) {}
