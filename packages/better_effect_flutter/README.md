# better_effect_flutter

[![pub package](https://img.shields.io/pub/v/better_effect_flutter.svg)](https://pub.dev/packages/better_effect_flutter)
[![Flutter](https://img.shields.io/badge/Flutter-%E2%89%A53.38.0-02569B.svg)](https://flutter.dev/)

`better_effect_flutter` conecta o runtime Dart de `better_effect` ao ciclo de vida e à UI do Flutter. Um `Effect<A, E>` passa a ser executado por um `EffectCommand` e projetado em um estado selado que distingue loading, sucesso, falha esperada, defect e interrupção.

O package não substitui Provider, Riverpod, BLoC, Signals, MobX ou outra solução de state management. Ele fornece uma fronteira de execução e lifecycle que pode ser usada por essas ferramentas.

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

O package reexporta `better_effect`, portanto a maioria das aplicações precisa de um único import:

```dart
import 'package:better_effect_flutter/better_effect_flutter.dart';
```

## Primeiro fluxo funcional

### 1. Declare a operação e o Module

```dart
import 'package:better_effect_flutter/better_effect_flutter.dart';

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
```

### 2. Inicie o Runtime no boundary da aplicação

```dart
Future<void> main() {
  return runBetterEffectApp(
    module: appModule,
    app: const GreetingApp(),
  );
}
```

`runBetterEffectApp` inicia um Runtime de aplicação e publica `BetterEffectScope` na árvore. Para startup declarativo com loading/error/retry, use `BetterEffectBootstrap`. Quando outro boundary já possui o Runtime, use `BetterEffectProvider.value`.

### 3. Crie um ViewModel com Command

```dart
final class GreetingViewModel extends EffectViewModel {
  GreetingViewModel(super.commands) {
    greet = commandWithInput<String, String, GreetingFailure>(
      greeting,
      keepPreviousData: false,
      debugLabel: 'GreetingViewModel.greet',
    );
  }

  late final EffectCommand<String, String, GreetingFailure> greet;
}
```

`EffectViewModel` é opcional. Se a aplicação já possui uma classe base de ViewModel, use o mixin `EffectCommandOwner` para possuir e descartar Commands automaticamente.

### 4. Construa o ViewModel no boundary Flutter

```dart
EffectViewModelBuilder<GreetingViewModel>(
  create: (_, commands) => GreetingViewModel(commands),
  builder: (_, viewModel, _) => GreetingView(viewModel: viewModel),
)
```

Adapters de Provider/Riverpod/BLoC podem obter a factory scoped com `context.effectCommands`. `context.effectRuntime` e `readEffectService` existem para boundaries de integração; widgets de negócio normalmente devem conversar com o ViewModel.

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

A View pode usar pattern matching exaustivo:

```dart
Widget render(EffectCommandState<String, GreetingFailure> state) {
  return switch (state) {
    EffectCommandIdle() => const Text('Informe um nome'),
    EffectCommandRunning() => const CircularProgressIndicator(),
    EffectCommandSuccess(:final value) => Text(value),
    EffectCommandFailure() => const Text('Não foi possível carregar'),
    EffectCommandDefect(:final defect) => Text('Erro inesperado: $defect'),
    EffectCommandInterrupted() => const Text('Operação interrompida'),
  };
}
```

`execute()` retorna `Future<Exit<A, E>>`, então código imperativo também pode aguardar o mesmo trabalho sem duplicar estado.

## Renderização e efeitos one-shot

Use `EffectCommandBuilder` quando a UI precisa renderizar o estado do Command. Use `EffectCommandListener` para navegação, diálogo, SnackBar, analytics e outros efeitos de apresentação.

O listener consome cada `revision` uma vez e despacha callbacks após o frame. Não é necessário chamar `clearError()` ou manter uma flag manual para impedir que a mesma navegação aconteça novamente.

`EffectCommandSelector` permite observar uma projeção do estado ou do `EffectCommandSnapshot`; `EffectCommandBuilder.buildWhen` é útil quando a View ainda precisa do estado completo, mas quer filtrar rebuilds.

## Políticas de execução

Novos códigos devem preferir `CommandPolicy`:

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

O `Runtime` mantém a execução e seus recursos até o trabalho físico terminar. Essa diferença também vale para `latest(cancelPrevious: true)`, dispose e timeout.

## Runtime e lifecycle no Flutter

| Situação | API |
| --- | --- |
| App possui o Runtime raiz | `runBetterEffectApp` |
| Startup declarativo com loading/error/retry | `BetterEffectBootstrap` |
| Widget possui um Runtime existente | `BetterEffectProvider` |
| Outro boundary possui o Runtime | `BetterEffectProvider.value` |
| Feature precisa de ambiente próprio com fallback para o pai | `BetterEffectFeatureScope` |

`BetterEffectLifecyclePolicy` controla fechamento por widget/application exit, grace period e solicitação de interrupção cooperativa. A API distingue ownership `external`, `widget` e `application` para impedir que um subtree feche um Runtime que não possui.

Observação de plataforma: callbacks canceláveis de exit dependem do suporte do Flutter desktop; o callback de detach usado pelo framework tem comportamento específico de iOS/Android. Não trate um único callback de lifecycle como garantia idêntica entre todas as plataformas.

## Feature scopes

`BetterEffectFeatureScope` cria um child `Runtime` que resolve providers locais primeiro e usa o Runtime pai como fallback. Os recursos da feature sobrevivem a várias telas, ViewModels e Commands e fecham no dispose/restart da feature.

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

Fechar o child não fecha o pai; fechar o pai coordena seus child Runtimes antes dos recursos parentais.

## Testes

Importe a biblioteca dedicada quando precisar de harnesses de widget/Command:

```dart
import 'package:better_effect_flutter/testing.dart';
```

O package também inclui uma aplicação executável em `example/` e testes para lifecycle, policies, one-shot listeners, selectors e ownership de Runtime.

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

- [Documentação oficial](https://better-effect-dart.vercel.app/docs)
- [Guia Flutter MVVM](https://better-effect-dart.vercel.app/docs/guides/flutter-mvvm)
- [Políticas de Command](https://better-effect-dart.vercel.app/docs/guides/command-policies)
- [Feature scopes](https://better-effect-dart.vercel.app/docs/guides/feature-scopes)
- [API no pub.dev](https://pub.dev/documentation/better_effect_flutter/latest/)
- [Repositório e issues](https://github.com/nitoba/better-effect-dart)

Para agentes de IA, use [llms.txt](https://better-effect-dart.vercel.app/llms.txt) como mapa da documentação e sempre confirme a versão instalada antes de aplicar uma API.

## Contribuição e licença

Issues e Pull Requests são bem-vindos. Valide o package e a aplicação em `example/` antes de enviar mudanças de lifecycle ou Commands.

Licença MIT. Consulte [LICENSE](LICENSE).
