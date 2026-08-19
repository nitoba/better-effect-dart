part of '../../better_effect.dart';

/// A read-only, callable view of the services available in a [Runtime].
///
/// This type is primarily useful at composition boundaries such as
/// [Binding.resource]. Business code should normally request services through
/// the `use` value received by [Effect.result].
final class Services {
  const Services._(this._context);

  final _RuntimeContext _context;

  /// Resolve a service by type or by a typed [ServiceKey].
  T call<T extends Object>([ServiceKey<T>? key]) {
    return _context._resolve<T>(key);
  }

  /// Named equivalent of [call] for discoverability.
  T get<T extends Object>([ServiceKey<T>? key]) {
    return _context._resolve<T>(key);
  }
}
