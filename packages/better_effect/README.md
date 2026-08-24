# better_effect

[![pub package](https://img.shields.io/pub/v/better_effect.svg)](https://pub.dev/packages/better_effect)
[![Dart SDK](https://img.shields.io/badge/Dart-%E2%89%A53.10.0-0175C2.svg)](https://dart.dev/)

`better_effect` é um runtime Dart para descrever operações lazy com falhas tipadas, resolver dependências no contexto da execução e controlar o ciclo de vida de recursos sem depender de estado global.

Um `Effect<A, E>` produz `A` em caso de sucesso ou `E` para uma falha esperada. Exceções inesperadas, erros de programação, falhas de resolução e problemas de cleanup continuam sendo **defects** e podem ser observados separadamente com `Exit`.

O package é Dart-only. Ele não depende de Flutter, não é um state manager e não exige que toda função da aplicação vire um `Effect`.

## Quando faz sentido usar

Use `better_effect` quando a aplicação precisa combinar I/O, falhas de domínio, dependências substituíveis e recursos com ownership explícito. Ele é especialmente útil em repositories, use cases, workers, CLIs, backends Dart e na camada compartilhada de aplicações Flutter.

Para lógica pura, transformações síncronas ou um fluxo assíncrono pequeno que já é bem representado por `Future`/`Result`, manter Dart normal costuma ser suficiente.

## Requisitos

- Dart `>=3.10.0 <4.0.0`;
- `result_dart` `^2.2.0`;
- `auto_injector` `^2.2.0`.

A linha documentada aqui é `0.4.x`.

## Instalação

```bash
dart pub add better_effect
```

Ou, no `pubspec.yaml`:

```yaml
dependencies:
  better_effect: ^0.4.0
```

## Primeiro Effect

O exemplo abaixo é completo: declara um serviço, registra sua implementação, descreve uma operação e deixa o `Module` criar e fechar o `Runtime` automaticamente.

```dart
import 'package:better_effect/better_effect.dart';

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

Future<void> main() async {
  final result = await appModule.run(greeting('Dart'));

  result.fold(
    print,
    (failure) => print('Falha esperada: $failure'),
  );
}
```

Criar `greeting('Dart')` não executa a operação. O trabalho começa apenas quando um `Runtime` executa o `Effect`.

## Modelo mental

| Peça | Responsabilidade |
| --- | --- |
| `Effect<A, E>` | Descreve uma operação lazy com sucesso `A` e falha esperada `E`. |
| `EffectContext<E>` | Resolve serviços, compõe Effects/Results e adquire recursos durante a execução. |
| `Module` | Declara bindings, lifetimes, instâncias e recursos. |
| `Runtime` | Materializa o ambiente, executa Effects e coordena scopes e shutdown. |
| `Scope` | É o owner de finalizers, recursos e child scopes. |
| `Exit<A, E>` | Preserva sucesso, falha tipada, defect ou interrupção. |

`Module.run(effect)` é a opção curta para uma execução. Para um processo de vida longa, crie um `Runtime` e feche-o no boundary que possui esse runtime:

```dart
final runtime = await appModule.start();

try {
  await runtime.run(syncUsers());
  await runtime.run(syncOrders());
} finally {
  await runtime.close();
}
```

## Falha esperada, defect e interrupção

Falhas que o produto conhece devem entrar no tipo `E`. Defects são eventos inesperados que não devem ser silenciosamente convertidos em uma falha de domínio.

```dart
final exit = await appModule.runExit(loadUser('42'));

switch (exit) {
  case ExitSuccess(:final value):
    print(value);
  case ExitFailure(:final error):
    print('Falha esperada: $error');
  case ExitDefect(:final defect, :final stackTrace):
    print('Defect: $defect\n$stackTrace');
  case ExitInterrupted():
    print('Execução interrompida');
}
```

`Effect.tryAsync` captura objetos que implementam `Exception`. `Error` e outros objetos lançados permanecem defects. Use `Effect.tryAll` somente quando mapear **todo** objeto lançado para o canal tipado for uma decisão intencional.

## Dependências e lifetimes

Bindings constructor-backed usam `lazySingleton` por padrão:

```dart
final module = Module([
  .instance(const AppConfig(baseUrl: 'https://api.example.com')),
  .provide<HttpClient>(HttpClientLive.new),
  .factory<CreateOrder>(CreateOrder.new),
]);
```

As opções são `factory`, `singleton`, `lazySingleton`, `instance` e `resource`. Use `ServiceKey<T>` somente quando o mesmo contrato precisa de múltiplas identidades.

`use<T>()` resolve a dependência no ambiente da execução; isso não cria um service locator global. Constructor injection e resolução contextual podem coexistir.

## Recursos e ownership

Recursos declarados no `Module` pertencem ao `Runtime` e são adquiridos em ordem de declaração e liberados em ordem reversa.

```dart
final module = Module([
  .resource<DatabaseConnection>(
    acquire: (_) => DatabaseConnection.open(),
    release: (connection, exit) => connection.close(),
  ),
]);
```

Recursos de uma única execução devem ser adquiridos com `use.acquire`. Child scopes fecham antes do pai; finalizers são executados em ordem reversa e falhas de release são agregadas.

## Concorrência e retry

`Effect.all` e `Effect.forEach` são sequenciais por padrão (`concurrency: 1`). Com um limite maior, preservam a ordem de saída conforme a entrada e param de iniciar novos itens depois de uma falha, defect ou interrupção. O trabalho já iniciado continua sob ownership do `Runtime` até terminar.

```dart
final users = Effect.forEach(
  userIds,
  loadUser,
  concurrency: 4,
);
```

Fan-out sem limite é explícito com `Effect.allUnbounded` e `Effect.forEachUnbounded`.

`Effect.retry` repete apenas falhas tipadas. Cada tentativa tem um child `Scope` próprio, fechado antes da decisão, do delay ou da próxima tentativa.

```dart
final resilient = request().retry(
  RetryPolicy.exponential(
    maxAttempts: 4,
    initialDelay: const Duration(milliseconds: 200),
    maxDelay: const Duration(seconds: 3),
  ),
);
```

Policies com delay precisam de `EffectClock`; jitter precisa de `EffectRandom`. Esses serviços não são registrados implicitamente.

## Ambientes temporários e child Runtimes

Use `runWith`/`runExitWith` para providers e recursos que pertencem a uma execução. Use `Runtime.fork` quando um ambiente precisa sobreviver a várias execuções, mas deve fechar antes do runtime pai.

```dart
final featureRuntime = await runtime.fork(
  featureModule,
  label: 'checkout',
);

try {
  await featureRuntime.run(loadCheckout());
} finally {
  await featureRuntime.close();
}
```

Backends customizados precisam implementar `ResolverBackendOverlayFactory` para suportar esses overlays. `AutoInjectorBackend`, usado por padrão, já oferece esse suporte.

## Cancelamento: lógico não é físico

Dart não oferece cancelamento físico geral para qualquer `Future`. `EffectExecution.interrupt()` publica uma interrupção lógica e disponibiliza um `CancellationSignal`, mas o `Runtime` continua possuindo a operação e o `Scope` até o trabalho físico terminar.

O mesmo vale para `timeout`: o caller pode receber a falha de timeout antes da conclusão do `Future` original, sem liberar recursos ainda em uso.

## Testes

Para testes de runtime, importe a biblioteca dedicada:

```dart
import 'package:better_effect/testing.dart';
```

Ela disponibiliza `TestRuntime`, clock manual, primitives determinísticas, matchers de `Exit`, `RecordingRuntimeObserver` e o contrato para validar implementações customizadas de `ResolverBackend`.

Para substituir dependências de um grafo existente, `Module.overrideWith` mantém a mesma operação e troca apenas bindings correspondentes.

## Limitações importantes

- `Effect` não cancela fisicamente `Future`s arbitrários;
- defects não entram automaticamente no tipo `E`;
- `EffectClock` e `EffectRandom` não são globais nem implícitos;
- backends customizados precisam oferecer overlays para `runWith` e `fork`;
- o package não substitui state management, roteamento ou um framework de aplicação.

## Documentação e referência

- [Documentação oficial](https://better-effect-dart.vercel.app/docs)
- [API no pub.dev](https://pub.dev/documentation/better_effect/latest/)
- [Contrato semântico](https://github.com/nitoba/better-effect-dart/blob/main/SEMANTICS.md)
- [CHANGELOG](CHANGELOG.md)
- [Repositório e issues](https://github.com/nitoba/better-effect-dart)

Para agentes de IA, a documentação também publica [llms.txt](https://better-effect-dart.vercel.app/llms.txt) e [llms-full.txt](https://better-effect-dart.vercel.app/llms-full.txt). A versão instalada no projeto continua sendo a fonte para decidir se uma API está disponível.

## Contribuição e licença

Issues e Pull Requests são bem-vindos. Antes de enviar uma mudança, execute os checks do package descritos no README raiz do monorepo e preserve o contrato de `SEMANTICS.md` quando a alteração afetar lifecycle ou outcomes.

Licença MIT. Consulte [LICENSE](LICENSE).
