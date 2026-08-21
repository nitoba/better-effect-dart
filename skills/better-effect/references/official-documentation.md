# Documentação oficial publicada

Use a documentação publicada de `better_effect` como referência viva para APIs, semântica, exemplos e integração Flutter. Esta referência complementa as regras locais da skill; ela não substitui a verificação da versão realmente instalada no projeto.

## Endpoints canônicos

- Site para leitura humana: <https://better-effect-dart.vercel.app/docs>
- Índice LLM de todas as páginas: <https://better-effect-dart.vercel.app/llms.txt>
- Corpus completo em texto: <https://better-effect-dart.vercel.app/llms-full.txt>
- Base de conteúdo Markdown por página: `https://better-effect-dart.vercel.app/llms.mdx`

## Protocolo de consulta

Quando houver acesso à web e a tarefa depender do comportamento ou da API de `better_effect`/`better_effect_flutter`:

1. Comece por `https://better-effect-dart.vercel.app/llms.txt` para localizar a página ou as poucas páginas relevantes.
2. Prefira o conteúdo Markdown específico da página em vez da página HTML ou do corpus completo.
3. Para uma rota de documentação `/docs/<caminho>`, consulte o conteúdo em:

   `https://better-effect-dart.vercel.app/llms.mdx/docs/<caminho>/content.md`

4. O mesmo padrão vale para páginas índice. Exemplos:

   - `/docs/guides/flutter-mvvm` → <https://better-effect-dart.vercel.app/llms.mdx/docs/guides/flutter-mvvm/content.md>
   - `/docs/guides` → <https://better-effect-dart.vercel.app/llms.mdx/docs/guides/content.md>

5. Se uma página apontar para outro tópico necessário para compreender a semântica ou o exemplo, siga somente os links relevantes.
6. Use `https://better-effect-dart.vercel.app/llms-full.txt` como fallback quando:
   - o índice não estiver disponível;
   - uma página específica não puder ser resolvida;
   - a tarefa exigir uma visão transversal de várias áreas da biblioteca.
7. Não carregue `llms-full.txt` por padrão quando uma ou duas páginas específicas forem suficientes; preserve contexto para o código do projeto.

## Rotas úteis por assunto

O índice `llms.txt` é a fonte para descobrir páginas e deve ser preferido a uma lista fixa. Para os assuntos mais frequentes desta skill, procure primeiro por rotas equivalentes a:

- modelo mental e primeiro uso: `/docs/getting-started/*`;
- package core: `/docs/packages/better_effect`;
- package Flutter: `/docs/packages/better_effect_flutter`;
- analyzer: `/docs/packages/better_effect_analyzer`;
- semântica: `/docs/semantics`;
- Effects: `/docs/guides/effects`;
- composição de coleções: `/docs/guides/collection-composition`;
- retry: `/docs/guides/retry`;
- resources e lifetimes: `/docs/guides/resources-and-lifetimes`;
- execution-scoped modules: `/docs/guides/execution-scoped-modules`;
- observabilidade: `/docs/guides/observability`;
- Flutter MVVM: `/docs/guides/flutter-mvvm`;
- Command policies: `/docs/guides/command-policies`;
- Command selectors: `/docs/guides/command-selectors`;
- feature scopes: `/docs/guides/feature-scopes`;
- testing: `/docs/guides/testing`;
- diagnostics: `/docs/guides/diagnostics`.

A lista acima é apenas um atalho de navegação. Se `llms.txt` expuser uma rota mais nova, mais específica ou renomeada, siga o índice publicado.

## Precedência e compatibilidade

Use esta ordem ao decidir se uma API pode ser aplicada no projeto:

1. `pubspec.yaml`, `pubspec.lock` e source da dependência realmente instalada;
2. testes/source da mesma versão quando disponíveis localmente;
3. documentação oficial publicada para semântica, exemplos e descoberta da API atual;
4. referências locais desta skill como heurísticas de arquitetura/refatoração.

A documentação publicada acompanha a linha atual do projeto e pode estar à frente de uma aplicação que usa uma versão antiga. Se a documentação mostrar uma API que não existe na versão instalada, não a introduza silenciosamente: adapte a solução para a versão real ou proponha explicitamente o upgrade.

Se houver conflito entre uma regra resumida em `SKILL.md` e a documentação oficial atual sobre a semântica da biblioteca, verifique a versão instalada. Para a versão atual, prefira a documentação oficial e o source; para versões anteriores, prefira o source/testes daquela versão.

## Uso durante implementação e review

Consulte a documentação oficial especialmente quando:

- a tarefa usar uma feature que não está detalhada nas regras locais da skill;
- houver dúvida sobre assinatura, overload, estado ou lifecycle de uma API;
- o código usar recursos adicionados depois do baseline embutido na skill;
- uma implementação envolver Runtime, Scope, resources, retry, concorrência, observabilidade ou execution-scoped modules;
- uma implementação Flutter envolver bootstrap/provider, `EffectCommand`, policies, selectors, feature scopes, testing ou lifecycle;
- um code review precisar distinguir um gap real de uma API apenas usada de forma diferente da recomendada.

Não use a documentação apenas para copiar snippets. Leia o contrato e adapte o exemplo ao ownership, failures, Runtime e boundaries reais da aplicação.
