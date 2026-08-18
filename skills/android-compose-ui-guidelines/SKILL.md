---
name: android-compose-ui-guidelines
description: |
  Official Compose UI craftsmanship - layout and arrangement, modifier order, Material 3 theme tokens instead of hardcoded values, lazy-list keys and contentType, text overflow, and accessibility. SCOPED TO MIGRATIONS AND NEW SCREENS ONLY - never apply during a bug fix. Use this skill when migrating a screen to Compose or building a brand-new screen or component. Trigger on phrases like "new screen", "migrate this screen", "theme tokens", "Material 3", "accessibility", "contentDescription", "touch target", "lazy list keys", or "text overflow".
---

# Skill: Compose UI Guidelines

> Apply **android-working-discipline** (verification, self-attack, final gate) while executing this skill.
>
> Sourced from official Android/Jetpack Compose guidance (layouts, Material 3 theming, lists, text,
> accessibility) and **adapted to a real project's standards — where they conflict, the project
> standard wins.**

## SCOPE — read this first

**Use this skill ONLY when migrating an XML/Fragment screen to Compose, or building a brand-new
Compose screen/component.** It is the *UI craftsmanship* companion to **android-xml-to-compose-migration**,
**android-compose-architecture**, and **android-compose-ui-patterns**.

**Do NOT apply this skill during bug fixes.** A bug fix changes only what the task requires. Do not
restyle, re-theme, re-lay-out, hoist state, swap hardcoded values for theme tokens, or "modernise" a
working screen while fixing a bug — that turns a one-line fix into an unreviewable diff and risks
sibling flows. If you notice a UI-quality issue while fixing a bug, mention it in the answer; do not
act on it unless the user asks.

Before writing any UI, **actually read **android-compose-ui-patterns** end to
end** and reuse the shared components it lists. Do **not** substitute an ad-hoc grep for reading it,
and do **not** hand-roll on raw Material 3 (`OutlinedTextField`, `ExposedDropdownMenu`, a platform
`DatePickerDialog`) when a project wrapper exists. The form inputs you will almost always need
already exist somewhere in the shared UI module:

- **Text/number input** → the project's text-field wrapper (watch its capitalisation default —
  wrappers often force `Capitalization.Sentences`, so uppercase in `onValueChange` for all-caps fields).
- **Currency/amount input** → the project's amount field (symbol + digit grouping).
- **Read-only picker / dropdown / date trigger** → the project's picker field.
- **Date** → the project's date dialog; add a platform time picker only if the payload needs a time too.
- **Destructive confirmation** → the project's delete dialog.

Put anything generic in the shared UI module, not in the feature module. Wrap screens in the
project's theme wrapper, not a bare `MaterialTheme`.

> **Real failure this prevents:** on one migration, `LabeledTextField` / `DateField` /
> `CategoryDropdown` were all hand-rolled on raw primitives plus a platform date dialog — because the
> mandated pattern file was never opened and the scan was narrowed to one subfolder. Read the pattern
> file; scan the **whole** shared UI module.

---

## 1. Layout (Column / Row / Box)

- Pick by intent: **`Column`** stacks vertically, **`Row`** horizontally, **`Box`** layers/overlaps.
- Configure spacing with arrangement + alignment, not stray padding:
  - `Column(verticalArrangement, horizontalAlignment)`
  - `Row(horizontalArrangement, verticalAlignment)`
- **Space between items** → `Arrangement.spacedBy(8.dp)` on the parent, not a `Spacer` after every
  child. Use `Spacer` only for a single deliberate gap.
- **Proportional sizing** inside a Row/Column → `Modifier.weight(f)`; fixed → `Modifier.size(...)` /
  `fillMaxWidth()`.
- Deeply nested Compose layouts are cheap (single-pass measure) — don't flatten them for
  "performance". Reach for intrinsics or `BoxWithConstraints` only when a child genuinely needs the
  parent's constraints.
- Use **`Scaffold`** for screen chrome (`topBar` / `bottomBar` / `floatingActionButton`) and **always
  apply its `contentPadding`** to the content root — dropping it hides content behind bars.

## 2. Modifier discipline

- **Order matters** — modifiers apply outside-in. Typical order: input (`clickable`) → padding →
  size/fill → background/border. `.padding().clickable()` ≠ `.clickable().padding()`: the ripple and
  hit area differ.
- Every **reusable composable takes `modifier: Modifier = Modifier` as its first optional param** and
  applies it to its root layout.
- Don't allocate per-frame in composition (brushes, shapes, formatters) — `remember` them.

## 3. Material 3 theming — use tokens, never hardcode

- Read every colour from the theme: `MaterialTheme.colorScheme.primary` / `onSurface` /
  `surfaceVariant` — **never `Color(0xFF…)` or `Color.Blue` inline** in feature code.
- Read every text style from `MaterialTheme.typography.*` (`titleLarge`, `bodyMedium`, `labelSmall`) —
  never a raw `fontSize`/`fontWeight` for standard text.
- Read shapes from `MaterialTheme.shapes.*`.
- **Container/on-container pairing:** put `onPrimaryContainer` content on a `primaryContainer`
  surface, `onSurface` on `surface`. Always pair a background with its matching `on…` colour so
  contrast survives a theme change.
- Emphasis by component, not custom colour: `Button` (high) → `FilledTonalButton` / `OutlinedButton`
  (medium) → `TextButton` (low); `FloatingActionButton` for the primary action.
- M3 elevation is tonal — prefer `Surface(tonalElevation = …)` over stacking shadows.
- If the project ships its own theme wrapper and brand tokens, pull from there; don't spin up a new
  `lightColorScheme` / `Typography` in a feature module.
- Mark M3 experimental composables with `@OptIn(ExperimentalMaterial3Api::class)` at the composable,
  not file-wide, unless that is already the file's convention.

## 4. Lists (`LazyColumn` / `LazyRow` / grids)

- **Stable `key = { it.id }` on every `items(...)`** — never the index. Keys preserve item state and
  scroll position and enable correct add/remove animations. The key type must be Bundle-able
  (primitive, enum, or Parcelable).
- Add **`contentType`** when a list mixes row shapes (header/promo/normal) so Compose only reuses
  compositions across same-type items.
- **Padding around content** → `contentPadding = PaddingValues(...)` (scrolls with content, doesn't
  clip); **gaps between rows** → `verticalArrangement = Arrangement.spacedBy(...)`.
- **Never nest same-direction scrollables**: a `LazyColumn` inside a `Modifier.verticalScroll` Column
  throws. Use one `LazyColumn` with `item { Header() }` / `items(...)` / `item { Footer() }` instead.
- One element per `item {}` (except a divider tied to its row) — bundling breaks `scrollToItem` and
  per-item composition.
- Give async images a **fixed size** in list rows so the viewport can't mis-measure a 0px item.
- **React to scroll** with `derivedStateOf` reading `rememberLazyListState()`; **side-effect on
  scroll** (analytics) via `snapshotFlow { listState.firstVisibleItemIndex }`. Scroll programmatically
  from `rememberCoroutineScope()`, never the ViewModel.
- Paged lists use Paging 3 + `collectAsLazyPagingItems()` with `itemKey { it.id }` — see
  **android-xml-to-compose-migration**, Appendix A.

## 5. Text

- Style from `MaterialTheme.typography.*`; colour from `MaterialTheme.colorScheme.*`. No hardcoded
  size/weight/colour for standard text.
- **Always constrain** potentially long text: `maxLines = N` + `overflow = TextOverflow.Ellipsis`.
- Mixed inline styles → one `Text(buildAnnotatedString { withStyle(SpanStyle(...)) { append(...) } })`,
  not several stacked `Text`s.
- HTML-bearing fields usually already have a project component — reuse it rather than calling
  `AnnotatedString.fromHtml` by hand.

## 6. Accessibility (build it in, don't retrofit)

- **Content descriptions:** meaningful `contentDescription` on informative `Image`/`Icon`; `null` for
  purely decorative ones so screen readers skip them.
- **Touch targets ≥ 48.dp.** Small clickable icons need `Modifier.size(48.dp)` or
  `minimumInteractiveComponentSize()`. Don't ship a 24dp tappable icon.
- **Click labels:** `Modifier.clickable(onClickLabel = "Open details") { … }` so the action reads
  meaningfully.
- **Merge related nodes:** `Modifier.semantics(mergeDescendants = true) { }` on a row so a card reads
  as one item, not five fragments.
- **Headings & state:** mark section titles with `semantics { heading() }`; expose toggle/selection
  via `stateDescription` / `Role` rather than leaving it silent.
- Respect user font scaling — never lock text with fixed `dp` sizing, or with a hard `maxLines` that
  clips scaled text without ellipsis.

## 7. Effects, hoisting, recomposition (pointer)

Covered in depth in **android-compose-best-practices** — apply that skill's §3
(state hoisting table), §5 (recomposition/performance) and §6 (side-effect API table) for any new
screen. Do not duplicate that logic here; this file is the UI-surface layer on top of it.

---

## UI parity note for migrations

When this skill is used inside a migration, the **UI toolkit modernises but behaviour does not** (see
**android-xml-to-compose-migration** → Parity contract). Applying a theme token, a Material 3 component, or a
lazy-list key is fine; changing what renders, when it renders, or what a tap does is **not** —
replicate the legacy conditions exactly and flag anything that looks wrong instead of "fixing" it.
