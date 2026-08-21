# better-effect Agent Skill

Skill oficial do monorepo [`nitoba/better-effect-dart`](https://github.com/nitoba/better-effect-dart) para implementar, revisar, depurar e refatorar aplicações que usam `better_effect`, `result_dart` e `better_effect_flutter`.

## Instalação

Com o open Agent Skills CLI da Vercel Labs:

```bash
npx skills add nitoba/better-effect-dart --skill better-effect
```

Para instalar globalmente em um agente específico:

```bash
npx skills add nitoba/better-effect-dart --skill better-effect -g -a codex
```

A skill também pode ser usada sem instalação permanente:

```bash
npx skills use nitoba/better-effect-dart@better-effect
```

## O que ela cobre

- `ResultDart` e typed failures;
- `Effect`, composição e boundaries de erro;
- DI contextual com `use<T>()`;
- `Module`, `Runtime`, `Scope`, resources e cancellation;
- retry, concorrência limitada, execution-scoped modules e observabilidade;
- testing utilities;
- Flutter MVVM com `EffectViewModel` e `EffectCommand`;
- Command state, policies, debounce/throttle/queue e selectors;
- Runtime ownership e lifecycle na árvore Flutter;
- implementação nova, debugging, code review e refatoração profunda;
- consulta à documentação oficial publicada por meio de `llms.txt`, conteúdo Markdown por página e `llms-full.txt` como fallback.

## Fonte de verdade

A skill usa a linha `0.3.x` como baseline embutido, mas a versão efetivamente instalada no projeto sempre prevalece.

Para documentação atual, a skill referencia:

- <https://better-effect-dart.vercel.app/docs> — site oficial;
- <https://better-effect-dart.vercel.app/llms.txt> — índice das páginas para agentes/LLMs;
- `https://better-effect-dart.vercel.app/llms.mdx/docs/<caminho>/content.md` — conteúdo Markdown específico de cada página;
- <https://better-effect-dart.vercel.app/llms-full.txt> — corpus completo usado apenas como fallback.

Em caso de dúvida de compatibilidade, consulte source, testes e documentação da mesma versão antes de propor uma API.

## Arquivos

`SKILL.md` contém o fluxo principal. `references/` aprofunda regras e transformações para core e Flutter; `references/official-documentation.md` descreve como descobrir e consultar a documentação oficial publicada sem carregar o corpus inteiro desnecessariamente. `scripts/verify.sh` executa format, analyzer e testes quando chamado a partir da raiz de um projeto Dart/Flutter.
