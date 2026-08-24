# better_effect_analyzer

[![pub package](https://img.shields.io/pub/v/better_effect_analyzer.svg)](https://pub.dev/packages/better_effect_analyzer)
[![Dart SDK](https://img.shields.io/badge/Dart-%E2%89%A53.10.0-0175C2.svg)](https://dart.dev/)

`better_effect_analyzer` é o tooling oficial para `better_effect` e `better_effect_flutter`. Ele combina diagnósticos rápidos do Dart Analysis Server com uma análise de grafo do projeto inteiro para validar `Module`s, ownership e composição antes do deploy.

O package é uma **dev dependency**. Ele não participa do `Runtime`, não entra no fluxo de execução de um `Effect` e não deve ser importado por código de produção.

## O que cada camada verifica

O plugin do Analysis Server encontra problemas locais enquanto você edita. O graph checker responde perguntas que dependem do projeto inteiro, como “este root realmente fornece todos os serviços que a aplicação solicita?”.

```text
Analysis Server plugin → código local, IDE, dart analyze, flutter analyze
Graph checker / CLI    → Modules, roots, composição e dependências do projeto
```

## Requisitos

- Dart `>=3.10.0 <4.0.0`;
- Flutter `>=3.38.0` quando o projeto analisado é Flutter;
- linha `0.4.x` de `better_effect`/`better_effect_flutter` para os símbolos documentados aqui;
- `analysis_server_plugin >=0.3.14 <0.3.18` e `analyzer ^12.1.0` conforme o `pubspec.yaml` desta release.

O upper bound do plugin faz parte da compatibilidade com a linha de analyzer usada pelo Flutter suportado. Não aumente esse constraint em uma aplicação apenas para “pegar a versão mais nova” sem verificar a versão de analyzer que o SDK Flutter fixa.

## Instalação

Adicione o package como dependência de desenvolvimento quando quiser usar a CLI ou a API de grafo:

```bash
dart pub add --dev better_effect_analyzer
```

```yaml
dev_dependencies:
  better_effect_analyzer: ^0.4.0
```

Para habilitar o plugin, configure o `analysis_options.yaml` **na raiz do projeto**:

```yaml
plugins:
  better_effect_analyzer:
    version: ^0.4.0
```

Depois de alterar a seção `plugins`, reinicie o Dart Analysis Server da IDE.

Durante o desenvolvimento local deste monorepo, o plugin aceita `path`, mas o caminho precisa ser absoluto:

```yaml
plugins:
  better_effect_analyzer:
    path: /caminho/absoluto/para/packages/better_effect_analyzer
```

## Warnings ativados com o plugin

A versão `0.4.x` registra sete warnings de correção por padrão:

| Código | O que detecta |
| --- | --- |
| `discarded_effect` | Um `Effect` lazy foi criado como expressão e descartado sem composição/execução. |
| `discarded_effect_execution` | Um handle `EffectExecution` foi descartado sem observar/retornar seu resultado. |
| `runtime_started_without_close` | Um `Runtime` local iniciado não possui um fechamento verificável. |
| `unawaited_effect_context_operation` | `use.unwrap`, `use.result`, `use.tryAsync` ou `use.acquire` foi ignorado sem `await`/return. |
| `missing_binding_type_argument` | Um binding constructor-backed não deixa claro o contrato de serviço. |
| `incompatible_provider` | A implementação registrada não satisfaz o contrato do binding. |
| `duplicate_service_binding` | Um `Module` declara duas vezes a mesma identidade de serviço. |

Esses warnings tratam correção e ownership, não preferência de arquitetura.

## Lints opt-in

Há sete lints conservadores que precisam ser habilitados explicitamente porque diferentes equipes escolhem fronteiras diferentes:

```yaml
plugins:
  better_effect_analyzer:
    version: ^0.4.0
    diagnostics:
      effect_command_not_owned: true
      closed_runtime_exposed: true
      module_root_not_complete: true
      repository_requests_repository: true
      viewmodel_requests_service: true
      widget_requests_business_dependency: true
      singleton_viewmodel: true
```

Os quatro últimos refletem a direção arquitetural sugerida por `better_effect_flutter`:

```text
Widget → ViewModel → Repository / UseCase → Service / Client
```

Eles são opt-in de propósito. Não habilite uma regra se a arquitetura do projeto adota conscientemente outra fronteira.

`effect_command_not_owned`, `closed_runtime_exposed` e `module_root_not_complete` ajudam na migração para ownership explícito e roots completos, mas também são conservadores e podem precisar de adoção gradual.

## Quick fixes

A versão atual registra transforms locais e seguros para alguns diagnósticos, incluindo:

- observar/retornar um `EffectExecution` descartado;
- envolver um `Runtime` local com `try/finally`;
- registrar ownership de um Command;
- converter um root visível para `Module.complete`.

O analyzer não tenta gerar arquitetura quando o ownership não pode ser inferido com segurança.

## Graph checker

Instale o package como `dev_dependency` e rode a partir da raiz do app:

```bash
dart run better_effect_analyzer
```

O checker descobre/investiga roots, bindings e dependências e reporta, entre outros casos:

- serviços ausentes em um root completo;
- ciclos de dependência e de composição de `Module`;
- `Module`s selecionados que não existem;
- providers duplicados ou incompatíveis após composição/override;
- recursos que dependem de outro recurso adquirido depois na ordem de startup;
- problemas de ownership que também possuem código equivalente no plugin.

`Module.complete` marca explicitamente um root completo para a análise de serviços ausentes. `Runtime.fork`, `BetterEffectFeatureScope` e `runWith`/`runExitWith` são modelados como ambientes scoped: requisitos que vêm do parent/root permanecem externos ao grafo local, enquanto duplicatas, compatibilidade, ciclos e ordem de recursos continuam sendo validados dentro do overlay.

Selecione roots manualmente quando necessário:

```bash
dart run better_effect_analyzer \
  --module appModule \
  --module backgroundModule
```

Inclua testes no índice com:

```bash
dart run better_effect_analyzer --include-tests
```

## Saídas para CI e inspeção

O CLI suporta formatos de diagnóstico e de grafo:

```bash
# Diagnósticos legíveis
dart run better_effect_analyzer

# Automação
dart run better_effect_analyzer --format machine
dart run better_effect_analyzer --format json
dart run better_effect_analyzer --format sarif

# Exportar o grafo
dart run better_effect_analyzer --graph --format dot
dart run better_effect_analyzer --graph --format mermaid

# Entender o grafo
dart run better_effect_analyzer --explain appModule
dart run better_effect_analyzer --why UserRepository
dart run better_effect_analyzer --unused
```

`--output/-o` grava a saída em arquivo. `--schema-version` expõe a versão pública do schema de grafo.

Por padrão, warnings do graph checker também produzem exit code diferente de zero. Use `--no-fatal-warnings` somente quando essa política for intencional no pipeline.

## API pública de grafo

Aplicações de tooling podem importar:

```dart
import 'package:better_effect_analyzer/better_effect_analyzer.dart';
```

A biblioteca pública expõe `BetterEffectGraphChecker`, `BetterEffectGraph`, queries e renderers para text/JSON/DOT/Mermaid, além dos modelos versionados usados pela CLI. Isso permite integrar a mesma análise em scripts sem parsear stdout.

## Troubleshooting

**O plugin não aparece na IDE.** Confirme que a configuração está no `analysis_options.yaml` raiz, que `version` ou `path` é válido e reinicie o Analysis Server.

**O plugin resolve localmente, mas o Flutter acusa conflito de analyzer.** Compare os constraints do SDK Flutter com `analysis_server_plugin`/`analyzer` desta release antes de alterar versões.

**O graph checker acusa serviço ausente em uma feature.** Verifique se o ambiente foi realmente descoberto como `Runtime.fork`/`BetterEffectFeatureScope`/execution overlay. Requirements fornecidos pelo parent não devem ser duplicados no child apenas para satisfazer a ferramenta.

**Uma regra arquitetural não representa a arquitetura do time.** Desative essa lint no mapa `diagnostics` em vez de espalhar `ignore` pelo código. Supressões locais continuam disponíveis para exceções pontuais.

## Limitações

O plugin é uma análise estática. Ele não executa factories, não prova comportamentos criados dinamicamente em runtime e evita inferir ownership quando a evidência sintática é insuficiente. O graph checker amplia o escopo para o projeto inteiro, mas ainda depende de composição que possa ser descoberta estaticamente.

## Documentação e referência

- [Documentação oficial](https://better-effect-dart.vercel.app/docs/packages/better_effect_analyzer)
- [Guia de diagnósticos](https://better-effect-dart.vercel.app/docs/guides/diagnostics)
- [API no pub.dev](https://pub.dev/documentation/better_effect_analyzer/latest/)
- [CHANGELOG](CHANGELOG.md)
- [Repositório e issues](https://github.com/nitoba/better-effect-dart)

Para agentes de IA, use [llms.txt](https://better-effect-dart.vercel.app/llms.txt) como índice e trate código/configuração da versão instalada como fonte de disponibilidade das APIs.

## Contribuição e licença

Issues e Pull Requests são bem-vindos. Mudanças em regras devem incluir testes que diferenciem diagnósticos corretos de falsos positivos; mudanças no grafo devem preservar o schema e as compatibilidades documentadas.

Licença MIT. Consulte [LICENSE](LICENSE).
