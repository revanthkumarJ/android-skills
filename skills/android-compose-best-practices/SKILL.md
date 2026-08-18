---
name: android-compose-best-practices
description: |
  Official Jetpack Compose and architecture best practices mapped onto a real project - MVI/unidirectional data flow, ViewModel rules, the state-hoisting decision table, composable design, recomposition performance, the side-effect API table, layering, an error-proofing checklist, and how to record deliberate deviations. Use this skill for ALL new Compose/ViewModel/data code and any edit touching state, recomposition, or async work. Trigger on phrases like "is this composable correct", "recomposition", "state hoisting", "LaunchedEffect", "derivedStateOf", "remember", "stability", or "review this ViewModel".
---

# Skill: Jetpack Compose & Architecture Best Practices

> Apply **android-working-discipline** (verification, self-attack, final gate) while executing this skill.

## When to use this skill

Apply to ALL new Compose/ViewModel/data code and to any edit that touches state, recomposition, or
async work. Sourced from official Android guidance (architecture recommendations, Compose
performance, side-effects, state-hoisting docs), **adapted to a real project's standards — where they
conflict, the project standard wins (see "Deliberate deviations" at the end).**

---

## 0. Editing discipline (always)

- **Editing an existing file:** fix/extend in place. Do NOT restructure it — no moving classes
  between files/packages, no renaming public symbols, no re-architecting a working flow "to be
  cleaner", no reformatting untouched code. The diff should contain only the change asked for.
- **Creating new files:** follow the skill files exactly (**android-compose-architecture** for screen shape,
  **android-module-creation** for module shape, **android-xml-to-compose-migration** for the layer chain). Never
  invent a new structure or import a pattern from another codebase.
- Legacy patterns you encounter stay as they are unless the task IS migrating them. Modernising code
  you happen to be reading is how a one-line fix becomes an unreviewable diff.

---

## 1. MVI / Unidirectional Data Flow

A `State` / `Action` / `Event` triple IS MVI. Enforce the loop strictly:

```
UI emits Action → ViewModel.onAction() → updates StateFlow<State> / sends Event → UI renders state
```

- **One immutable state object per screen**: a single `data class [Feature]State` behind
  `MutableStateFlow`, updated only via `_state.update { it.copy(...) }`. Never a scatter of loose
  `MutableStateFlow<Boolean>`s for what is one screen's state (legacy ViewModels do this — don't copy).
- **All intents through `onAction(action: [Feature]Action)`** — never separate public ViewModel
  functions per click.
- **State is the single source of truth**: the UI never mutates data it received; it only sends
  Actions. No business logic in composables.
- **Model exclusive states as a sealed type**, not booleans: `ScreenState.Loading / Success / Error`.
  (Some projects deliberately omit an `Error` UI state and surface errors as toast events — follow
  whichever your codebase already does, consistently.)
- Derive, don't duplicate: values computable from existing state fields become `val x get() = ...` on
  the state class, not a second stored field that can drift out of sync.

---

## 2. ViewModel rules (official, all apply)

- **Screen-level only.** ViewModels belong to screens/nav destinations. Reusable components get
  parameters + callbacks, or a plain `@Stable` state-holder class (`remember { FormState() }`) — never
  their own ViewModel.
- **Lifecycle-independent.** Never hold `Context`, `Activity`, `View`, or `Resources` in a ViewModel.
  String resources → pass from the UI, or resolve resource ids in the composable.
- **Coroutines**: suspend work in `viewModelScope`; expose streams as `Flow`/`StateFlow`. For
  always-on derived streams use `stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), initial)`.
- **Never call Compose-UI suspend functions** (`LazyListState.animateScrollToItem`,
  `DrawerState.close`) from `viewModelScope` — they need the composition's `MonotonicFrameClock`. Do
  them in the composable via `rememberCoroutineScope()`.
- **Collection in UI**: always `collectAsStateWithLifecycle()` for state;
  `LaunchedEffect(Unit) { viewModel.event.collectLatest { ... } }` for events.

---

## 3. State hoisting — decision table (official)

| Situation | Where the state lives |
|---|---|
| Only one composable reads/writes it (expand flag, local animation) | Inside that composable: `rememberSaveable { mutableStateOf(...) }` |
| Several sibling composables share it, pure UI logic (scroll, focus) | Hoist to the **lowest common ancestor**; child takes it as a defaulted param (`lazyListState: LazyListState = rememberLazyListState()`) |
| Complex UI logic across several fields, no business logic | Plain `@Stable` state-holder class + `remember { ... }` |
| Business/data logic, survives config change, screen-level | ViewModel state (`[Feature]State`) |
| Must survive process death | `rememberSaveable` (simple types) or `SavedStateHandle` in the ViewModel |

- Never hoist higher than needed; never pass state through composables that don't use it — pass the
  field, not the whole state object, to leaf components.
- `FocusRequester`s, `SheetState`, `LazyListState`: create with `remember`/`rememberXxxState()` in the
  composable that owns them — never in the ViewModel.

---

## 4. Composable design

- **Stateless content**: `[Feature]ScreenContent(state, onAction)` takes values in, lambdas out. It
  must be previewable with a fake `State`.
- **Parameter order**: required params → optional/defaulted params; accept a
  `modifier: Modifier = Modifier` as the FIRST optional param on every reusable component and apply it
  to the root layout.
- **Slots over flags**: for flexible content take `trailingIcon: @Composable () -> Unit` style slots
  instead of boolean + resource params.
- **Reuse the shared UI module first** — scan it before writing any component; put anything generic
  there, not in the feature.
- Add new params to shared composables with **defaults**, so existing call sites and `@Preview`s keep
  compiling.

---

## 5. Recomposition & performance (official)

- **`remember` expensive work**: any sorting/filtering/parsing done in composition must be wrapped in
  `remember(inputs) { ... }` — or better, moved to the ViewModel.
- **Lazy list `key`s**: every `items(...)` gets a stable unique `key = { it.id }` (never the index).
  Add `contentType` when the list mixes row types. Without keys, insert/remove recomposes every
  following row and breaks item animations and scroll position.
- **`derivedStateOf`** ONLY when the input changes faster than the UI needs to update (e.g.
  `firstVisibleItemIndex > 0` for a scroll-to-top button). If output changes as often as input, it is
  pure overhead — don't use it.
- **Defer state reads**: pass lambdas for fast-changing values (`Modifier.offset { ... }`,
  `Modifier.drawBehind { ... }`) so reads happen in the layout/draw phase, not composition.
- **No backwards writes**: never assign to state during composition (only inside event lambdas or
  effects). A write-after-read in composition = infinite recomposition.
- **Stability**: prefer immutable `data class` + `List` in state. Don't introduce `var` fields or
  mutable collections into state classes.
- Don't create objects (lists, brushes, formatters) inline in composition per frame — `remember` them.

---

## 6. Side-effect APIs — the right one for the job (official)

| Need | Use | Pitfall |
|---|---|---|
| Run suspend work tied to composition / on key change | `LaunchedEffect(key)` | Wrong keys → the effect restarts, or never restarts. `Unit` = run once |
| Launch a coroutine from a click handler | `rememberCoroutineScope()` | Don't use it for auto-running work |
| Effect must see the latest lambda without restarting | `rememberUpdatedState(callback)` | Read the wrapped `State`, not the raw param |
| Register/unregister a listener or observer | `DisposableEffect(key) { onDispose { ... } }` | An empty `onDispose` is a smell |
| Push Compose state to non-Compose code (analytics) | `SideEffect` | Runs after EVERY recomposition — keep it cheap |
| Turn `State<T>` into a Flow for operators | `snapshotFlow { state.value }` | Emits only on change (`distinctUntilChanged` is built in) |
| Turn a callback/Flow source into `State` in composition | `produceState` | Use `awaitDispose` for non-suspending sources |

- One-shot effects that must fire exactly once per screen entry: `LaunchedEffect(Unit)`.
- Events collected in the screen: `collectLatest`.

---

## 7. Layering (official, project-shaped)

- UI (composable) never touches data sources directly — always via ViewModel → repository interface.
  Composables never call the network API, write preferences, or touch the DB.
- Repository per feature, injected as an interface, implementation depending on the shared API
  interface.
- Model per layer: network DTO (serialized-name annotations, all-nullable responses) → domain model
  (non-null, UI-shaped) via a mapper. Never let a network DTO reach a composable; never let Compose
  types reach the data layer.
- Naming (official convention): methods are verb phrases (`createItem()`), stream getters are
  `get[Model]Stream(): Flow<...>`, test doubles are prefixed `Fake`.

---

## 8. Error-proofing checklist for new Compose code

1. Every `items()` has a stable `key`.
2. Every reusable composable: `modifier: Modifier = Modifier` first optional param, stateless, previewable.
3. No state writes during composition; no `MutableList`/`var` in state classes.
4. Every state set to `Loading` has a path back in BOTH the success and the error branch (see
   **android-gotchas** — infinite loading).
5. `collectAsStateWithLifecycle()` for state; events collected with `collectLatest`.
6. New params on shared composables have defaults; previews updated.
7. Long-running work in the ViewModel, never in composition; UI-animation suspends in
   `rememberCoroutineScope`.
8. `rememberSaveable` for user-entered transient UI state that must survive rotation when it is not
   already in the ViewModel.

---

## 9. Deliberate deviations from official guidance (do NOT "fix" these)

Every long-lived codebase has some. Write yours down explicitly, so an agent does not "correct" a
deliberate decision as a side effect of an unrelated task. A representative table:

| Official recommendation | What a codebase may do instead | Why keeping it can be right |
|---|---|---|
| "Don't send events from the ViewModel; reduce into state" | One-shot `Channel<Event>` / `SharedFlow` for navigation and toasts | Established across every feature; host Fragments own navigation |
| A specific DI framework | Whichever one the app already uses, everywhere | Never mix two DI frameworks in one app |
| Navigation Compose across the whole app | Fragment-hosted Compose + XML nav graph; `NavHost` only inside a feature | A mixed XML/Compose migration is still in progress |
| Error state in the UI state | `ScreenState = Loading/Success`; errors become toast events | A product UX decision, applied uniformly |

The value of this table is not that the deviations are correct in the abstract. It is that they are
**consistent**, and consistency is worth more than partial correctness.
