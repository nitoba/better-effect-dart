# Padrões de transformação Flutter

Use como direção, nunca como substituição mecânica. Confirme a API da versão instalada.

## `isLoading/error/data` manual -> `EffectCommandState`

### Antes

```dart
bool isLoading = false;
User? user;
Object? error;

Future<void> load() async {
  isLoading = true;
  notifyListeners();
  try {
    user = await repository.load();
    error = null;
  } catch (e) {
    error = e;
  } finally {
    isLoading = false;
    notifyListeners();
  }
}
```

### Direção preferida

Mantenha a operação como `Effect<User, UserFailure>` e exponha-a por Command:

```dart
final class UserViewModel extends EffectViewModel {
  UserViewModel(super.commands) {
    load = command<User, UserFailure>(
      loadUser,
      debugLabel: 'users.load',
    );
  }

  late final EffectCommand0<User, UserFailure> load;
}
```

A UI observa o estado já tipado em vez de manter uma segunda máquina de estados.

---

## Infraestrutura no ViewModel -> `EffectCommands` + resolução no Effect

### Antes

```dart
final class LoginViewModel extends ChangeNotifier {
  LoginViewModel(
    this.runtime,
    this.authRepository,
    this.sessionStorage,
    this.logger,
  );

  // ...
}
```

Se essas dependências só existem para executar operações, mova a resolução para o Effect e deixe o ViewModel possuir Commands.

```dart
Effect<Session, AuthFailure> signIn(LoginInput input) =>
    Effect.result((use) async {
      final auth = use<AuthRepository>();
      final storage = use<SessionStorage>();

      final session = await use.unwrap(auth.signIn(input));
      await use.unwrap(storage.save(session));
      return session;
    });
```

```dart
final class LoginViewModel extends EffectViewModel {
  LoginViewModel(super.commands) {
    login = commandWithInput<LoginInput, Session, AuthFailure>(signIn);
  }

  late final EffectCommand<LoginInput, Session, AuthFailure> login;
}
```

Não remova dependências estruturais reais do ViewModel apenas para seguir esse formato.

---

## Side effect em builder -> Listener

### Antes

```dart
ValueListenableBuilder(
  valueListenable: command,
  builder: (context, state, _) {
    if (state is Success) {
      Navigator.of(context).pushNamed('/home');
    }
    return LoginForm(...);
  },
)
```

Isso pode repetir navigation em rebuilds.

### Direção preferida

```dart
EffectCommandListener<Session, AuthFailure>(
  command: viewModel.login,
  onSuccess: (context, session) {
    Navigator.of(context).pushReplacementNamed('/home');
  },
  child: EffectCommandBuilder<Session, AuthFailure>(
    command: viewModel.login,
    builder: (context, state, child) => LoginForm(
      busy: state.isRunning,
    ),
  ),
)
```

Ou `EffectCommandConsumer` quando juntar as duas responsabilidades deixar o subtree mais simples.

---

## Flag `alreadyHandled` -> revisão one-shot

### Antes

```dart
if (state.success && !_alreadyNavigated) {
  _alreadyNavigated = true;
  navigate();
}
```

### Direção preferida

Use `EffectCommandListener`; não replique manualmente a semântica de revision.

---

## Busca com race manual -> `latest`

### Antes

```dart
int requestId = 0;

Future<void> search(String query) async {
  final id = ++requestId;
  final result = await repository.search(query);
  if (id == requestId) {
    items = result;
    notifyListeners();
  }
}
```

### Direção preferida

```dart
search = commandWithInput<String, List<Item>, SearchFailure>(
  searchItems,
  policy: const CommandPolicy.latest(),
);
```

Se a API externa suporta cancellation e o produto quer solicitá-la, avalie `cancelPrevious: true` e conecte o cancellation signal no Effect.

---

## Debounce manual -> TriggerPolicy

### Antes

```dart
Timer? _debounce;

void onQueryChanged(String query) {
  _debounce?.cancel();
  _debounce = Timer(const Duration(milliseconds: 300), () {
    search(query);
  });
}
```

### Direção preferida

```dart
search = commandWithInput<String, List<Item>, SearchFailure>(
  searchItems,
  policy: const CommandPolicy.latest(
    trigger: TriggerPolicy.debounce(
      Duration(milliseconds: 300),
    ),
  ),
);
```

Registre `EffectClock` se essa versão exigir e teste com `ManualEffectClock`.

---

## Submit duplicado -> `drop`

### Antes

```dart
if (_submitting) return;
_submitting = true;
try {
  await submit();
} finally {
  _submitting = false;
}
```

### Direção preferida

Use Command com `drop` (default na linha analisada) quando um segundo tap não representa nova intenção.

---

## Writes que não podem ser perdidos -> `queue`

### Problema

Um toggle/upload/save usa `drop`, então uma intenção do usuário desaparece enquanto outra está ativa.

### Direção preferida

```dart
save = commandWithInput<Change, Unit, SaveFailure>(
  persistChange,
  policy: const CommandPolicy.queue(
    maxPending: 20,
    overflow: QueueOverflow.dropOldest,
  ),
);
```

A estratégia de overflow é decisão do produto. Não copie `dropOldest` sem analisar a semântica.

---

## Rebuild global -> Selector local

### Antes

A tela inteira observa Command apenas para mostrar um overlay de loading.

### Direção preferida

```dart
EffectCommandSelector<User, UserFailure, bool>(
  command: viewModel.load,
  selector: (state) => state.isRunning,
  builder: (context, running, child) {
    return LoadingOverlay(
      visible: running,
      child: child!,
    );
  },
  child: const UserContent(),
)
```

Não use selector quando o estado completo já é simples e o rebuild não é um problema.

---

## Counters de fila espelhados -> snapshot selector

### Antes

```dart
int queued = 0;
int pending = 0;
```

sincronizados manualmente com callbacks de policy.

### Direção preferida

Projete `EffectCommandSnapshot` por `EffectCommandSelector.snapshot` quando a UI precisa mostrar queue/pending/trigger counts.

---

## Runtime por Screen -> Runtime de app/subtree

### Antes

```dart
Future<void> openScreen() async {
  final runtime = await appModule.start();
  runApp(Screen(runtime: runtime));
}
```

ou `Module.start()` dentro de ViewModel.

### Direção preferida

- app root: `runBetterEffectApp`;
- feature async/subtree: `BetterEffectBootstrap`;
- Runtime externo: `BetterEffectProvider.value`.

Escolha um único owner.

---

## `FutureBuilder` em Effect de domínio -> Command quando a interação exige semântica rica

Não substitua todo `FutureBuilder`.

Troque quando a operação já é Effect e precisa de typed failure/defect, repeated execution policy, previous data, retry, interruption ou one-shot effects.

Mantenha `FutureBuilder` para async local simples em que Command seria estrutura extra sem benefício.

---

## UI retry manual -> retry no boundary correto

### Antes

```dart
for (var attempt = 0; attempt < 3; attempt++) {
  try {
    await api.fetch();
    break;
  } catch (_) {
    await Future.delayed(...);
  }
}
```

### Direção preferida

Modele retry na operação:

```dart
fetchData().retry(
  RetryPolicy.exponential(
    maxAttempts: 3,
    initialDelay: const Duration(milliseconds: 200),
  ),
  whileError: (failure) => failure is TemporaryNetworkFailure,
);
```

O botão pode usar `command.retry()` para repetir a intenção aceita quando essa é a UX desejada; não confunda com a policy de resiliência interna do Effect.

---

## Widget test criando Runtime que a árvore fecha -> ownership externo

### Direção preferida

```dart
final harness = await TestRuntime.start(testModule);
addTearDown(harness.close);

await tester.pumpWidget(
  BetterEffectTestApp(
    runtime: harness.runtime,
    child: const UserScreen(),
  ),
);
```

O teste continua owner. Não faça a árvore fechar a mesma instância.
