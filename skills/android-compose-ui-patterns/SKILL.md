---
name: android-compose-ui-patterns
description: |
  Reusable-component discipline and screen layout patterns for Compose - scanning the shared UI module before writing anything, sticky-bottom-button screens, sealed bottom-sheet state with a single wrapper, self-contained form sheets, in-sheet push/pop navigation, previews, pull-to-refresh, and sharing a composable as an image. Use this skill whenever building any Compose screen UI or extracting a shared component. Trigger on phrases like "build this screen", "bottom sheet", "dialog", "shared component", "core:ui", "preview", "pull to refresh", "chips", "FAB", or "where should this composable live".
---

# Skill: Compose UI Patterns

> Apply **android-working-discipline** (verification, self-attack, final gate) while executing this skill.
> Pair with **android-compose-best-practices** — recomposition performance (lazy keys, `derivedStateOf`, deferred reads), side-effect API selection, and composable design rules.

## When to use this skill

Whenever building any Compose screen UI. **Always scan the shared UI module first**, before writing
any UI code, to see what already exists.

Throughout this file, shared components are named `App…` (`AppButton`, `AppTextField`). Substitute
your project's prefix.

---

## Rule 0 — Scan the shared UI module first

Never create a custom component if one already exists.

> **Scan the WHOLE module, not just `components/`.** Reusable pieces live in sibling packages too —
> form inputs in a `textfields` package, pickers and dialogs in a `dialog` package. Run
> `find core/ui -name "*.kt"` before hand-rolling. Do **not** restrict the scan to
> `…ui.components.*`, and do **not** grep only the names you expect.
>
> Real cost of skipping this: a migration re-implemented a text field, a picker field and a date
> dialog that all already existed one package over. The review caught it; the rebuild did not come
> back.

Typical inventory worth knowing before you start:

| Need | Component |
|---|---|
| App bar | `AppTopBar` |
| Text/number input | `AppTextField` (note any forced capitalisation — see below) |
| Currency/amount input | `AppAmountField` |
| Read-only picker / dropdown / date trigger | `AppPickerField` |
| Inline option menu (anchored pop-up, check on selected) | `AppMenuPicker` |
| Date | `AppDateDialog` — never a platform `DatePickerDialog` |
| Destructive confirm | `AppDeleteDialog` |
| Card | `AppCard` |
| Primary button | `AppButton` |
| Toggle | `AppSwitch` |
| Modal sheet | `AppBottomSheet` (often with a **headerless overload** for menu sheets) |
| Simple single-select sheet | `AppListBottomSheet` |
| Spacing | `VerticalSpacer` / `HorizontalSpacer` |
| Section title | `TextHeader` |
| Divider | `AppDivider` |
| Ripple-less tap | `Modifier.clickWithoutRipple` |
| Debounced navigation click | `rememberDebounce` |

## Rule 0.5 — Copy a reference module

Pick the two or three feature modules that best represent the current standard and name them in this
file. When unsure how something should look, find it there and copy that structure rather than
inventing one.

---

## Component notes worth writing down

**Text fields.** If the shared field forces `KeyboardCapitalization.Sentences`, all-caps fields must
uppercase in `onValueChange` — the keyboard hint alone will not do it.

**Icons.** Use the project's own drawables, never a Material icon as a stand-in for a branded one:

```kotlin
Image(
    painter = painterResource(id = com.example.core.resource.R.drawable.ic_logout),
    contentDescription = null,          // decorative; give a label when it is the only affordance
    modifier = Modifier.size(IconSize.small),
)
```

- If icons are `.webp` with a `drawable-night` twin, use **`Image`, not `Icon`**, and do **not** pass
  a `tint` — otherwise dark mode breaks.
- Reusable components take the icon as `@DrawableRes icon: Int`, not an `ImageVector`.
- `Icons.*` is acceptable only for genuinely generic affordances with no branded asset.

**Spacing.** Always use the theme's spacing constants (`Paddings.small`, `Paddings.extra2Large`).
Never hardcode dp unless a very specific value is needed and no constant matches.

---

## Screen layout pattern

### Standard detail/settings screen with a sticky bottom button

```kotlin
Scaffold(
    topBar = {
        AppTopBar(
            title = "Title",
            onBackClick = { debounce { onBackClick() } },
        )
    }
) { innerPadding ->
    Box(
        modifier = Modifier
            .fillMaxSize()
            .padding(top = innerPadding.calculateTopPadding())
    ) {
        when (state.screenState) {
            is ScreenState.Loading -> LoadingScreen()
            is ScreenState.Success -> {
                Column(modifier = Modifier.fillMaxSize()) {
                    Column(
                        modifier = Modifier
                            .weight(1f)
                            .padding(horizontal = Paddings.extra2Large)
                            .verticalScroll(rememberScrollState())
                    ) {
                        VerticalSpacer(Paddings.extra2Large)
                        // screen content
                    }

                    // Sticky bottom button
                    Column(modifier = Modifier.padding(Paddings.extra2Large)) {
                        AppButton(
                            buttonText = "Save",
                            onClick = { onAction(Action.OnSaveClick) },
                            modifier = Modifier.fillMaxWidth()
                        )
                        VerticalSpacer(Paddings.extra2Large)
                    }
                }
            }
        }

        if (state.showOverlayLoader) OverlayLoading()

        // Sheets and dialogs also live inside the outer Box
        FeatureBottomSheetWrapper(state.bottomSheetState, onAction)
    }
}
```

> The sticky bottom column needs `navigationBarsPadding()` under enforced edge-to-edge — see
> **android-platform-compliance** §2. This is the most commonly missed inset.

---

## Bottom sheets & dialogs pattern

### One sealed state, not a pile of booleans

```kotlin
data class FeatureState(
    val screenState: ScreenState = ScreenState.Loading,
    val bottomSheetState: BottomSheetState = BottomSheetState.None,
    val showOverlayLoader: Boolean = false,
) {
    sealed interface BottomSheetState {
        data object None : BottomSheetState
        data object SheetName : BottomSheetState
        // one entry per sheet / dialog
    }
}
```

`showSheetA` + `showSheetB` + `showDialogC` booleans allow two sheets to be open at once, which is
never what you want and always what eventually happens.

### One generic show/hide action pair

```kotlin
sealed interface FeatureAction {
    data class ShowBottomSheet(val bottomSheetState: FeatureState.BottomSheetState) : FeatureAction
    data object HideBottomSheet : FeatureAction
}
```

### One wrapper composable

Put `FeatureBottomSheetWrapper` in `presentation/components/`, switch on the sealed state inside it,
and render it from every screen in the feature — so any sheet works regardless of which screen is
active.

---

## Self-contained form bottom sheet (add / edit)

An add/edit form sheet keeps its **own field state locally** with `remember`, seeded from the item
being edited, and emits a finished result through `onSubmit`. The ViewModel stores only *which* item
is being edited, not every keystroke.

```kotlin
@Composable
fun AddressBottomSheet(
    existing: AddressItem?,                  // null = add
    onDismiss: () -> Unit,
    onSubmit: (AddressRequest) -> Unit,
) {
    var line1 by remember { mutableStateOf(existing?.line1.orEmpty()) }
    var region by remember { mutableStateOf(existing?.region.orEmpty()) }
    var showRegionPicker by remember { mutableStateOf(false) }

    AppBottomSheet(header = "…", sheetState = rememberModalBottomSheetState(true), onDismiss = onDismiss) {
        // AppTextField for inputs; AppPickerField { showRegionPicker = true } for the region
        AppButton(buttonText = "Save") {
            onSubmit(AddressRequest(/* assembled from local state */, isEdit = existing != null))
        }
    }
    if (showRegionPicker) RegionPickerSheet(
        onDismiss = { showRegionPicker = false },
        selected = region,
        onSelected = { region = it },
    )
}
```

**Where validation goes:** form-shaped validation (required field, something chosen) lives in the
sheet. Validation needing domain data (duplicate rules, cross-record checks) lives in the ViewModel.

---

## In-sheet push/pop navigation (iOS-style), not stacked modal sheets

When a bottom sheet drills into sub-screens, do **not** open a second `ModalBottomSheet` on top of the
first. Keep **one** sheet and transition its *content* in place.

- Model destinations as a `private sealed interface` and keep a back stack:
  `remember { mutableStateListOf<Screen>(Screen.Main) }`, plus a `navDirection` (1 forward, −1 back).
  `navigateTo` pushes (dir = 1, `keyboardController?.hide()`), `goBack` pops (dir = −1). Add
  `BackHandler(enabled = stack.size > 1) { goBack() }`.
- Swap bodies with `AnimatedContent(targetState = currentScreen)` using
  `slideInHorizontally { it } + fadeIn() togetherWith slideOutHorizontally { -it } + fadeOut() using SizeTransform(clip = false)`,
  reversing the offset signs when going back.
- Give the shared sheet an optional `onBackClick: (() -> Unit)? = null` — pass `goBack` when
  `stack.size > 1` to show a leading back arrow. Close still dismisses the whole sheet.
- **Reuse existing sheets by exposing their `…Content` composable as `internal`** and driving their
  picker opens through **callbacks** (`onXxxClick`), not by firing visibility events. The standalone
  caller passes callbacks that fire its own events; the nav host passes callbacks that
  `navigateTo(...)`. Keep the old wrapper if another entry point still uses it.
- **Hoist every ViewModel the sub-screens need at the host level** so state survives transitions — a
  child screen leaves composition when `AnimatedContent` settles, so its selections must live in the
  ViewModel, not local `remember`.
- A conditional header `action` slot should be an **always-non-null** `@Composable () -> Unit` that
  renders nothing when inactive — a conditional `@Composable (() -> Unit)?` trips Compose's lambda
  inference.

---

## Extract shared composables into `presentation/components/`

When the same visual element appears on more than one screen, put it in `presentation/components/`.
Do not copy-paste a card into three screens.

### One public component per file

Name each file after its public composable (`EmptyProductsView.kt`, `CategoriesRow.kt`). Keep a
component's private helpers in the same file as the public composable that uses them.

Do **not** create grab-bag files like `CommonComponents.kt` or `FeatureBottomSheets.kt` holding many
unrelated public composables — they grow without bound and make components impossible to find. Each
bottom sheet is its own file; only the small `when`-on-`BottomSheetState` wrapper lives in the wrapper
file. Splitting out of one file turns formerly-`private` helpers into `internal` so siblings can call
them.

---

## Previews — one per composable file

Every file under `components/` and `screens/` gets at least one `@Preview`: a `private` preview fun
wrapped in the project theme, named `<Composable>Preview`, with `@Preview(showBackground = true)`
(drop `showBackground` for full-screen/dialog/sheet previews). Cover the meaningful states.

```kotlin
@Preview(showBackground = true)
@Composable
private fun EmptyProductsViewPreview() {
    AppTheme { EmptyProductsView(onAddProductClick = {}) }
}
```

- Put shared fake data in one internal file (`FeaturePreviewData.kt`): `internal fun sampleX(...)`
  factories + `internal val` sample lists, reused by every preview.
- **Paged list screens:** previews can drive `LazyPagingItems` directly —
  `flowOf(PagingData.from(listOf(sampleX(), …))).collectAsLazyPagingItems()` — passed into the
  stateless `ScreenContent`. No ViewModel or DI needed.
- Sheet/dialog composables compile in `@Preview` but the tooling may render them blank (they live in
  a popup window). That is a tooling limit, not a bug — still add the preview.
- **Preview factories must not touch real preferences or context at composition time**, or the render
  throws. Gate or default such reads.

---

## Comment hygiene

Keep comments that explain a non-obvious *why* (a race-condition guard, a legacy-parity quirk that
looks like a mistake, "this padding matches the old layout"). Delete comments that restate the code,
decorative dividers, and KDoc that paraphrases the signature. A future developer should learn
something from the comment they could not get from reading the code.

---

## Navigation click debounce

Only wrap **navigation** clicks. Never regular actions:

```kotlin
val debounce = rememberDebounce()

onBackClick = { debounce { onBackClick() } }        // navigation → debounce
onClick = { onAction(Action.OnSaveClick) }          // regular action → no debounce
```

Debouncing a normal action makes rapid legitimate input feel broken; not debouncing navigation lets a
double-tap push two copies of the destination.

---

## Recurring list/screen patterns

### Category chips

A `LazyRow` of chips with a synthetic "All" chip (id 0), and a count shown **only** on the selected
chip. Reuse the generic filter chip ONLY if it matches the legacy look — if the legacy chip differs
(brand-filled selected pill, separate count badge, no leading check icon), build a small dedicated
chip rather than bending the shared one that other screens depend on.

If the legacy caps inline chips (say 12) and shows a "View All" chip opening a sheet, replicate that:
cap the list, **keep the selected chip visible** by inserting it at index 1 if it falls past the cap,
and append the "View All" chip.

### Empty optional fields as add-chips

On a details/form screen, an optional field with no value should not occupy a full label/value row.
Render the filled optional fields as rows, then collect the empty ones into a `FlowRow` of add-chips
at the bottom of the same card. **A chip is a single-tap affordance** — it navigates straight to edit,
even when the filled rows on the same screen use double-tap-to-edit.

### Paged content

`PullToRefreshBox` wrapping a `LazyColumn` driven by paging `loadState`.

- **Shimmer for the initial load, not a spinner.** If the legacy used a shimmer layout, build a
  placeholder list of N cards matching the row shape.
- **The pull-to-refresh spinner must only show on a real user pull**, never on the initial or
  automatic load. Don't bind `isRefreshing` directly to `loadState.refresh is Loading`; track a user
  flag:

```kotlin
val isRefreshLoading = items.loadState.refresh is LoadState.Loading
var userRefreshing by remember { mutableStateOf(false) }
LaunchedEffect(isRefreshLoading) { if (!isRefreshLoading) userRefreshing = false }

PullToRefreshBox(
    isRefreshing = userRefreshing,
    onRefresh = { userRefreshing = true; items.refresh() },
) {
    when {
        isRefreshLoading && !userRefreshing -> ListShimmer()   // initial → shimmer
        items.itemCount == 0 -> EmptyView()
        else -> LazyColumn { /* items + append spinner */ }
    }
}
```

- **Conditional footers are `item { }` blocks keyed off state/loadState**, not normal rows: an append
  spinner while loading, a promo card once `loadState.append.endOfPaginationReached`. Port every
  legacy `getItemViewType` branch this way.

### Extending FAB that collapses on scroll

```kotlin
@Composable
private fun LazyListState.isScrollingUp(): Boolean {
    var prevIndex by remember(this) { mutableStateOf(firstVisibleItemIndex) }
    var prevOffset by remember(this) { mutableStateOf(firstVisibleItemScrollOffset) }
    return remember(this) {
        derivedStateOf {
            (if (prevIndex != firstVisibleItemIndex) prevIndex > firstVisibleItemIndex
             else prevOffset >= firstVisibleItemScrollOffset)
                .also { prevIndex = firstVisibleItemIndex; prevOffset = firstVisibleItemScrollOffset }
        }
    }.value
}
// expanded = lazyState.isScrollingUp()
```

---

## Sharing a composable as an image

When an XML screen shared a *view* as a bitmap, the Compose equivalent is a `GraphicsLayer` capture —
**not** re-generating the raw content. Sharing only the inner asset (the bare QR bitmap) silently
drops the branded card around it.

```kotlin
val cardLayer = rememberGraphicsLayer()
val scope = rememberCoroutineScope()

AppCard(
    modifier = Modifier.drawWithContent {
        cardLayer.record { this@drawWithContent.drawContent() }
        drawLayer(cardLayer)
    },
) { /* logo, title, QR, url, footer */ }

scope.launch { shareImage(context, cardLayer.toImageBitmap().asAndroidBitmap()) }
```

Imports: `androidx.compose.ui.graphics.rememberGraphicsLayer`,
`androidx.compose.ui.graphics.layer.drawLayer`, `androidx.compose.ui.draw.drawWithContent`,
`androidx.compose.ui.graphics.asAndroidBitmap`. `record { }` is a `DrawScope` member extension — no
import. Compose 1.7+.

---

## `ScreenContent` rules

- Fully stateless — receives `state`, emits `onAction`.
- No business logic, no `LaunchedEffect`, no ViewModel references.
- No `Toast` inside `ScreenContent` — events come from the ViewModel via `LaunchedEffect` in the entry
  Screen composable.

---

## What NOT to do

- Do NOT use raw `Spacer(Modifier.height(...))` — use the spacer components.
- Do NOT define `TextHeader` locally — import the shared one.
- Do NOT hardcode dp values — use the spacing constants.
- Do NOT create a custom card or button — use the shared ones.
- Do NOT use raw `TopAppBar`, `Card`, `Button`, `OutlinedTextField`, `HorizontalDivider`, `Switch`, or
  `ExposedDropdownMenu` — use the project equivalents.
- Do NOT use a platform date/time picker, or build a bespoke delete dialog — use the shared ones.
- Do NOT wrap regular action clicks with a debounce — navigation only.
- Do NOT scatter sheet/dialog `if` conditions through `ScreenContent` — use the wrapper + sealed state.
- Do NOT use multiple boolean flags for sheets.
- Do NOT show a `Toast` from inside a composable.
- Do NOT copy-paste a shared element across screens — extract it to `presentation/components/`.
- Do NOT lump many public composables into one file.
- Do NOT ship a `components/` or `screens/` composable without a `@Preview`.
- Do NOT push every form keystroke into the ViewModel — keep add/edit form fields in local `remember`
  state and emit a result via `onSubmit`.
- Do NOT fix a "stale search query on back-icon collapse" in the UI — guard the query change in the
  ViewModel with the `isSearchActive` flag.
