# Regras detalhadas de refatoração

Use este documento durante refatorações não triviais. Ele complementa o `SKILL.md` com critérios mais específicos.

## 1. Preserve comportamento antes de buscar elegância

Preserve, sempre que possível:

- regras de negócio;
- contratos públicos;
- persistência;
- chamadas externas;
- comportamento observável;
- estados e transições;
- expectativas dos testes.

Uma refatoração pode alterar organização e implementação sem alterar semântica.

## 2. Falhas devem fazer parte do contrato quando forem esperadas

Evite um tipo de erro amplo quando o chamador precisa reagir de formas diferentes.

Exemplo:

```dart
sealed class SessionFailure implements Exception {
  const SessionFailure();
}

final class SessionNotFound extends SessionFailure {
  const SessionNotFound();
}

final class SessionStorageUnavailable extends SessionFailure {
  const SessionStorageUnavailable(this.cause);

  final Object cause;
}
```

Use exhaustive `switch` no boundary que transforma failures em UI, status HTTP ou outra representação externa.

Não converta bugs ou invariantes quebradas em failures esperadas apenas para “tipar tudo”.

## 3. Evite controle de fluxo manual sobre Result

Sinais de código a revisar:

```dart
final result = await operation();
if (result.isError()) {
  return Failure(result.exceptionOrNull()!);
}
final value = result.getOrNull()!;
```

Procure uma composição equivalente com operadores nativos da versão instalada.

### Escolha de operador

- `map`: altera apenas o valor de sucesso;
- `flatMap`: encadeia operação que também retorna Result;
- `mapError`: traduz erro/failure;
- `filter`: valida sucesso sem abrir manualmente o Result;
- `zip`: agrega Results independentes;
- `flatten`: remove nesting acidental;
- `recoverWhen`: recovery seletivo;
- `tap`: observação auxiliar sem mudar o valor.

Não crie pipelines gigantes. Quando um fluxo possui várias etapas procedurais, branching e Effects, `Effect.result + async/await` tende a ficar mais legível.

## 4. Evite nesting de abstrações

Questione tipos como:

```dart
Effect<ResultDart<User, Failure>, Failure>
Future<ResultDart<ResultDart<User, Failure>, Failure>>
ResultDart<Future<User>, Failure>
```

Eles podem ser corretos em casos específicos, mas geralmente indicam boundary confuso.

Se o canal de erro do Effect já representa a falha, prefira:

```dart
Effect<User, Failure>
```

Use adaptadores nativos da biblioteca para integrar APIs que retornam Result.

## 5. `Effect.result` como bloco de orquestração

Quando a versão instalada oferecer essa API, ela é uma boa escolha para lógica com várias etapas.

Estilo esperado:

```dart
Effect<User, AuthenticationFailure> authenticate(
  Credentials credentials,
) =>
    Effect.result((use) async {
      final repository = use<AuthenticationRepository>();
      final audit = use<AuditService>();

      final user = await use.unwrap(
        repository.authenticate(credentials),
      );

      await use.unwrap(
        audit.authenticationSucceeded(user.id),
      );

      return user;
    });
```

O corpo deve continuar parecendo Dart convencional e fácil de depurar.

## 6. Branching tipado com `Never`

Quando disponível, prefira um mecanismo como `use.fail(...)` para terminar um branch esperado:

```dart
if (!user.isActive) {
  use.fail(UserInactive(user.id));
}
```

Isso permite que a flow analysis compreenda que o branch não continua.

## 7. Exception boundaries

Clients HTTP, database drivers, filesystem, platform channels e SDKs geralmente lançam exceptions.

Traduza a exception uma única vez no boundary apropriado:

```dart
Effect.tryAsync(
  client.load,
  onError: (error, stackTrace) => RemoteDataUnavailable(error),
);
```

Não espalhe `try/catch` idêntico por services e use cases.

Não capture `Error` indiscriminadamente. APIs que capturam qualquer objeto lançado devem ser usadas apenas quando essa semântica for realmente desejada.

## 8. Escolha consciente entre Result, Effect e Future

### Result

Use quando a computação já está sendo executada/calculada e seu resultado natural é `sucesso | failure`.

É especialmente útil em:

- parsing;
- validação;
- transformações puras;
- regras de domínio;
- APIs que naturalmente retornam Result.

### Effect

Use quando a operação é uma descrição lazy e pode envolver:

- async;
- dependências;
- failure tipada;
- recursos;
- runtime;
- contexto por execução;
- composição de operações.

### Future

Mantenha `Future` em APIs externas e async simples onde a conversão não agrega semântica.

Não faça conversões de ida e volta sem necessidade.

## 9. `Unit` e `Never`

Uma operação sem payload significativo não deve retornar `bool` apenas para dizer que terminou.

Prefira `Unit` quando suportado pela arquitetura:

```dart
Effect<Unit, SaveFailure>
```

Use `Never` como canal de failure apenas quando a operação realmente não possui falha esperada.

## 10. Aliases

Aliases podem reduzir ruído:

```dart
typedef AuthEffect<A extends Object> =
    Effect<A, AuthenticationFailure>;
```

Use apenas quando a família de erros for estável e o alias tornar assinaturas mais legíveis.

## 11. DI: constructor vs contexto

Constructor injection continua útil para dependências estruturais.

Evite, porém, transportar dependências por várias camadas apenas porque uma operação interna eventualmente as utiliza.

Critério:

```text
dependência necessária para a identidade/validade do objeto
    -> constructor

dependência necessária para executar uma operação contextual
    -> Effect/Runtime
```

Não resolva dependências globalmente fora do Runtime.

## 12. Module bindings e lifecycle

Revise se cada binding tem lifecycle coerente.

Considere, conforme a API instalada:

- factory;
- singleton;
- lazy singleton;
- instance;
- resource;
- provider/constructor binding.

Não faça tudo singleton por conveniência.

Quando constructor tear-off for suficiente, prefira:

```dart
.provide<UserRepository>(UserRepositoryLive.new)
```

em vez de closures artificiais.

## 13. Runtime

Evite iniciar toda a árvore de serviços para cada pequena operação quando elas pertencem ao mesmo lifecycle da aplicação.

Em aplicações de longa duração, um Runtime explicitamente iniciado e fechado costuma modelar melhor ownership.

Use execuções one-shot apenas quando forem realmente isoladas.

## 14. Recursos e Scope

Procure código como:

```dart
final connection = await open();
try {
  // uso
} finally {
  await connection.close();
}
```

Se o recurso pertence ao Runtime, registre-o como resource no Module quando a API suportar.

Se pertence apenas a uma execução, use o mecanismo de aquisição/release scoped disponível no Effect.

O código deve deixar claro **quem possui o recurso e quando ele termina**.

## 15. Contexto por execução

Dados como correlation ID, tracing metadata, tenant e flags contextuais podem ser bons candidatos a `EffectLocal` ou API equivalente.

Não use contexto implícito para esconder parâmetros de negócio.

Isto:

```dart
loadUser(userId)
```

é melhor que buscar `userId` de um contexto implícito se o ID faz parte do comando.

## 16. Composição paralela

Quando duas operações são independentes e a versão da biblioteca fornece composição paralela, avalie-a.

Use Records para receber resultados:

```dart
final (profile, permissions) = ...;
```

Não paralelize etapas com dependência causal.

Não suponha cancelamento de `Future` onde Dart não o fornece.

## 17. Records

Use Records para estruturas temporárias sem identidade própria:

```dart
(User user, List<Order> orders)
```

Se a estrutura possui invariantes, comportamento ou significado recorrente, crie uma classe/value object.

## 18. Pattern matching

Prefira exhaustive `switch` para hierarquias seladas:

```dart
String messageFor(AuthenticationFailure failure) => switch (failure) {
  InvalidCredentials() => 'Credenciais inválidas',
  UserBlocked() => 'Usuário bloqueado',
  AuthenticationUnavailable() => 'Serviço indisponível',
};
```

Use object/record patterns quando removerem casts e boilerplate.

## 19. Class modifiers

Considere:

```dart
abstract interface class UserRepository {}
final class UserRepositoryLive implements UserRepository {}
sealed class AuthenticationFailure {}
```

Evite inheritance trees profundas. Prefira composição.

## 20. Extension types

Use quando dois valores possuem a mesma representação física, mas não devem ser intercambiáveis:

```dart
extension type UserId(String value) {}
extension type TenantId(String value) {}
```

Não aplique a todo primitive indiscriminadamente.

## 21. Null safety

Questione:

- `!`;
- `late`;
- nullable usado como estado múltiplo;
- casts depois de checks artificiais.

Ausência legítima, failure, loading e “desconhecido” são estados diferentes e devem ser modelados de forma diferente quando isso importa.

## 22. Não faça functional syntax golf

Isto pode ser melhor:

```dart
final user = await use.unwrap(repository.find(id));
return user;
```

que uma cadeia longa de operadores.

Use pipelines quando eles realmente tornam transformações lineares mais claras.

## 23. Remova helpers redundantes

Antes de manter helpers como:

```text
safeCall
unwrapResult
executeResult
tryResult
resolveService
withResource
```

verifique se a versão instalada de `result_dart` ou `better_effect` já possui a operação.

## 24. Testes

Prefira trocar dependências via recursos oficiais de Module/Runtime/Effect quando disponíveis.

Use test runtimes, overrides, Exit matchers, gates/signals ou recording apenas quando resolverem problemas reais de determinismo, lifecycle ou observabilidade.

Um fake simples ainda é melhor quando suficiente.

## 25. `Exit` deve ficar em boundaries especializados

Não faça toda a aplicação manipular `Exit` explicitamente.

Use-o onde infraestrutura precisa distinguir sucesso, failure esperada, defect ou interruption.

Em código de aplicação, mantenha o caminho mais simples.

## 26. Organização física

Evite concentrar conceitos não relacionados em arquivos como:

```text
models.dart
repositories.dart
services.dart
utils.dart
exceptions.dart
```

Uma feature deve poder ser entendida navegando pelo filesystem.

Mas não crie fragmentação artificial em dezenas de arquivos minúsculos.

## 27. Naming

Nomes devem revelar papel.

Prefira:

```text
SessionRepository
AuthenticationService
LoadCurrentSession
TokenRefreshService
SessionStorage
```

Evite `Manager`, `Helper`, `Processor`, `CommonService` e `Utils` quando não comunicarem uma responsabilidade real.

## 28. Side effects

Código puro deve parecer puro.

Não esconda rede, database, filesystem, logging importante ou publicação de eventos em getters, constructors ou operadores aparentemente puros.

## 29. Performance pragmática

Não faça micro-otimização especulativa.

Corrija, porém:

- Runtime recriado desnecessariamente;
- clients caros recriados repetidamente;
- recursos de longa duração reabertos sem razão;
- serialização acidental de operações independentes;
- wrappers/conversões redundantes entre abstrações.

## 30. Features avançadas são opcionais

Se a versão instalada de `better_effect` oferecer funcionalidades como:

- modules temporários por execução;
- observers/runtime instrumentation;
- locals/metadata;
- test runtime;
- deterministic gates/signals;
- leak assertions;

avalie-as somente quando houver um problema concreto.

“Usar todo o potencial” significa reconhecer a ferramenta adequada, não ativar todas as features.

## 23. Retry deve repetir somente failures elegíveis

Quando a versão suportar `Effect.retry`, prefira-o a loops com `Future.delayed`.

Use `RetryPolicy.none/fixed/linear/exponential` ou policy customizada conforme necessidade. `maxAttempts` inclui a tentativa inicial na linha 0.3.x analisada.

Defina `whileError` para restringir retry a failures realmente transitórias. Não repita automaticamente:

- validação;
- autenticação/autorização definitiva;
- not-found não transitório;
- defect/programming error.

Delays usam `EffectClock` e jitter pode usar `EffectRandom`; mantenha essas capacidades explícitas no Module. Em testes, use clock/random determinísticos.

Cada tentativa pode possuir Scope próprio; não mova resource per-attempt para singleton apenas para facilitar retry.

## 24. Coleções: limite concorrência explicitamente

Para coleções homogêneas, quando disponível, avalie:

- `Effect.forEach(items, mapper)` — sequencial por default;
- `Effect.forEach(..., concurrency: n)` — concorrência limitada;
- `Effect.all(effects, concurrency: n)`;
- variantes `Unbounded` somente para fan-out pequeno e deliberado.

Prefira limite explícito a `Future.wait` sobre lista controlada por usuário ou serviço com connection limits.

Não use um número mágico para representar unbounded.

Preserve a ordem lógica do output quando a API a garante e não suponha que interruption cancela Futures já iniciados fisicamente.

## 25. Modules por execução

Use `runWith`, `runExitWith` ou `executeWith` quando uma execução precisa de ambiente temporário que combina com serviços do Runtime raiz, por exemplo:

- request/job context;
- tenant/session contextual;
- transaction compartilhada por várias camadas;
- resource temporário composto;
- override de preview/teste por operação.

O overlay é local-first e não deve mutar o Runtime raiz.

Não crie Module local para cada parâmetro simples. Se o valor pertence naturalmente à assinatura do use case, continue passando como parâmetro.

## 26. Timeout/interruption não encerram ownership físico automaticamente

Um caller pode receber timeout/failure/interruption antes do Future físico terminar.

O Runtime/Scope deve continuar owner de resources e trabalho iniciado até conclusão/cleanup. Não feche transaction/file/subscription no momento em que o resultado lógico é publicado se o trabalho subjacente ainda pode usá-lo.

Conecte APIs canceláveis ao `CancellationSignal` quando possível.

## 27. Observabilidade deve ficar fora da regra de negócio

Quando houver necessidade real de tracing/log/metrics, prefira `RuntimeObserver` e labels estáveis em vez de espalhar logging operacional em todos os Effects.

Nomeie operações (`users.load`, `checkout.submit`) e coloque IDs variáveis em metadata segura.

Use `EffectLocal.metadata` apenas para valores apropriados a diagnóstico. Não exponha secrets/payloads sensíveis.

Observers são best-effort e não devem alterar o outcome da execução.

## 28. Testes determinísticos

Quando disponíveis, prefira:

- `TestRuntime`;
- typed Exit matchers/extractors;
- `TestGate`/`TestSignal`;
- `ManualEffectClock`;
- `RecordingRuntimeObserver`/event recorder;
- `assertNoActiveExecutions`.

Evite `Future.delayed`/sleep arbitrário para coordenar concorrência, retry, timeout ou cancellation em testes.
