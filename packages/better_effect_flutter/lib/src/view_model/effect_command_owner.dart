part of '../../better_effect_flutter.dart';

/// Disposes every Effect command owned by a [ChangeNotifier].
///
/// Use [ownCommand] when an existing ViewModel base class prevents extending
/// [EffectViewModel].
mixin EffectCommandOwner on ChangeNotifier {
  final List<EffectCommandDisposable> _ownedEffectCommands =
      <EffectCommandDisposable>[];

  /// Register [command] for automatic disposal with this ViewModel.
  @protected
  T ownCommand<T extends EffectCommandDisposable>(T command) {
    _ownedEffectCommands.add(command);
    return command;
  }

  @override
  void dispose() {
    for (final command in _ownedEffectCommands.reversed) {
      if (!command.isDisposed) {
        command.dispose();
      }
    }

    _ownedEffectCommands.clear();
    super.dispose();
  }
}
