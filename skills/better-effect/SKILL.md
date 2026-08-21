---
name: better-effect
description: Implementa, revisa, depura e refatora aplicações Dart e Flutter com better_effect, better_effect_flutter e result_dart. Use para typed failures, composição Result/Effect, DI contextual, Module/Runtime/Scope, retry, concorrência, resources, observabilidade, testes e, em Flutter, MVVM com EffectCommand, lifecycle, one-shot UI effects e rebuilds seletivos sem overengineering.
---

# better_effect for Dart + Flutter

Use esta skill ao implementar, revisar, depurar ou refatorar código que utiliza `better_effect`, `result_dart` e, quando aplicável, `better_effect_flutter`.

O objetivo não é maximizar o número de APIs utilizadas. O objetivo é escolher a abstração correta, preservar ownership/lifecycle e fazer o resultado parecer **bom Dart e bom Flutter**, não uma tradução de Effect TS nem um framework arquitetural inventado.

Esta é a skill oficial do monorepo `nitoba/better-effect-dart`. Ela cobre uso normal das bibliotecas, evolução de features e refatoração profunda. Quando a tarefa for apenas uma dúvida conceitual ou revisão pontual, aplique somente as partes relevantes; quando houver implementação, execute o fluxo completo e valide o resultado.

## Princípios

Priorize, nesta ordem:

1. correção;
2. legibilidade;
3. type safety;
4. ownership/lifecycle correto;
5. simplicidade;
6. coerência arquitetural;
7. boa DX;
8. redução de boilerplate;
9. performance observável, sem micro-otimização especulativa.

Nunca sacrifique legibilidade apenas para usar uma feature moderna, funcional ou específica da biblioteca.

## Contextos da skill

### Dart/core

Use quando o projeto usa `better_effect`/`result_dart` sem uma camada Flutter relevante.

Leia em refatorações não triviais:

- `references/refactoring-rules.md`
- `references/transformation-patterns.md`
- `references/upstream-reference.md`

Leia também `references/official-documentation.md` quando a tarefa depender da API ou da semântica atual de `better_effect`, quando a skill local não detalhar uma feature ou quando houver dúvida sobre uma assinatura/comportamento.

### Flutter

Use quando o projeto contém Flutter e usa `better_effect_flutter`, ou quando precisa integrar Effects existentes à camada Flutter.

Leia obrigatoriamente:

- `references/refactoring-rules.md`
- `references/flutter-refactoring.md`
- `references/flutter-transformation-patterns.md`
- `references/upstream-reference.md`

Leia também `references/transformation-patterns.md` quando houver refatoração relevante no domínio/data/application.

Leia `references/official-documentation.md` para confirmar APIs, lifecycle e comportamento atual de bootstrap/provider, `EffectCommand`, policies, selectors, feature scopes, testing e outras features que possam ter evoluído além do baseline embutido nesta skill.

## Fonte de verdade e compatibilidade

Antes de editar:

1. leia `pubspec.yaml` e `pubspec.lock`;
2. confirme as versões efetivamente instaladas de `result_dart`, `better_effect`, `better_effect_flutter` e `better_effect_analyzer` quando presentes;
3. se forem path/git dependencies, inspecione a implementação local usada pelo projeto;
4. não assuma que a API instalada é igual à versão mais recente;
5. só use APIs disponíveis na versão real do projeto.

A referência que originou esta skill foi o monorepo `nitoba/better-effect-dart` na linha `0.3.x`, onde `better_effect_flutter` reexporta `better_effect`. Trate isso como baseline de conhecimento, não como licença para ignorar a versão instalada.

### Documentação oficial publicada

A documentação atual também é uma referência explícita desta skill:

- site oficial: <https://better-effect-dart.vercel.app/docs>;
- índice de todas as páginas para LLMs: <https://better-effect-dart.vercel.app/llms.txt>;
- conteúdo Markdown por página: `https://better-effect-dart.vercel.app/llms.mdx/docs/<caminho>/content.md`;
- corpus completo de fallback: <https://better-effect-dart.vercel.app/llms-full.txt>.

Quando houver acesso à web e a tarefa depender do comportamento ou da API da biblioteca:

1. consulte `llms.txt` para descobrir a página relevante;
2. prefira uma ou poucas páginas Markdown específicas em `llms.mdx`;
3. siga links adicionais apenas quando forem necessários para completar a implementação;
4. use `llms-full.txt` somente se o índice/página específica falhar ou se a tarefa realmente exigir uma visão transversal da documentação inteira.

Exemplos do padrão:

- `/docs/guides/flutter-mvvm` → <https://better-effect-dart.vercel.app/llms.mdx/docs/guides/flutter-mvvm/content.md>;
- `/docs/guides` → <https://better-effect-dart.vercel.app/llms.mdx/docs/guides/content.md>.

Consulte `references/official-documentation.md` para o protocolo completo, rotas comuns e regras de precedência.

A documentação publicada acompanha a linha atual e pode estar à frente da versão instalada no projeto. Para decidir se uma API pode ser usada, prevalecem `pubspec`/lockfile e o source/testes da versão efetivamente instalada. Use a documentação oficial para descoberta, semântica e exemplos; se ela mostrar uma API mais nova, adapte à versão real ou proponha explicitamente o upgrade.

## Tipos de tarefa

Adapte a profundidade sem perder as semânticas da biblioteca:

- **Implementação nova:** modele primeiro failures, Effects, services, Module/Runtime e ownership; em Flutter, defina ViewModel/Command/policy antes de ligar a UI.
- **Refatoração:** faça inventário das ocorrências relevantes e corrija o padrão por completo, não apenas um exemplo.
- **Debugging:** siga o fluxo `Effect -> Runtime -> Exit` e, em Flutter, `Command -> state/listener`; diferencie failure, defect e interruption antes de corrigir.
- **Code review:** compare a mudança com a versão instalada, os testes e a documentação oficial/repositório; aponte gaps confirmados separadamente de riscos que ainda dependem de validação.
- **Arquitetura/DX:** prefira simplificações que expressem ownership e intenção; não introduza camadas vazias nem abstrações só para demonstrar features da biblioteca.

## Fluxo obrigatório

### 1. Entenda a aplicação antes de editar

Inspecione, conforme existirem:

- `pubspec.yaml` e lockfile;
- estrutura por features/camadas;
- models, entities e value objects;
- failures/exceptions;
- repositories, services e use cases;
- clients HTTP, database, filesystem e plugins;
- composition root, `Module`, bindings e `Runtime`;
- Scopes/resources e cancellation;
- retries, timeouts e composição concorrente;
- observabilidade e diagnostics;
- testes.

Em Flutter, inspecione também:

- `main.dart`/bootstrap;
- `runBetterEffectApp`, `BetterEffectBootstrap`, `BetterEffectProvider` e `BetterEffectScope`;
- ownership/lifecycle do Runtime;
- ViewModels;
- `EffectCommands`, `EffectCommand`/`EffectCommand0`;
- command policies e concorrência;
- `EffectCommandBuilder`, `Listener`, `Consumer` e `Selector`;
- adapters com Provider/Riverpod/BLoC/Signals/MobX ou outro state manager;
- widget lifecycle e `dispose`;
- widget tests e `better_effect_flutter/testing.dart`.

Não faça substituições mecânicas antes de entender o fluxo real.

### 2. Mapeie o trabalho antes de alterar

Em implementação nova, identifique os boundaries e responsabilidades que precisam existir. Em refatoração/debugging, faça um inventário de todas as ocorrências relevantes. Procure no core por:

- `try/catch` manual repetido;
- `Exception` genérica usada como contrato de domínio;
- `isSuccess()`, `isError()`, `getOrNull()` ou `exceptionOrNull()` controlando fluxo;
- `Result<Result<...>>`, `Effect<Result<...>>` ou conversões redundantes;
- `Effect` usado somente como wrapper de `Future`;
- dependências transportadas por constructors sem necessidade estrutural;
- service locator/global singleton;
- Runtime criado repetidamente sem necessidade;
- `try/finally` manual para recurso com owner claro;
- retry manual com loops/delays;
- `Future.wait`/fan-out sem limite onde `Effect.all/forEach` seria mais seguro;
- operações independentes serializadas;
- contexto transversal transportado manualmente por muitas camadas;
- `dynamic`, casts, `!`, `late` e nullability artificial;
- helpers que duplicam APIs das bibliotecas;
- side effects escondidos em APIs aparentemente puras.

Em Flutter, procure adicionalmente por:

- `isLoading + error + data` duplicando `EffectCommandState`;
- widgets chamando repositories/services/clients diretamente;
- ViewModel recebendo `Runtime`, `Module`, injector, HTTP client, database ou todas as dependências da feature;
- Runtime criado dentro de tela, `build`, ViewModel ou por ação;
- Commands criados sem owner/dispose coerente;
- `FutureBuilder` ou callback manual em operações que já são Effects e precisam de estado tipado;
- navegação, Snackbar, dialog ou analytics executados dentro de `build`/builder de estado;
- flags manuais para impedir que um side effect de UI repita após rebuild;
- debounce/throttle/tap guards/queues implementados manualmente ao redor de Commands;
- política `drop`, `latest` ou `queue` incompatível com a semântica do produto;
- rebuild da tela inteira por uma projeção pequena de estado;
- `setState` usado apenas para espelhar estado do Command;
- Runtime fechado por um widget que não o possui;
- Runtime externo passado para um Provider que também tenta fechá-lo;
- cancellation sendo tratada como se Dart pudesse cancelar qualquer `Future` fisicamente.

### 3. Defina o boundary correto

Use esta matriz como padrão:

| Necessidade | Abstração preferida |
| --- | --- |
| valor calculado com sucesso ou falha tipada | `ResultDart<A, E>` |
| operação lazy com async/dependências/falha/contexto/resources | `Effect<A, E>` |
| async externo simples sem ganho de Effect | `Future<A>` |
| operação sem payload de sucesso significativo | `Unit` |
| operação sem falha esperada | `Never` no canal de falha, quando aplicável |
| executar um Effect e expor estado observável à UI | `EffectCommand` / `EffectCommand0` |
| ViewModel que possui Commands | `EffectViewModel` ou `EffectCommandOwner` quando outra base class já existe |
| renderizar estado de Command | `EffectCommandBuilder` |
| navegação/Snackbar/dialog/analytics one-shot | `EffectCommandListener` |
| render + side effect no mesmo subtree | `EffectCommandConsumer` |
| rebuild de uma projeção pequena | `EffectCommandSelector` / `.snapshot` |
| Runtime raiz da aplicação Flutter | `runBetterEffectApp` quando a lib possui o root |
| startup async de feature/preview/add-to-app | `BetterEffectBootstrap` |
| Runtime criado/fechado por outro owner | `BetterEffectProvider.value` |

Não converta tudo para Effect e não transforme `better_effect_flutter` em um novo state manager geral.

### 4. Implemente ou refatore completamente

Quando implementar uma feature, conclua o fluxo necessário de ponta a ponta. Quando identificar um padrão recorrente em refatoração, corrija **todas as ocorrências relevantes**.

Não entregue implementação parcial nem pare após dois arquivos com “os demais podem seguir o mesmo padrão”.

Em refatorações, preserve comportamento, contratos públicos, regras de negócio e UX sempre que possível. Quando a correção exige mudança de comportamento — por exemplo, escolher `latest` em busca para impedir resposta antiga de sobrescrever a nova — documente a decisão. Em features novas, siga os contratos públicos e a semântica documentada da versão instalada.

### 5. Valide

A partir da raiz do projeto alvo, execute quando compatível o `scripts/verify.sh` fornecido por esta skill (resolvendo o caminho da skill instalada), ou rode os comandos equivalentes de format/analyze/test diretamente.

Em Flutter, valide também os widget tests afetados e qualquer teste específico de Command/policy/lifecycle.

Não conclua com erros introduzidos pela mudança.

## Regras centrais de `result_dart`

- Modele failures esperadas explicitamente.
- Prefira composição (`map`, `flatMap`, `mapError`, `filter`, `zip`, `flatten`, `recoverWhen`, `tap`, conforme a versão instalada) a branching manual.
- Use `map` para transformação pura e `flatMap` quando a etapa seguinte também retorna Result.
- Traduza failures no boundary correto.
- Recovery deve ser localizado e sem mascarar falhas anteriores indevidamente.
- Não force Result onde um valor simples ou Effect comunica melhor a semântica.

## Regras centrais de `better_effect`

- `Effect` descreve execução; não é apenas `Future<Result>` com outro nome.
- Prefira `Effect.result((use) async { ... })` para orquestração procedural clara quando disponível.
- Use `use<T>()`, `use.unwrap`, `use.result`, `use.fail`, `use.acquire` e cancellation da versão instalada em vez de wrappers locais equivalentes.
- Separe failure esperada, defect inesperado e interruption.
- Traduza exceptions de I/O na borda da infraestrutura.
- Dê owner/lifetime explícito a todo resource.
- Use `Module` raiz para capacidades de longa duração e Module por execução somente para contexto/resource realmente local à execução.
- Use `runWith`/`runExitWith`/`executeWith` quando o ambiente temporário for a abstração correta; não use Module local para substituir parâmetros normais de domínio.
- Use `Effect.retry`/`RetryPolicy` para retry de failures elegíveis; defects não devem virar retry automático.
- Use `Effect.all`/`Effect.forEach` com limite explícito quando houver coleções de I/O; `unbounded` deve ser deliberado.
- Respeite que interruption/timeout são boundaries lógicos; o Runtime continua owner do trabalho físico e resources até a conclusão.
- Use `RuntimeObserver`/labels/metadata para observabilidade sem contaminar a regra de negócio quando houver necessidade real.

## Regras centrais de `better_effect_flutter`

- Mantenha domínio e aplicação no core; `better_effect_flutter` é a ponte de apresentação.
- A View não resolve serviços. Ela renderiza `EffectCommandState` e dispara Commands.
- O ViewModel recebe `EffectCommands` em vez de receber Module/Runtime/injector e toda a árvore de infraestrutura.
- Commands criados por `EffectViewModel` devem ser owned/disposed pelo ViewModel.
- `EffectCommandState` deve preservar a distinção entre idle, running, success, typed failure, defect e interruption quando esses estados importarem.
- Não reduza esse modelo a `isLoading` + `error != null` se isso apagar informação útil.
- Use Builder para renderização e Listener para efeitos imperativos one-shot.
- Use Selector quando só uma projeção precisa rebuildar; não use selector para consumir revisões de listener.
- Escolha Command policy pela semântica da interação, não por gosto:
  - `drop`: submit/refresh/destructive action sem duplicação;
  - `latest`: busca/filtro onde só o resultado mais recente deve controlar UI;
  - `queue`: writes/uploads/toggles em que cada intenção importa.
- Em código novo, prefira `CommandPolicy` quando precisar combinar coordenação com debounce/throttle/overflow/cancelPrevious.
- Decisões operacionais como debounce substituído, overflow ou cancelamento pertencem a `ExitInterrupted`, não ao failure type de domínio.
- `debugLabel` deve nomear a operação e pode correlacionar Command com observabilidade do Runtime.
- Ownership do Runtime deve ser único e explícito; não misture Provider owner com fechamento externo.

## Dart/Flutter moderno

Use quando melhorar clareza/segurança:

- `sealed class`;
- `final class`;
- `abstract interface class`;
- exhaustive `switch` e switch expressions;
- object/record patterns;
- Records e destructuring;
- constructor tear-offs;
- dot shorthands quando suportados e claros;
- extension types para identidades primitivas relevantes;
- collection `if`/`for`/spread;
- `const`;
- `Never`;
- callbacks/closures pequenos e semanticamente nomeados.

Em Flutter, use o estado selado do Command com pattern matching em vez de reconstruir uma segunda hierarquia de estado equivalente sem necessidade.

Evite syntax golf.

## DI

Não imponha “tudo pelo constructor” nem “nada pelo constructor”.

- dependência estrutural necessária para a validade do objeto → constructor;
- dependência contextual à execução → Effect/Runtime;
- ViewModel Flutter → normalmente recebe `EffectCommands`, não infraestrutura da feature;
- widget → recebe ViewModel/Command/valores de apresentação, não repository/client.

`use<T>()` não é service locator global: ele resolve no Runtime da execução.

## Organização

O filesystem deve explicar a feature de ponta a ponta.

Evite arquivos genéricos gigantes como `models.dart`, `repositories.dart`, `services.dart`, `utils.dart` ou `view_models.dart` agrupando conceitos não relacionados.

Em Flutter, uma feature pode conter presentation/application/domain/data sem concentrar todas as implementações de uma categoria em um único arquivo global. Não crie, porém, camadas ou arquivos vazios só para satisfazer uma arquitetura teórica.

## Proibições

Não:

- reescreva o projeto do zero sem necessidade;
- introduza Clean Architecture/DDD/CQRS por padrão;
- replique Effect TS literalmente em Dart;
- transforme todo `Future` em Effect;
- transforme toda tela em um ViewModel por regra dogmática;
- transforme `better_effect_flutter` em substituto obrigatório de Provider/Riverpod/BLoC/Signals;
- crie um Command para estado puramente local e síncrono que não representa uma operação;
- coloque navegação/Snackbar/dialog dentro de builder de estado;
- faça `BuildContext` atravessar domínio/data;
- use todas as features da biblioteca só porque existem;
- suponha cancelamento preemptivo de Futures Dart;
- feche Runtime/resource em mais de um owner;
- declare sucesso sem formatar, analisar e testar quando as ferramentas estiverem disponíveis.

## Critério de conclusão

A tarefa está concluída somente quando:

- em refatorações, todos os padrões problemáticos mapeados foram tratados nas ocorrências relevantes;
- o código compila;
- formatter/analyzer não apresentam regressões introduzidas;
- testes afetados passam ou falhas preexistentes estão identificadas;
- Result, Effect, Future e, em Flutter, EffectCommand possuem responsabilidades claras;
- failures, defects e interruptions não foram colapsados sem motivo;
- DI e Runtime possuem lifecycle coerente;
- resources têm owner explícito;
- Commands têm owner/dispose correto;
- política de concorrência representa a semântica do produto;
- UI one-shot não depende de flags manuais frágeis;
- rebuilds não foram otimizados à custa de clareza;
- o código ficou mais fácil de compreender, não apenas mais sofisticado.

## Entrega

Ao finalizar, forneça relatório objetivo com:

1. objetivo e escopo concluído;
2. problemas encontrados e/ou implementação realizada;
3. melhorias no uso de `result_dart`;
4. melhorias no uso de `better_effect`;
5. em Flutter, melhorias no uso de `better_effect_flutter`;
6. decisões de Runtime/Scope/resource ownership;
7. decisões de Command state/policy/lifecycle;
8. recursos modernos de Dart utilizados e motivo;
9. simplificações e boilerplate removido;
10. comandos/testes executados e resultados;
11. problemas preexistentes que impediram alguma validação.

Métrica final:

> legibilidade + correção + type safety + ownership + simplicidade + coerência arquitetural + aproveitamento real de result_dart/better_effect/better_effect_flutter.
