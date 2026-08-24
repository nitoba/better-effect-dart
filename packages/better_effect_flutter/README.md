# better_effect_flutter

[![pub package](https://img.shields.io/pub/v/better_effect_flutter.svg)](https://pub.dev/packages/better_effect_flutter)
[![Flutter](https://img.shields.io/badge/Flutter-%E2%89%A53.38.0-02569B.svg)](https://flutter.dev/)

`better_effect_flutter` conecta o runtime Dart de `better_effect` ao ciclo de vida e à UI do Flutter. Um `Effect<A, E>` continua sendo o mesmo programa do core; a camada Flutter executa esse Effect por meio de um `EffectCommand` e projeta seu outcome em um estado selado que distingue loading, sucesso, falha esperada, defect e interrupção.

O package **depende de `better_effect` e reexporta sua API pública**. `Module`, `Runtime`, `Scope`, resources, retry, concorrência, `EffectLocal`, `RuntimeObserver` e testing do core continuam disponíveis em uma aplicação Flutter. Não existe um segundo runtime para Flutter.

O package também não substitui Provider, Riverpod, BLoC, Signals, MobX ou outra solução de state management. Ele fornece uma fronteira de execução e lifecycle que pode ser usada por essas ferramentas.

## Como Dart e Flutter se encaixam

```text
better_effect
Module → Runtime → Effect<A, E> → Exit<A, E>
                    │
                    │ executado pela camada Flutter
                    ▼
better_effect_flutter
BetterEffectScope
      ↓
EffectCommands
      ↓
EffectCommand
      ↓
EffectCommandState
      ↓
Builder / Listener / Consumer / Selector
```

Repositories, services e use cases continuam retornando `Effect<A, E>`. O Command é o adapter que possui uma execução para a UI; ele não substitui o Effect nem muda sua semântica.

## Quando faz sentido usar

Use o package quando a UI precisa representar falhas de domínio separadas de bugs/defects, controlar chamadas repetidas com políticas explícitas, executar efeitos one-shot como navegação e SnackBars sem flags manuais e manter um `Runtime` com ownership claro no widget tree.

Se a tela só precisa aguardar um `Future` simples e não há necessidade de DI contextual, falhas tipadas ou coordenação de execuções, um `FutureBuilder` pode ser suficiente.

## Requisitos

- Dart `>=3.10.0 <4.0.0`;
- Flutter `>=3.38.0`;
- `better_effect` `^0.4.0`.

A linha documentada aqui é `0.4.x`.

## Instalação

```bash
flutter pub add better_effect_flutter
```

Ou:

```yaml
dependencies:
  better_effect_flutter: ^0.4.0
```

A maioria das aplicações precisa de um único import:

```dart
import 'package:better_effect_flutter/better_effect_flutter.dart';
```

## Mapa completo da integração Flutter

### Runtime e scopes

| API | Quando usar |
| --- | --- |
| `runBetterEffectApp` | iniciar a app e possuir o Runtime raiz com o menor boilerplate |
| `BetterEffectBootstrap` | startup declarativo com loading, erro, retry e `restartKey` |
| `BetterEffectProvider` | publicar um Runtime existente que o widget/application boundary possui |
| `BetterEffectProvider.value` | publicar um Runtime cujo owner está fora da árvore |
| `BetterEffectScope` | `InheritedWidget` que expõe `Runtime` + `EffectCommands` |
| `BetterEffectFeatureScope` | child Runtime que vive durante uma feature e faz fallback para o pai |

### Commands e ViewModels

| API | Quando usar |
| --- | --- |
| `EffectCommands` | factory scoped de Commands ligados ao Runtime |
| `EffectCommand0<A, E>` | operação sem input |
| `EffectCommand<I, A, E>` | operação com input tipado |
| `EffectCommandState<A, E>` | estado selado da execução |
| `EffectCommandSnapshot<A, E>` | estado + `lastExit`, pending, queue e trigger metadata |
| `EffectViewModel` | classe base opcional que cria e possui Commands |
| `EffectCommandOwner` | mixin para outra classe base de ViewModel |
| `EffectViewModelBuilder` | cria, observa, recria e descarta ViewModel no scope atual |

### Widgets de Command

| Widget | Responsabilidade |
| --- | --- |
| `EffectCommandBuilder` | renderizar `EffectCommandState`; suporta `buildWhen` e `child` |
| `EffectCommandListener` | side effects one-shot; suporta `listenWhen`, callbacks por estado e `fireImmediately` |
| `EffectCommandConsumer` | combinar Builder + Listener no mesmo boundary |
| `EffectCommandSelector` | rebuild somente quando uma projeção selecionada muda |
| `EffectCommandSelector.snapshot` | selecionar `pendingCount`, `queuedCount`, `triggerPendingCount`, `lastExit` ou `policy` |

### Context e observabilidade

`BuildContext` recebe `effectCommands`, `watchEffectCommands()`, `effectRuntime`, `runEffect`, `runEffectExit` e `readEffectService`. Commands podem ser observados globalmente por `EffectCommandObserver`/`EffectCommandTransition` e `EffectCommandPolicyObserver`.

### Testing

`package:better_effect_flutter/testing.dart` adiciona `BetterEffectTestApp` e probes para estado, listener e policy. O helper usa ownership externo e deixa o teste responsável por fechar o Runtime.

A documentação completa de cada item está em [better_effect_flutter](https://better-effect-dart.vercel.app/docs/packages/better_effect_flutter).

## Primeiro exemplo funcional

Coloque este exemplo em `lib/main.dart`. Ele cria o Runtime da aplicação, resolve um serviço dentro de um `Effect`, executa a operação com um `EffectCommand` e renderiza o estado tipado.

```dart
import 'package:better_effect_flutter/better_effect_flutter.dart';
import 'package:flutter/material.dart';

sealed class GreetingFailure implements Exception {
  const GreetingFailure();
}

final class GreetingUnavailable extends GreetingFailure {
  const GreetingUnavailable(this.cause);
  final Exception cause;
}

abstract interface class GreetingService {
  Future<String> greet(String name);
}

final class GreetingServiceLive implements GreetingService {
  @override
  Future<String> greet(String name) async => 'Olá, $name!';
}

final appModule = Module([
  .provide<GreetingService>(GreetingServiceLive.new),
]);

Effect<String, GreetingFailure> greeting(String name) =>
    Effect.result((use) async {
      final service = use<GreetingService>();

      return use.tryAsync(
        () => service.greet(name),
        onError: (error, stackTrace) => GreetingUnavailable(error),
      );
    });

final class GreetingViewModel extends EffectViewModel {
  GreetingViewModel(super.commands) {
    greet = command<String, GreetingFailure>(
      () => greeting('Flutter'),
      keepPreviousData: false,
      debugLabel: 'GreetingViewModel.greet',
    );
  }

  late final EffectCommand0<String, GreetingFailure> greet;
}

final class GreetingPage extends StatelessWidget {
  const GreetingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return EffectViewModelBuilder<GreetingViewModel>(
      create: (_, commands) => GreetingViewModel(commands),
      builder: (context, viewModel, child) {
        return Scaffold(
          appBar: AppBar(title: const Text('better_effect_flutter')),
          body: Center(
            child: EffectCommandBuilder<String, GreetingFailure>(
              command: viewModel.greet,
              builder: (context, state, child) => switch (state) {
                EffectCommandIdle() => const Text('Toque para executar'),
                EffectCommandRunning() =>
                  const CircularProgressIndicator(),
                EffectCommandSuccess(:final value) => Text(value),
                EffectCommandFailure() =>
                  const Text('Falha esperada'),
                EffectCommandDefect(:final defect) =>
                  Text('Defect: $defect'),
                EffectCommandInterrupted() =>
                  const Text('Execução interrompida'),
              },
            ),
          ),
          floatingActionButton: FloatingActionButton(
            onPressed: () {
              viewModel.greet.execute();
            },
            child: const Icon(Icons.play_arrow),
          ),
        );
      },
    );
  }
}

Future<void> main() {
  return runBetterEffectApp(
    module: appModule,
    app: const MaterialApp(home: GreetingPage()),
  );
}
```

Execute com `flutter run`. Antes do toque, a tela está em `EffectCommandIdle`; durante a operação, em `EffectCommandRunning`; ao concluir, renderiza `Olá, Flutter!` a partir de `EffectCommandSuccess`.

## O estado de um Command

`EffectCommandState<A, E>` é selado:

| Estado | Significado |
| --- | --- |
| `EffectCommandIdle` | Ainda não executou ou foi resetado. |
| `EffectCommandRunning` | Há uma execução autoritativa em andamento. |
| `EffectCommandSuccess` | O Effect produziu `A`. |
| `EffectCommandFailure` | O Effect produziu a falha tipada `E`. |
| `EffectCommandDefect` | Houve um evento inesperado fora do canal tipado. |
| `EffectCommandInterrupted` | O Command deixou de possuir o resultado da execução. |

`execute()` retorna `Future<Exit<A, E>>`, então código imperativo também pode aguardar o mesmo trabalho sem duplicar estado.

## Builder, Listener, Consumer e Selector

### `EffectCommandBuilder`

Use quando a UI precisa apenas renderizar estado. `buildWhen` pode filtrar transições; `child` preserva uma subtree estática.

### `EffectCommandListener`

Use para navegação, diálogo, SnackBar, analytics e outros efeitos de apresentação. Ele oferece callbacks `onIdle`, `onRunning`, `onSuccess`, `onFailure`, `onDefect`, `onInterrupted` e `onChanged`, além de `listenWhen` e `fireImmediately`.

O listener consome cada `revision` uma vez e despacha callbacks após o frame. Não é necessário chamar `clearError()` ou manter uma flag manual para impedir que a mesma navegação aconteça novamente.

### `EffectCommandConsumer`

Combina Listener e Builder. Use quando o mesmo boundary precisa renderizar e executar side effects. `buildWhen` e `listenWhen` continuam independentes.

### `EffectCommandSelector`

Permite observar apenas uma projeção. A variante `.snapshot` observa também fila, pending, trigger, `lastExit` e policy sem transformar essas métricas em novo estado visual.

## Políticas de execução

Para código novo que precisa de coordenação além do default, prefira `CommandPolicy`:

```dart
search = commandWithInput<String, List<User>, SearchFailure>(
  searchUsers,
  policy: const CommandPolicy.latest(
    cancelPrevious: true,
    trigger: TriggerPolicy.debounce(
      Duration(milliseconds: 300),
    ),
  ),
);
```

As três coordenações são:

- `drop`: reutiliza a execução ativa e não inicia duplicata;
- `latest`: aceita novas execuções, mas apenas a mais nova possui o estado visível;
- `queue`: serializa as execuções em FIFO.

`TriggerPolicy.debounce` e `TriggerPolicy.throttle` só são válidos para Commands com input e usam o serviço contextual `EffectClock`. Filas podem definir `maxPending` e `QueueOverflow`.

`EffectCommandConcurrency` continua disponível como shorthand de compatibilidade para `drop`, `latest` e `queue`, mas não deve ser combinado com `policy` na mesma criação de Command.

## Cancelamento e ownership físico

`command.cancel()` interrompe a ownership lógica do Command e pode limpar callers enfileirados/trigger-delayed. Isso **não** significa que o `Future` subjacente foi fisicamente cancelado.

O `Runtime` mantém a execução e seus resources até o trabalho físico terminar. Essa diferença também vale para `latest(cancelPrevious: true)`, dispose e timeout.

Quando uma API externa oferece cancelamento, conecte-a ao `use.cancellation` dentro do `Effect` ou cruze um boundary cooperativo com `use.cancellation.throwIfCancelled()`.

## Runtime e lifecycle no Flutter

| Situação | API |
| --- | --- |
| App possui o Runtime raiz | `runBetterEffectApp` |
| Startup declarativo com loading/error/retry | `BetterEffectBootstrap` |
| Widget possui um Runtime existente | `BetterEffectProvider` |
| Outro boundary possui o Runtime | `BetterEffectProvider.value` |
| Feature precisa de ambiente próprio com fallback para o pai | `BetterEffectFeatureScope` |

`BetterEffectLifecyclePolicy` controla fechamento por widget/application exit, grace period e solicitação de interrupção cooperativa. A API distingue ownership `external`, `widget` e `application` para impedir que um subtree feche um Runtime que não possui.

## Feature scopes

`BetterEffectFeatureScope` cria um child `Runtime` que resolve providers locais primeiro e usa o Runtime pai como fallback. Os resources da feature sobrevivem a várias telas, ViewModels e Commands e fecham no dispose/restart da feature.

```dart
BetterEffectFeatureScope(
  module: checkoutModule,
  label: 'checkout',
  loadingBuilder: (_) => const CheckoutLoading(),
  errorBuilder: (_, error, stackTrace, retry) =>
      CheckoutStartupError(error: error, onRetry: retry),
  builder: (_) => const CheckoutFlow(),
)
```

Fechar o child não fecha o pai; fechar o pai coordena seus child Runtimes antes dos resources parentais.

## BuildContext

- `context.effectCommands`: read non-listening para factories de ViewModel;
- `context.watchEffectCommands()`: versão listening para adapters que precisam reagir à troca de scope;
- `context.effectRuntime`: acesso direto ao Runtime no boundary;
- `context.runEffect` / `runEffectExit`: execução direta sem Command observável;
- `context.readEffectService<T>()`: resolução no composition boundary, não uma recomendação para business logic no `build`.

## Testes

Importe a biblioteca dedicada quando precisar de harnesses de widget/Command:

```dart
import 'package:better_effect_flutter/testing.dart';
```

Ela reexporta os helpers de testing do core e adiciona probes de estado/listener/policy e `BetterEffectTestApp`.

`BetterEffectTestApp` usa `BetterEffectProvider.value`: o teste continua owner do Runtime e deve fechá-lo.

## Limitações importantes

- Commands não cancelam fisicamente `Future`s arbitrários;
- debounce/throttle dependem de `EffectClock` resolvível no Runtime;
- `EffectViewModel` é uma conveniência, não uma regra de “um ViewModel por tela”;
- o package não substitui state management, roteamento ou uma arquitetura completa;
- `readEffectService` é uma API de composition boundary, não uma recomendação para acessar repositories diretamente no build de widgets.

## Compatibilidade e migração

Na linha `0.4.x`, prefira `CommandPolicy` quando precisar combinar coordenação, cancelamento, debounce/throttle ou fila limitada. O parâmetro `concurrency` existe para compatibilidade e mapeia para a policy correspondente.

Os parâmetros legados `closeRuntimeOnDetach` e `closeRuntimeOnDispose` estão depreciados; use `BetterEffectLifecyclePolicy` e ownership explícito.

Consulte o [CHANGELOG](CHANGELOG.md) antes de atualizar uma aplicação existente.

## Documentação e referência

- [Mapa completo do package Flutter](https://better-effect-dart.vercel.app/docs/packages/better_effect_flutter)
- [Flutter: integração completa](https://better-effect-dart.vercel.app/docs/guides/flutter-mvvm)
- [Core `better_effect`](https://better-effect-dart.vercel.app/docs/packages/better_effect)
- [Políticas de Command](https://better-effect-dart.vercel.app/docs/guides/command-policies)
- [Seletores](https://better-effect-dart.vercel.app/docs/guides/command-selectors)
- [Feature scopes](https://better-effect-dart.vercel.app/docs/guides/feature-scopes)
- [API no pub.dev](https://pub.dev/documentation/better_effect_flutter/latest/)
- [Repositório e issues](https://github.com/nitoba/better-effect-dart)

Para agentes de IA, use [llms.txt](https://better-effect-dart.vercel.app/llms.txt) como mapa da documentação e sempre confirme a versão instalada antes de aplicar uma API.

## Contribuição e licença

Issues e Pull Requests são bem-vindos. Valide o package e a aplicação em `example/` antes de enviar mudanças de lifecycle ou Commands.

Licença MIT. Consulte [LICENSE](LICENSE).
