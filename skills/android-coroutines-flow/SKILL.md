---
name: android-coroutines-flow
description: |
  Coroutines and Flow discipline for Android - who may launch a coroutine, repository Flow shapes, what a shared network wrapper does NOT do, StateFlow exposure and stateIn, lifecycle-aware collection, one-shot events, dispatcher rules, cancellation-safe try/catch, and parallel work with async. Use this skill whenever writing or reviewing code that touches viewModelScope, Flow, StateFlow, SharedFlow, Channel, Dispatchers, or a repository signature. Trigger on phrases like "collect this flow", "StateFlow", "one-time event", "coroutine", "Dispatchers.IO", "cancellation", "flowOn", "stateIn", or "why does this run on the main thread".
---

# Skill: Coroutines & Flow Discipline

Adapted from the official [Coroutines best practices](https://developer.android.com/kotlin/coroutines/coroutines-best-practices)
and [Things to know about Flow](https://developer.android.com/kotlin/flow) guidance, **reshaped for a
real codebase**. Where official guidance and an existing codebase disagree, §10 says which one wins
and why — because "the official docs say so" is not a good enough reason to refactor 300 call sites.

## When to use this skill

Read before writing or editing anything that touches `viewModelScope`, `Flow`, `StateFlow`,
`SharedFlow`, `Channel`, `Dispatchers`, the shared network wrapper, or a repository method
signature. Complements **android-compose-best-practices** §2 (ViewModel rules) and
**android-compose-architecture** — this file is the async/concurrency half those two only point at.

---

## Rule 0 — Establish the repo baseline, then don't "fix" it

Before writing a line, run these greps and write down the answers. They are conventions, not
mistakes to clean up mid-task:

| Question | Grep | Why it matters |
|---|---|---|
| What shape do repositories use? | `suspend fun .*: Flow<` vs `^\s*fun .*: Flow<` | Match the majority. Consistency beats purity. |
| Is there a shared network wrapper? | `fun .*safeCall` | If yes, never hand-roll `flow { emit(Loading) … }` for a plain call. |
| Are dispatchers injected anywhere? | `CoroutineDispatcher` | If not, do not retrofit injection (see §7). |
| Lifecycle-aware collection? | `collectAsStateWithLifecycle` vs `collectAsState()` | Match the majority; the former should win. |

A typical mature codebase answers: `suspend fun x(): Flow<Resource<T>>` everywhere (the `suspend` is
redundant on a cold flow builder, but it is the house signature), a shared `safeCall`, zero injected
dispatchers, and `collectAsStateWithLifecycle` almost everywhere with a handful of stragglers.

---

## 1. Who is allowed to create a coroutine

- **ViewModel → `viewModelScope.launch { }`.** This is the only place a feature module starts work.
- **Fragment → `viewLifecycleOwner.lifecycleScope.launch { repeatOnLifecycle(STARTED) { … } }`** for
  collection only, never for business logic.
- **Repository → never launches.** It exposes `suspend` functions and cold `Flow`s and lets the
  caller own the lifetime. This is what makes "user navigates away mid-request" cancel correctly.
- **`GlobalScope` is banned in feature and core modules.** Legacy offenders usually exist in the
  `:app` module — do not copy them, do not mass-refactor them. If you need work that outlives the
  screen (a fire-and-forget log, a cache write), do it inside the same `viewModelScope` coroutine
  that already owns the request, or move it into the repository's `suspend` body so the caller's
  scope covers it.

## 2. Repository method shape — pick by call site, not by taste

| The call is… | Signature | Why |
|---|---|---|
| One-shot, UI needs Loading/Success/Error | `suspend fun x(...): Flow<Resource<T>>` via `safeCall` | The house pattern; the `Resource` states drive `screenState`. |
| One-shot, caller only needs the raw result | `suspend fun x(...): NetworkResult<T>` | Fire-and-submit actions. Don't wrap in a Flow just to unwrap it. |
| Cache + network (two emissions) | `suspend fun x(): Flow<Resource<T>>` hand-written with `flow { }` | See **android-room-offline-cache** — a single-emission wrapper cannot emit twice. |

**Never** collect a Flow inside a repository and return a plain value. That hides the Loading state
and makes the call uncancellable from the UI's point of view.

## 3. The shared network wrapper — what it does and what it does NOT do

A typical `safeCall` emits `Loading` → runs the request → emits `Success(mapped)` / `Error(message)`,
catches the network exception, and treats a `null` mapper result as an error.

What it almost certainly does **not** do — check yours before assuming otherwise:

- **No `flowOn`.** The whole chain — including your `mapper` — runs on the collector's dispatcher,
  which is `Main` (`viewModelScope` defaults to `Dispatchers.Main.immediate`). Retrofit's own
  `suspend` call is main-safe, so the request is fine; **your mapper is not**. If a mapper walks
  hundreds of rows, parses JSON, decodes base64, or formats a document, move that work explicitly:
  ```kotlin
  viewModelScope.launch {
      repo.getItems().collect { res ->
          when (res) {
              is Resource.Success -> {
                  val rows = withContext(Dispatchers.Default) { res.data.toRows() }
                  _state.update { it.copy(rows = rows, screenState = ScreenState.Success) }
              }
              else -> Unit
          }
      }
  }
  ```
  Do the heavy step in the ViewModel. **Never bolt `flowOn` onto the shared wrapper** — it is shared
  by every feature in the app, and you cannot test the blast radius.
- **No `retry`, no timeout, no `.catch`.** Anything thrown *outside* the request — inside your
  `mapper`, or in a `flow { }` you wrote yourself — propagates to the collector and crashes the app.
  If you build an operator chain, add `.catch` and emit `Resource.Error`.

## 4. State exposure

```kotlin
private val _state = MutableStateFlow(FeatureState())
val state: StateFlow<FeatureState> = _state.asStateFlow()
```

- A public `MutableStateFlow` is a defect. Grep for `^\s*val .*= MutableStateFlow` before you add one.
- Use `_state.update { it.copy(...) }`, not `_state.value = _state.value.copy(...)`. `update` is
  atomic; the read-modify-write form drops updates when two coroutines write in the same frame.
- **`stateIn`:** when deriving a StateFlow from a repository Flow, always
  `stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), initial)`. `WhileSubscribed(5_000)`
  keeps the upstream alive across a rotation but tears it down when the user actually leaves.
  `SharingStarted.Eagerly` on a network-backed flow fires a request before any screen is listening;
  `Lazily` never stops it.

## 5. Collecting

| Context | Use | Never |
|---|---|---|
| Compose | `viewModel.state.collectAsStateWithLifecycle()` | `collectAsState()` — it keeps collecting while the app is backgrounded. |
| Fragment | `viewLifecycleOwner.lifecycleScope.launch { viewLifecycleOwner.repeatOnLifecycle(STARTED) { flow.collect { … } } }` | a bare `lifecycleScope.launch { flow.collect { } }` — it leaks the collection past `onStop`. |
| Inside another suspend fun | `.collect { }` / `.first()` | `.launchIn(GlobalScope)` |

## 6. One-shot events (navigate, toast, dismiss sheet)

An event must **not** live in the `StateFlow` UI state — a rotation replays it and the user gets the
toast twice or navigates twice.

```kotlin
private val _events = MutableSharedFlow<FeatureEvent>(extraBufferCapacity = 1)
val events: SharedFlow<FeatureEvent> = _events.asSharedFlow()
// emit with tryEmit(...) from non-suspend code, emit(...) inside a coroutine
```

`extraBufferCapacity = 1` matters: a default `MutableSharedFlow()` has **zero** buffer and no replay,
so `tryEmit` silently returns `false` and the event vanishes when nobody is collecting at that
instant. If you must not lose the event even when the screen is briefly detached, use
`Channel<Event>(Channel.BUFFERED).receiveAsFlow()` instead.

## 7. Dispatchers

Official guidance says inject dispatchers so tests can swap them. **If the codebase has no injected
dispatchers and no real test suite, that advice does not apply yet.** Then:

- Do **not** add a `CoroutineDispatcher` constructor parameter to an existing class. It is a
  cross-cutting refactor with no payoff and it violates the minimal-edit rule.
- Do **not** wrap things that are already main-safe. Retrofit `suspend` calls and Room `suspend` DAO
  functions dispatch themselves; `withContext(Dispatchers.IO) { api.getX() }` is noise.
- **Do** use `withContext(Dispatchers.IO)` for genuinely blocking work: `File` reads/writes,
  `ContentResolver` queries, bitmap encode/decode, socket/stream writes.
- **Do** use `withContext(Dispatchers.Default)` for CPU work: large list mapping, sorting thousands of
  rows, serializing a big payload.
- `Dispatchers.Main` is already the default in `viewModelScope`; never state it explicitly.

When the project *does* grow a test suite, inject dispatchers **at that point**, as its own task.

## 8. Cancellation and exceptions

- **`catch (e: Exception)` around a suspend call swallows cancellation** and turns a cancelled screen
  into a "success" path that writes state after the ViewModel is gone. Correct form:
  ```kotlin
  try {
      doSuspendingWork()
  } catch (e: CancellationException) {
      throw e
  } catch (e: Exception) {
      _state.update { it.copy(screenState = ScreenState.Error(e.message.orEmpty())) }
  }
  ```
  Catch the narrowest type you can (`IOException`, a JSON parse exception) before falling back.
- A long non-suspending loop is not cancellable. Add `ensureActive()` at the top of each iteration if
  you loop over more than a few dozen items.
- **Every state you set in the `Loading` branch must be reset in BOTH the `Success` and `Error`
  branches.** This is failure mode #9 in **android-working-discipline** and the infinite-loading trap in
  **android-gotchas** — the most common async bug in Compose codebases.

## 9. Parallel work

Two independent requests → one coroutine, `async`/`await`, so "both finished" is a single atomic
update:

```kotlin
viewModelScope.launch {
    val a = async { repo.getA().first { it !is Resource.Loading } }
    val b = async { repo.getB().first { it !is Resource.Loading } }
    applyBoth(a.await(), b.await())
}
```

Two separate `viewModelScope.launch { }` blocks each doing `_state.update { }` race each other and
produce a screen that is half-loaded, half-loading. If one of the two may fail without killing the
other, use `supervisorScope`.

## 10. Deliberate deviations from official guidance (do NOT "fix" these)

| Official says | A mature codebase often does | Why keeping it can be right |
|---|---|---|
| Inject `CoroutineDispatcher` | Hardcoded, or not used at all | No test suite to benefit; injection touches every repository constructor. |
| Data layer exposes plain `fun` returning `Flow` | `suspend fun` returning `Flow` | Hundreds of call sites. Harmless — the `suspend` is simply never used. |
| Repository returns domain types; UI maps errors | Repository returns `Resource<Domain>` | The shared wrapper is the single error boundary; keeping it in the repo makes error handling uniform. |

The point of this table is not that the deviations are better. It is that **an agent must not
"correct" a deliberate, consistent, 300-call-site decision as a side effect of an unrelated task.**
Flag it, propose it as its own piece of work, and move on.

---

## Checklist before you send a coroutine change

1. No `GlobalScope`, no new public `MutableStateFlow`, no `collectAsState()`.
2. Every `Loading` state has a matching reset in both the success and the error branch.
3. Every `catch (e: Exception)` rethrows `CancellationException` first.
4. Heavy mapping runs in `withContext(Default)`, not inside a network-wrapper mapper on Main.
5. One-shot events go through `SharedFlow(extraBufferCapacity = 1)` / `Channel`, never the UI state.
6. `stateIn` uses `WhileSubscribed(5_000)`.
7. Two related requests are one coroutine with `async`, not two racing `launch`es.

## What NOT to do

- Do not add `.flowOn()` to the shared network wrapper — every feature depends on it.
- Do not convert existing `suspend fun …: Flow<…>` signatures to plain `fun`.
- Do not introduce `runBlocking` anywhere outside a `main()`-style entry point.
- Do not collect a Flow inside a repository to return a plain value.
- Do not add dispatcher injection or a coroutine test harness as a side effect of an unrelated task.
