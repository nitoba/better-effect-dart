part of '../../better_effect.dart';

/// A typed name for distinguishing multiple implementations of the same type.
///
/// Most services can be resolved only by type:
///
/// ```dart
/// final database = use<Database>();
/// ```
///
/// Use a [ServiceKey] only when the same contract has multiple registrations:
///
/// ```dart
/// const primaryDatabase = ServiceKey<Database>('primary');
/// const analyticsDatabase = ServiceKey<Database>('analytics');
/// ```
final class ServiceKey<T extends Object> {
  const ServiceKey(this.name) : assert(name != '');

  /// The logical name of this registration.
  final String name;

  /// The service type represented by this key.
  Type get serviceType => T;

  String get _backendKey => '${T.toString()}::$name';

  @override
  bool operator ==(Object other) {
    return other is ServiceKey<T> && other.name == name;
  }

  @override
  int get hashCode => Object.hash(T, name);

  @override
  String toString() => 'ServiceKey<$T>($name)';
}
