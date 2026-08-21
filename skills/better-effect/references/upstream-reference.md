# Referência upstream: better-effect-dart

Use este arquivo para orientar descoberta de API. Ele descreve o baseline `0.3.x` analisado no repositório `nitoba/better-effect-dart`. **A versão instalada no projeto sempre vence.**

## Packages

### `better_effect`

Baseline analisado: `0.3.0`, Dart `>=3.10.0 <4.0.0`, `result_dart ^2.2.0`.

Áreas públicas relevantes do source:

- `packages/better_effect/lib/src/effect/`: Effect, composição, context, EffectLocal, retry e policy services;
- `packages/better_effect/lib/src/module/`: bindings, lifetimes e Module;
- `packages/better_effect/lib/src/runtime/`: Runtime, Exit, execution modules, observer, Scope e errors;
- `packages/better_effect/lib/src/di/`: resolver backend, keys e services;
- `packages/better_effect/lib/src/testing/` + `lib/testing.dart`: TestRuntime, matchers, manual clock, recorder e primitives.

### `better_effect_flutter`

Baseline analisado: `0.3.0`, Dart `>=3.10.0`, Flutter `>=3.38.0`, `better_effect ^0.3.0`.

O entrypoint `package:better_effect_flutter/better_effect_flutter.dart` **reexporta `better_effect`**. Em apps Flutter, normalmente prefira esse import único quando não houver motivo para separar imports.

Áreas públicas relevantes:

- bootstrap: `runBetterEffectApp`;
- runtime tree/lifecycle: `BetterEffectBootstrap`, `BetterEffectProvider`, `BetterEffectScope`, lifecycle/ownership policy;
- commands: `EffectCommand`, `EffectCommand0`, `EffectCommands`, `EffectCommandState`, snapshots, transitions, concurrency e `CommandPolicy`;
- view models: `EffectViewModel`, `EffectCommandOwner`, `EffectViewModelBuilder`;
- widgets: `EffectCommandBuilder`, `EffectCommandListener`, `EffectCommandConsumer`, `EffectCommandSelector`;
- testing: `better_effect_flutter/testing.dart`, `BetterEffectTestApp`, probes e assertions.

### `better_effect_analyzer`

O analyzer é tooling separado do Runtime. Ele oferece feedback local no Analysis Server e um graph checker de projeto/CI.

Ao trabalhar em apps que o instalaram, verifique:

- configuração do plugin em `analysis_options.yaml`;
- diagnostics arquiteturais opt-in;
- graph checker executado com `dart run better_effect_analyzer` quando configurado;
- se mudanças em Modules/providers mantêm o grafo válido.

Não trate o analyzer como substituto dos testes do Runtime/Flutter nem vice-versa.

## Documentação do monorepo

A documentação de uso vive em `apps/docs/content/docs/`.

Ao verificar comportamento ou recomendar transformação, procure primeiro a página temática correspondente:

- `getting-started/mental-model.mdx`: modelo mental;
- `guides/effects.mdx`: Effects e failures tipadas;
- `guides/resources-and-lifetimes.mdx`: ownership de resources;
- `guides/execution-scoped-modules.mdx`: Modules por execução;
- `guides/retry.mdx`: retry, clock, random, jitter, scopes por tentativa;
- `guides/collection-composition.mdx`: `Effect.all`/`forEach` e concorrência limitada;
- `guides/observability.mdx`: RuntimeObserver, labels e metadata;
- `guides/diagnostics.mdx`: diagnostics/analyzer/CI;
- `guides/testing.mdx`: TestRuntime e Flutter testing tools;
- `guides/flutter-mvvm.mdx`: integração Flutter ponta a ponta;
- `guides/command-policies.mdx`: drop/latest/queue/debounce/throttle/overflow;
- `guides/command-selectors.mdx`: selector/snapshot/buildWhen;
- `packages/better_effect.mdx`: overview do core;
- `packages/better_effect_flutter.mdx`: overview Flutter;
- `packages/better_effect_analyzer.mdx`: overview do analyzer;
- `ai/`: instalação, uso e prompts da própria Agent Skill oficial.

Também consulte os READMEs dos packages, changelogs, testes e examples quando a documentação não responder uma nuance.

## Ordem de confiança ao trabalhar em um app

Quando houver divergência aparente:

1. versão efetivamente instalada no projeto (`pubspec.lock`/path/git dependency);
2. source da versão instalada;
3. testes da versão instalada;
4. documentação da mesma versão;
5. baseline descrito nesta skill.

Não copie API do `main` para um app preso em uma versão anterior.

## Semânticas que não devem ser perdidas

### Core

- `Effect` é lazy e Runtime-aware;
- expected failures, defects e interruptions são canais semanticamente distintos;
- Runtime mantém ownership físico após timeout/interruption lógica enquanto Futures/resources iniciados ainda terminam;
- resources seguem owner e ordem de cleanup;
- retry repete failures elegíveis, não defects;
- composição de coleções mantém limite de concorrência e output ordenado;
- execution-scoped Modules são overlays locais, não mutação do Runtime raiz;
- observers são best-effort e não podem mudar o resultado do Effect.

### Flutter

- `EffectCommand` transforma um Effect em estado observável sem apagar `Exit`;
- o ViewModel possui Commands; a View renderiza estado e dispara intenção;
- Builder é declarativo; Listener é one-shot imperativo;
- revisão de listener evita repetir navegação/Snackbar em rebuilds;
- Selector reduz rebuilds sem consumir revisões one-shot;
- Command policy expressa coordenação/timing, não failure de domínio;
- Runtime ownership deve ter um único owner;
- `better_effect_flutter` integra, mas não substitui obrigatoriamente state managers existentes.

### Analyzer/tooling

- diagnostics do editor e graph checker respondem perguntas diferentes;
- regras arquiteturais opt-in devem respeitar a configuração do app;
- o graph checker complementa, não substitui, `dart/flutter analyze` e testes;
- alterações de composition root precisam considerar o grafo inteiro, não apenas o arquivo editado.
