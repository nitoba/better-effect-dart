# Refatoração Flutter com better_effect_flutter

Use este documento quando a aplicação Flutter já utiliza ou deve consolidar o uso de `better_effect_flutter`.

## 1. Modelo mental

O fluxo preferido é:

```text
Widget / evento do usuário
        ↓
EffectViewModel
        ↓
EffectCommand
        ↓
Effect<A, E>
        ↓
Runtime
        ↓
Module / services / resources
        ↓
Exit<A, E>
        ↓
EffectCommandState<A, E>
        ↓
Widget
```

A UI não precisa conhecer container, repository, HTTP client ou database. Ela conhece estado de apresentação e Commands.

`better_effect_flutter` não é um state manager geral. Provider, Riverpod, BLoC, Signals ou outro mecanismo pode continuar responsável por expor/criar ViewModels. A biblioteca fornece o boundary entre execução tipada e Flutter.

## 2. Bootstrap e ownership do Runtime

Comece sempre perguntando: **quem criou o Runtime e quem deve fechá-lo?**

### App root pertence ao better_effect

Prefira `runBetterEffectApp` quando o package possui o root da aplicação. Isso favorece um Runtime longo compartilhado pelo subtree.

### Startup async de feature, preview ou add-to-app

Use `BetterEffectBootstrap` quando o subtree precisa iniciar Runtime assincronamente e representar loading/error/retry do startup.

### Runtime externo

Use `BetterEffectProvider.value` quando outro boundary criou e fechará o Runtime.

Nunca combine ownership interno e `runtime.close()` externo para a mesma instância.

Se o projeto usa APIs de ownership/lifecycle disponíveis na versão instalada, configure `BetterEffectRuntimeOwnership`/`BetterEffectLifecyclePolicy` de forma explícita quando a semântica não for o default.

### Sinais de problema

- `Module.start()` dentro de `build`;
- Runtime por tela sem necessidade;
- Runtime por clique/Command;
- `dispose()` fechando Runtime que veio de `.value`;
- database/client fechado pela View enquanto pertence ao Module raiz;
- duas árvores acreditando possuir o mesmo Runtime.

## 3. ViewModel deve possuir Commands, não infraestrutura

Quando possível:

```dart
final class UserViewModel extends EffectViewModel {
  UserViewModel(super.commands) {
    load = command<User, UserFailure>(
      loadCurrentUser,
      debugLabel: 'users.load-current',
    );
  }

  late final EffectCommand0<User, UserFailure> load;
}
```

O ViewModel normalmente não precisa receber:

- `Runtime`;
- `Module`;
- injector/service locator;
- API client;
- database;
- repository apenas para repassá-lo a um Effect.

Se uma dependência é verdadeiramente estado estrutural/presentation-specific do ViewModel, constructor injection pode continuar correta. Não remova por dogma.

Se a classe já precisa estender outra base (`ChangeNotifier`, classe de framework etc.), avalie `EffectCommandOwner`/`EffectCommands` conforme a API instalada em vez de criar inheritance artificial.

## 4. Não crie ViewModel por tela como regra cega

Use um ViewModel quando houver estado/coordenação de apresentação com lifetime significativo: Commands, filtros, seleção, paginação, estado derivado, coordenação de múltiplas operações.

Não crie um ViewModel apenas porque existe uma tela. Widgets simples podem receber dados/callbacks diretamente.

Também não faça um ViewModel enorme para várias rotas só para evitar classes. O owner deve acompanhar o lifetime e a coesão do estado de apresentação.

## 5. Command é boundary de operação, não variável de estado genérica

Use `EffectCommand0<A, E>` para operação sem input e `EffectCommand<I, A, E>` para uma entrada.

Para múltiplos valores lógicos, prefira named Record quando isso melhora clareza:

```dart
typedef LoginInput = ({String email, String password});
```

Evite Command para:

- checkbox local puramente síncrono;
- texto de campo que não dispara operação;
- estado visual efêmero que `State`/controller simples resolve melhor.

Use Command quando existe execução com começo, outcome, concorrência, cancellation, retry ou failure/defect relevante.

## 6. Preserve a hierarquia de estado

`EffectCommandState<A, E>` distingue, na linha 0.3.x:

- `EffectCommandIdle`;
- `EffectCommandRunning`;
- `EffectCommandSuccess`;
- `EffectCommandFailure`;
- `EffectCommandDefect`;
- `EffectCommandInterrupted`.

Não reduza automaticamente para:

```dart
bool isLoading;
Object? error;
A? data;
```

Isso pode apagar:

- failure esperada vs defect;
- interrupção;
- previous/retained data;
- último Exit;
- fila/pending;
- estado terminal.

Use pattern matching quando a View realmente precisa da hierarquia completa.

Para casos simples, getters como `isRunning`/`dataOrNull` podem ser mais legíveis do que um switch inteiro.

## 7. `keepPreviousData` é uma decisão de UX

Não preserve/limpe dados por padrão sem entender a tela.

Exemplos:

- refresh de dashboard: normalmente faz sentido manter dados anteriores;
- login submit: normalmente faz sentido `keepPreviousData: false`;
- busca incremental: pode manter resultados anteriores ou mostrar skeleton conforme produto.

Trate retenção como semântica de apresentação, não detalhe técnico.

## 8. Builder, Listener e Consumer têm papéis diferentes

### Builder

Use `EffectCommandBuilder` para renderizar estado.

Não faça navegação, Snackbar, dialog ou analytics no builder, porque builds podem repetir.

### Listener

Use `EffectCommandListener` para efeitos one-shot:

- navigation;
- Snackbar;
- dialog;
- analytics de outcome;
- focus/imperative presentation action.

O mecanismo de revision existe para que o mesmo outcome não seja reentregue apenas por rebuild.

Use `listenWhen` quando a transição precisa de filtro explícito.

### Consumer

Use `EffectCommandConsumer` quando um mesmo subtree precisa renderização e listener. Não use apenas para economizar uma indentação se separar responsabilidades ficar mais claro.

## 9. Selector e rebuilds

Use `EffectCommandSelector<A, E, S>` quando um subtree depende só de uma projeção estável, por exemplo `isRunning`.

A igualdade padrão é `==`. Forneça equality customizada para listas/objetos quando necessário.

Use `.snapshot` para informações operacionais que podem mudar sem uma nova revisão visual, como:

- `pendingCount`;
- `queuedCount`;
- `triggerPendingCount`;
- policy/lastExit/state projetados.

Use `buildWhen` quando a View ainda precisa do estado completo mas algumas transições não devem rebuildar aquele subtree.

Não coloque Selector em todo widget. Primeiro corrija arquitetura/rebuilds grandes; otimize somente subtrees relevantes.

Selector não substitui Listener e não deve consumir one-shot revisions.

## 10. Escolha a política de Command pela intenção

### `drop`

Bom default para ações em que repetir durante execução não cria uma nova intenção válida:

- submit;
- refresh;
- destructive action;
- botão que não deve duplicar request.

Callers repetidos compartilham a execução autoritativa conforme a policy da versão.

### `latest`

Use quando cada input novo torna o anterior obsoleto para o estado visível:

- busca;
- filtro;
- autocomplete;
- seleção que refaz consulta.

Com `cancelPrevious: true`, há solicitação de interruption cooperativa da execução anterior. Não trate isso como cancelamento físico garantido do Future.

### `queue`

Use quando toda intenção aceita precisa ser processada em ordem:

- writes ordenados;
- uploads;
- toggles/eventos que não podem ser perdidos.

Configure `maxPending`/overflow quando uma fila ilimitada é risco real.

## 11. `CommandPolicy` para timing e coordenação

Em código novo, quando a versão suportar, prefira `policy` para casos avançados.

Não passe `policy` e `concurrency` juntos quando a API os trata como alternativas.

Use:

- `TriggerPolicy.debounce` para esperar estabilidade de input;
- `TriggerPolicy.throttle` para limitar frequência;
- leading/trailing conforme UX;
- queue overflow deliberado.

Não implemente `Timer`, guard booleans, stream debounce ou fila local ao redor do Command quando a policy já expressa o comportamento.

Decisões como input substituído, chamada suprimida, overflow ou cancelamento são **operacionais**. O caller recebe interruption; não crie `SearchDebouncedFailure` ou `QueueFullDomainFailure` só para encaixar isso no `E`.

Triggers temporais usam `EffectClock` quando exigido pela versão. Registre-o explicitamente no Module e use `ManualEffectClock` nos testes.

## 12. Retry de Command vs retry de Effect

Separe duas ideias:

- `Effect.retry(policy)`: política de resiliência da operação, baseada em failure tipada elegível;
- `command.retry()`: repetir a última intenção/input aceito pelo Command/policy, quando a API instalada oferece isso.

Não implemente retry de rede no botão/UI com loops ad hoc se pertence à operação.

Não repita automaticamente failures de validação/autorização que não são transitórias.

## 13. Cancellation e dispose

Dart `Future` não tem cancelamento preemptivo geral.

Cancellation/interruption deve ser modelada como:

- revogar autoridade sobre o resultado;
- impedir novos trabalhos/tentativas quando observado;
- conectar `CancellationSignal` a APIs externas canceláveis;
- manter Runtime/Scope como owner físico até trabalho iniciado e cleanup terminarem.

Ao descartar ViewModel/Command, não suponha que o Future desapareceu. O Runtime continua responsável pelo lifecycle físico.

## 14. EffectViewModelBuilder e adapters de state management

`EffectViewModelBuilder` é a opção state-management-free para criar/dispor ViewModel num boundary de widget.

Se o projeto já usa Provider/Riverpod/BLoC/Signals/MobX:

- mantenha o adapter existente quando ele já resolve exposição/lifetime;
- injete `EffectCommands`/factory scoped no boundary adequado;
- não crie uma segunda árvore de DI concorrente;
- não replique estado do Command dentro do state manager sem necessidade.

Use a forma não-listening (`context.effectCommands`, conforme versão) em factories. Use a forma listening apenas em adapters que precisam reagir à troca de scope/runtime.

## 15. Side effects de UI

A regra é:

```text
estado durável/rebuildable → Builder/Selector
one-shot imperativo       → Listener
```

Não use campos como:

```dart
bool _alreadyNavigated = false;
bool _snackbarShown = false;
```

para compensar um side effect colocado em `build`.

## 16. Defect não é mensagem de domínio

`EffectCommandFailure<E>` é para failure esperada.

`EffectCommandDefect` representa programação/configuração/infra inesperada, como serviço ausente ou cleanup quebrado.

A UI pode ter uma fallback screen/reporting para defect, mas não converta todo defect em `AppFailure('Algo deu errado')` no domínio apenas para simplificar rendering.

## 17. Observabilidade no Flutter

Use `debugLabel` estável por operação, como:

```text
users.load
checkout.submit
search.products
sync.push-changes
```

Evite IDs em label. IDs/contexto pertencem à metadata.

Quando necessário, use Runtime observers e `policyObserver` para diagnosticar execução e decisões de Command sem colocar logging em cada ViewModel.

Observers de policy não devem receber input/value sensível apenas por conveniência; mantenha telemetry em metadata segura.

## 18. Resources e subtree lifetime

Resources de aplicação pertencem ao Runtime raiz.

Resources de feature podem pertencer a Runtime/subtree próprio quando existe motivo real de lifecycle.

Resources internos de uma operação pertencem ao Scope/`use.acquire`.

A View nunca deve fechar manualmente um client que o Module/Runtime possui.

## 19. Testing

Prefira testar em camadas sem duplicar lógica:

### Effect/core

Use `TestRuntime`, Module overrides, Exit matchers/extractors, gates e manual clock.

### Command sem widget

Use `EffectCommandProbe`/assertions para observar transições e outcomes sem montar árvore Flutter.

### Listener

Use `EffectCommandListenerProbe` para garantir one-shot/revisions únicas.

### Policy

Use `EffectCommandPolicyProbe` + `ManualEffectClock` para debounce/throttle/overflow sem sleeps reais.

### Widget

Use `BetterEffectTestApp` ou `BetterEffectProvider.value` com Runtime owned pelo teste. A árvore não deve fechar um Runtime externo.

Sempre dispose probes, ViewModels e Commands e confirme ausência de execuções físicas pendentes quando o teste mexe com interruption/timeout/cancellation.

## 20. Checklist Flutter

Antes de concluir, confirme:

- [ ] Runtime é iniciado num boundary estável e possui um único owner.
- [ ] View não resolve services/clients/repositories diretamente.
- [ ] ViewModel não recebe infraestrutura que Effect pode resolver contextualmente sem perda de clareza.
- [ ] Commands representam operações, não estado local arbitrário.
- [ ] Commands têm dispose/owner correto.
- [ ] Failure, defect e interruption continuam distinguíveis.
- [ ] Builder não contém side effects one-shot.
- [ ] Listener não repete outcome por rebuild.
- [ ] Policy de cada Command condiz com a UX.
- [ ] Busca/filter não sofre stale result quando `latest` é o comportamento esperado.
- [ ] Writes que não podem ser perdidos não usam `drop` por acidente.
- [ ] debounce/throttle não foram duplicados manualmente se policy resolve.
- [ ] rebuild selectors são usados apenas onde trazem benefício.
- [ ] widget tests usam ownership externo corretamente.
- [ ] `flutter analyze` e `flutter test` passam após a refatoração.
