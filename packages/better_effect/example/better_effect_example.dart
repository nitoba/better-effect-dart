import 'package:better_effect/better_effect.dart';

Future<void> main() async {
  final result = await appModule.run(program(UserId('user-1')));

  result.fold(
    (user) => print('Success: $user'),
    (failure) => print('Failure: $failure'),
  );
}

final appModule = Module([
  .provide<Database>(DatabaseLive.new),
  .provide<UserRepository>(UserRepositoryLive.new),
]);

AppEffect<User> program(UserId id) => .result((use) async {
  final users = use<UserRepository>();

  return use.unwrap(users.findUser(id));
});

typedef AppEffect<A extends Object> = Effect<A, AppFailure>;

sealed class AppFailure implements Exception {
  const AppFailure();
}

abstract interface class Database {
  AppEffect<User> findUser(UserId id);
}

final class DatabaseFailure extends AppFailure {
  final String message;

  const DatabaseFailure(this.message);

  factory DatabaseFailure.from(Exception error, StackTrace stackTrace) {
    return DatabaseFailure(error.toString());
  }

  @override
  String toString() => 'DatabaseFailure($message)';
}

final class DatabaseLive implements Database {
  @override
  AppEffect<User> findUser(UserId id) => .result((use) async {
    if (id.value == 'missing') {
      use.fail(UserNotFound(id));
    }

    return use.tryAsync(() async {
      if (id.value == 'database-error') {
        throw const FakeDatabaseException('Database unavailable');
      }

      return User(id: id, name: 'John Doe');
    }, onError: DatabaseFailure.from);
  });
}

final class FakeDatabaseException implements Exception {
  final String message;

  const FakeDatabaseException(this.message);

  @override
  String toString() => message;
}

final class User {
  final UserId id;

  final String name;
  const User({required this.id, required this.name});

  @override
  String toString() => 'User(id: ${id.value}, name: $name)';
}

final class UserNotFound extends AppFailure {
  final UserId id;

  const UserNotFound(this.id);

  @override
  String toString() => 'UserNotFound(${id.value})';
}

abstract interface class UserRepository {
  AppEffect<User> findUser(UserId id);
}

final class UserRepositoryLive implements UserRepository {
  @override
  AppEffect<User> findUser(UserId id) => .result((use) async {
    final database = use<Database>();

    return use.unwrap(database.findUser(id));
  });
}

extension type UserId(String value) {}
