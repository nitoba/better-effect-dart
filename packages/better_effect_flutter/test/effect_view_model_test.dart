import 'package:better_effect_flutter/better_effect_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

final class VmFailure implements Exception {
  const VmFailure();
}

final class CounterViewModel extends EffectViewModel {
  CounterViewModel(super.commands) {
    increment = command<int, VmFailure>(
      _increment,
      debugLabel: 'CounterViewModel.increment',
      stateObserver: (state) {
        if (state case EffectCommandSuccess<int, VmFailure>(:final value)) {
          count = value;
          notifyListeners();
        }
      },
    );
  }

  late final EffectCommand0<int, VmFailure> increment;
  int count = 0;

  Effect<int, VmFailure> _increment() =>
      Effect<int, VmFailure>.succeed(count + 1);
}

void main() {
  testWidgets('builder keeps a ViewModel across ordinary parent rebuilds', (
    tester,
  ) async {
    final runtime = await Module(const <Binding>[]).start();
    addTearDown(runtime.close);

    var createCount = 0;
    CounterViewModel? current;

    Widget build(Object? recreateKey) {
      return BetterEffectProvider.value(
        runtime: runtime,
        child: EffectViewModelBuilder<CounterViewModel>(
          recreateKey: recreateKey,
          create: (_, commands) {
            createCount++;
            return CounterViewModel(commands);
          },
          builder: (context, viewModel, _) {
            current = viewModel;
            return Text('${viewModel.count}', textDirection: TextDirection.ltr);
          },
        ),
      );
    }

    await tester.pumpWidget(build(null));
    final first = current;
    expect(createCount, 1);

    // A new inline create closure does not recreate the ViewModel.
    await tester.pumpWidget(build(null));
    expect(createCount, 1);
    expect(current, same(first));

    await current!.increment.execute();
    await tester.pump();
    expect(find.text('1'), findsOneWidget);

    await tester.pumpWidget(build('new-scope'));
    expect(createCount, 2);
    expect(current, isNot(same(first)));
    expect(first!.increment.isDisposed, isTrue);
  });

  test('disposing EffectViewModel disposes owned commands', () async {
    final runtime = await Module(const <Binding>[]).start();
    final viewModel = CounterViewModel(EffectCommands(runtime));

    viewModel.dispose();

    expect(viewModel.increment.isDisposed, isTrue);
    await runtime.close();
  });
}
