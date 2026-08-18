---
name: android-xml-to-compose-migration
description: |
  Migrating an XML layout plus Fragment to a Compose feature module with behavioural parity - the parity contract, proving a screen is reachable before migrating it, moving drawables, the request/response/domain/mapper/repository/ViewModel layer chain, Paging 3, host-fragment navigation, and a behavioural-parity audit of every condition and side effect. Use this skill whenever migrating an existing XML screen to Compose. Trigger on phrases like "migrate this screen to Compose", "convert this Fragment", "rewrite this in Compose", "XML to Compose", or "port this screen".
---

# Skill: XML to Compose Migration

> Apply **android-working-discipline** (verification, self-attack, final gate) while executing this skill. Migration parity is a §4/§7 problem: extract every render condition and formula from the old source, and tick each against the new flow.
>
> **UI craftsmanship:** while building the Compose surface, apply
> **android-compose-ui-guidelines**. That skill is **migration / new-screen only —
> never apply it during a bug fix.**

## When to use this skill

When the user references an existing XML layout + Fragment and wants it migrated to a Compose feature
module.

---

## Parity contract — non-negotiable

A migration modernises **only two things**: the UI toolkit (XML → Compose) and the architecture
(Fragment spaghetti → State/Action/Event + repository). **Everything else is replicated from the XML
flow EXACTLY:**

| Must match the legacy code exactly | How to guarantee it |
|---|---|
| **Endpoints + request payloads** | Same path, same request fields, same values the old code sent. Compare against the old service method and request model. Never "improve" an API call during a migration. |
| **Preference-gated rendering** | Every preference check ports 1:1, with the **exact comparison** (`!= 0` vs `== 1`) and the **same key string**. |
| **All conditional rendering** | Every `visibility =`, `isVisible`, `getItemViewType`, `if/when` around views becomes the equivalent `if` in Compose — **including the negative branches** (what is hidden, and when). |
| **Flow order & side effects** | Same fetch order on open, same on-click sequences, same dialogs/toasts and their triggers, same fragment results set, same preferences saved. |
| **Formulas & derived values** | Copy from the legacy source line, never paraphrase. |
| **Navigation targets** | Same destinations with the same bundles/keys. |
| **Icons & drawables** | Reuse the **exact drawables the XML used** (see Step 1c). Never substitute a Material icon for a branded one. |

Process: extract every condition/endpoint/side-effect from the legacy Fragment + Adapter + ViewModel
FIRST (Step 1 + Appendix E), keep the list, and tick each item against the new code before declaring
done.

**If a legacy behaviour looks wrong or obsolete, replicate it anyway and flag it to the user.** Never
silently "fix" behaviour during a migration — you will be blamed for the regression, and the original
bug will still be there in the other flow.

---

## Step 1 — Understand the referenced files

- Read the Fragment fully.
- If it calls a ViewModel, read that too.
- If the ViewModel calls a UseCase or repository, read those.
- Keep tracing until you find the final API call.
- Understand the full data flow before writing any code.

### Step 1a — Prove each screen is REACHABLE before migrating it

Legacy flows contain a lot of **dead UI**. Migrating it is wasted work and, worse, "un-deletes"
behaviour the team disabled on purpose. Check all three:

1. **`android:visibility="gone"` in the layout** — the widget that opens it may be hidden.
2. **Commented-out code in the Fragment/Adapter** — the list binding or `navigate()` may be `//`-ed out.
3. **Grep every `navigate` to the destination id** — if the only hits are in the nav graph and none in
   Kotlin, nothing can open it.

> Real examples from a single migration: a whole roles-management tab whose list *and* FAB were `gone`
> and whose binding call was commented out (the tab is now just an "manage this from the web" card); a
> 300-line reset-data flow referenced only from the nav graph, because the real row opens a static
> notice instead; and an edit mode that is unreachable because the menu entry that calls it is
> commented out.

Replicate the reachable state, list the dead screens in the delivery summary, and let the user decide
whether reviving them is a separate task.

### Step 1b — Verify shared components exist ON YOUR BRANCH

The UI-patterns file documents components added over time. A branch cut from the default branch may
not have them yet. **Grep the component before importing it**; fall back to the nearest one that does
exist rather than inventing a local copy.

### Step 1c — Move the legacy drawables into the shared resource module

Feature modules cannot see `:app`'s `R.drawable` — but that is **not** a reason to swap in
`Icons.Filled.*`. Generic Material icons look nothing like a branded set and are an instant visual
regression. Instead:

1. List every drawable the screen used:
   `rg "android:src=|app:srcCompat=" <legacy_layout>.xml`
2. Check whether it is already in the shared resource module.
3. Copy what is missing, **including the `drawable-night` variant** — most branded icons are `.webp`
   with a night twin, which is why they need `Image(painter = …)` and **no `tint`**; tinting breaks
   dark mode.
4. Reference via the shared module's `R.drawable.<name>`, and pass ids as `@DrawableRes Int` params
   (not `ImageVector`) through reusable components.
5. Vector drawables may reference `@color/…` — **verify the colour exists in the shared module** before
   copying, or the build breaks with a confusing resource-linking error.

Fall back to a Material icon only when the legacy used a **platform** drawable.

---

## Step 2 — Check the shared API interface first

Before adding any endpoint:

- Search the shared Retrofit interface for it.
- If it exists → use it as-is; do not duplicate.
- If not → add it there, and **only** there:

```kotlin
@POST("v3/[endpoint]")
suspend fun [functionName](
    @Body request: [RequestClassName]
): NetworkResult<[ResponseClassName]>
```

> **ONE place only.** Do not add it to a legacy god-object data source — that wrapper exists for older
> modules; never extend it and never inject it in new code.
>
> Also check before reinventing: the network module may already have a paging source or a list
> endpoint you need. Extending an existing request data class with **optional, defaulted** fields
> (sort/filter) is non-breaking — prefer that over a brand-new endpoint when the path is the same.

---

## Step 3 — Request / response models

```kotlin
// request
data class [FeatureName]Request(
    @SerializedName("first_name") val firstName: String,
    @SerializedName("some_id")    val someId: Int,
)

// response — all fields nullable
data class [FeatureName]Response(
    @SerializedName("first_name") val firstName: String?,
    @SerializedName("some_id")    val someId: Int?,
)
```

**Rules:**
- Always annotate with the exact API key. Verify the key from an existing model that already sends it
  — never invent it from the field name.
- Field names camelCase, never raw snake_case.
- **All response fields nullable.** Backends omit fields; a non-null Kotlin field on a missing key is
  a crash inside the deserializer, far from the cause.
- Request fields non-nullable unless the API explicitly allows null — see the nullable-through-layers
  rule in **android-gotchas** when "absent" must mean something.

---

## Step 4 — Domain model

```kotlin
data class [FeatureName](
    val firstName: String,
    val someId: Int,
)
```

camelCase, no serialization annotations, no network types. Keep only fields the UI actually needs.

---

## Step 5 — Mappers

```kotlin
fun [FeatureName]Response.toDomain(): [FeatureName] = [FeatureName](
    firstName = firstName.orEmpty(),
    someId = someId ?: 0,
)

fun [FeatureName].toRequest(): [FeatureName]Request = [FeatureName]Request(
    firstName = firstName,
    someId = someId,
)
```

**For every default you add, state what the backend receives when the user enters nothing.** `?: 0`
is right for a count and wrong for an optional price.

---

## Step 6 — Repository

```kotlin
interface [FeatureName]Repository {
    suspend fun get[FeatureName](): Flow<Resource<[FeatureName]>>
}

@Singleton   // your DI framework's singleton annotation, binding the interface
class [FeatureName]RepositoryImpl(
    private val api: AppNetworkApi,
) : [FeatureName]Repository {

    override suspend fun get[FeatureName](): Flow<Resource<[FeatureName]>> =
        safeCall(mapper = { toDomain() }) {
            api.get[FeatureName]([FeatureName]Request(...))
        }
}
```

**Rules:**
- Inject the shared API interface **directly**. The repository builds the request object itself:
  screen-facing params in, `Flow<Resource<Domain>>` out.
- Use the DI annotation that binds the interface, so the ViewModel can inject the interface type.
- Always wrap in the shared network wrapper.
- Always return `Flow<Resource<T>>` for non-paged calls.
- Keep the same layering the rest of the codebase uses — a migration is not the place to introduce
  or remove an architectural layer.

---

## Step 7 — Wire the ViewModel

```kotlin
class [FeatureName]ViewModel(
    private val repository: [FeatureName]Repository
) : ViewModel() {

    private val _state = MutableStateFlow([FeatureName]State())
    val state = _state.asStateFlow()
    private val _event = Channel<[FeatureName]Event>(Channel.BUFFERED)
    val event = _event.receiveAsFlow()

    private fun load() {
        viewModelScope.launch {
            repository.get[FeatureName]().collectLatest { result ->
                when (result) {
                    is Resource.Loading -> _state.update { it.copy(screenState = ScreenState.Loading) }
                    is Resource.Success -> _state.update {
                        it.copy(screenState = ScreenState.Success /*, map result.data */)
                    }
                    is Resource.Error -> {
                        sendEvent(Event.ShowToast(result.message.orEmpty()))
                        sendEvent(Event.NavigateBack)
                    }
                }
            }
        }
    }
}
```

**Every state set in the `Loading` branch must be reset in BOTH `Success` and `Error`** — see the
infinite-loading trap in **android-gotchas**.

---

## Step 8 — Build the Compose screen

Follow **android-compose-architecture** for structure and
**android-compose-ui-guidelines** for the surface.

Map: `RecyclerView` → `LazyColumn`, `TextView` → `Text`, click listeners → `onAction(...)`, visibility
logic → state fields driving `if/when`. Move all business logic to the ViewModel; keep `ScreenContent`
stateless.

---

## Layer summary

```
core/network/AppNetworkApi          ← Retrofit method (check before adding — the ONLY network layer to touch)
core/network/model/request/         ← request data class
core/network/model/response/        ← response data class (all nullable)
core/models/[featurename]/          ← clean domain model
feature/data/mappers/               ← Response → Domain, Domain → Request
feature/data/repo/                  ← repository interface
feature/data/repoImpl/              ← impl injecting the API, wrapper + Flow
feature/data/paging/                ← PagingSource (paged screens only)
feature/presentation/viewmodels/    ← ViewModel calls the repo directly
feature/presentation/screens/       ← Compose screen
feature/presentation/[Feature]Fragment.kt ← hosts Compose, owns navigation
```

---

## What NOT to do

- Do NOT change behaviour during a migration — see the **Parity contract**.
- Do NOT duplicate an API function that already exists.
- Do NOT inject or extend the legacy data source.
- Do NOT use snake_case field names, even if the old code did.
- Do NOT introduce or remove an architectural layer during a migration.
- Do NOT return anything other than `Flow<Resource<T>>` from a non-paged repository call.
- Do NOT put business logic inside `ScreenContent`.
- Do NOT guess API structure — always trace Fragment → ViewModel → repo → API.
- Do NOT reimplement file downloads (`DownloadManager` / `BroadcastReceiver` / storage permissions) —
  use the shared download service.
- Do NOT read `:app`'s preferences, `Constants`, or `R.id` from a feature module — use the shared
  ones, literal bundle-key strings, and the navigation registry.
- Do NOT page a list by hand (`currentPage` / `getMoreData()` / scroll listeners) — use Paging 3.
- Do NOT drop conditional logic during the visual port. Run the **behavioural parity audit
  (Appendix E)** before declaring a screen done.
- Do NOT skip side-effects the legacy screen runs on open just because they render nothing — other
  screens may read the preferences they cache.
- Do NOT forget persisted UI state — if the legacy saves a selection/sort/filter, save it on change
  AND restore it on entry.

---

# Appendix — patterns learned from real migrations

## A. Paged lists (Paging 3)

When the XML screen pages a `RecyclerView` manually, replace **all** of it with Paging 3.

### PagingSource

```kotlin
class [Feature]PagingSource(
    private val api: AppNetworkApi,
    private val params: [Feature]Params,
    private val onTotalLoaded: (Int) -> Unit = {},   // optional: for a count badge
) : PagingSource<Int, [Domain]>() {

    override fun getRefreshKey(state: PagingState<Int, [Domain]>): Int? =
        state.anchorPosition?.let {
            state.closestPageToPosition(it)?.prevKey?.plus(1)
                ?: state.closestPageToPosition(it)?.nextKey?.minus(1)
        }

    override suspend fun load(params: LoadParams<Int>): LoadResult<Int, [Domain]> = try {
        val page = params.key ?: 0
        var result: LoadResult<Int, [Domain]> = LoadResult.Page(emptyList(), null, null)
        api.get[Feature](buildRequest(page, params.loadSize))
            .onSuccess { resp ->
                if (page == 0) onTotalLoaded(resp.total ?: 0)
                val data = resp.items?.filterNotNull()?.map { it.toDomain() } ?: emptyList()
                result = LoadResult.Page(
                    data = data,
                    prevKey = null,
                    nextKey = if (data.size < params.loadSize) null else page + 1,
                )
            }
            .onError { _, message -> result = LoadResult.Error(Exception(message ?: "Error")) }
            .onException { result = LoadResult.Error(it) }
        result
    } catch (e: Exception) {
        LoadResult.Error(e)
    }
}
```

### Repository

```kotlin
fun get[Feature]Stream(
    params: [Feature]Params,
    onTotalLoaded: (Int) -> Unit = {},
): Flow<PagingData<[Domain]>> = Pager(
    config = PagingConfig(pageSize = 50, initialLoadSize = 50, enablePlaceholders = false),  // match the backend's page size
    pagingSourceFactory = { [Feature]PagingSource(api, params, onTotalLoaded) },
).flow
```

Keep **all** query inputs (search, category, filters, sort) in one `[Feature]Params` data class —
otherwise each new filter adds another `Flow` to combine and the pager rebuild logic drifts.

### ViewModel

```kotlin
@OptIn(ExperimentalCoroutinesApi::class)
class [Feature]ViewModel(private val repository: [Feature]Repository) : ViewModel() {
    private val _params = MutableStateFlow([Feature]Params())
    val items: Flow<PagingData<[Domain]>> = _params
        .flatMapLatest { p ->
            repository.get[Feature]Stream(p) { total -> _state.update { it.copy(totalCount = total) } }
        }
        .cachedIn(viewModelScope)
    // changing any field → _params.update { it.copy(...) } rebuilds the pager from page 0
}
```

### Screen

See **android-compose-ui-patterns** → "Paged content" for the pull-to-refresh
recipe, including the **user-pull-only refresh flag** and shimmer-vs-spinner rules.

---

## B. Gating the new flow behind a feature flag (host `:app` side)

Ship every migrated feature behind a flag so it can roll out gradually and roll back instantly:

```kotlin
if (remoteConfig.useNewStore()) {
    navController.navigate(R.id.newStoreFragment, bundleOf("has_access" to (access == 1)))
} else if (access == 1) {
    navController.navigate(R.id.action_moreFragment_to_storeFragment)   // old XML flow
} else {
    navController.navigate(R.id.demoCatalogFragment)
}
```

Add the flag by copying an existing one — they should all have identical bodies.

> **When one legacy entry point forks to two old destinations by access level, keep that fork inside a
> single new Compose Fragment**: pass the access boolean in the bundle and pick the `NavHost`
> `startDestination` from it, rather than registering two new fragments.

And remember: **gate every entry point, not just the one you were shown** — see
**android-cross-module-navigation** §2.

---

## C. Navigating to XML screens from a Compose feature module

Feature modules **cannot see `:app`'s `R.id.*` or `Constants`**. Never import them.

1. The **ViewModel emits a navigation `Event`**.
2. The **host Fragment** collects it and navigates through the registry:
   ```kotlin
   findNavController().navigate(
       NavigationDestinationRegistry.itemDetails,
       bundleOf("item_id" to event.itemId),      // bundle keys are literal strings
   )
   ```
3. If the destination isn't registered, add it in **two** places — the registry (key + typed accessor)
   and the host Activity's registration map.

Confirm the `R.id` exists in the nav graph first.

---

## D. Host Fragment (the only place that touches navigation)

```kotlin
class [Feature]Fragment : Fragment() {
    private val viewModel: [Feature]ViewModel by viewModels()   // DI-framework specific

    override fun onCreateView(...) = ComposeView(requireContext()).apply {
        setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)
        setContent { AppTheme { [Feature]Screen(viewModel = viewModel) } }
    }

    override fun onViewCreated(view: View, s: Bundle?) {
        super.onViewCreated(view, s)
        viewLifecycleOwner.lifecycleScope.launch {
            viewLifecycleOwner.repeatOnLifecycle(Lifecycle.State.STARTED) {
                viewModel.event.collectLatest(::handleEvent)   // navigate / toast / download here
            }
        }
    }
}
```

The Compose-scoped ViewModel accessor and the Fragment's own resolve to the **same** instance (the
Fragment's `ViewModelStore`), so events collected here fire exactly once. If you see an
event firing twice, that assumption has broken — check the scope, don't add a de-duplication flag.

### Fragment results (barcode scanner, etc.)

```kotlin
// launch
findNavController().navigate(
    NavigationDestinationRegistry.barcodeScanner,
    bundleOf("from_compose_module" to true),
)
// listen, in onViewCreated
activity?.supportFragmentManager?.setFragmentResultListener(
    "barcode_scanner", viewLifecycleOwner,
) { _, b -> viewModel.onBarcodeScanned(b.getString("barcode").orEmpty()) }
```

---

## E. Behavioural parity — port the conditions, not just the layout

A pixel-correct screen can still be wrong. The most common migration misses are **conditional logic
and side-effects**, not visuals. Before calling a screen done, grep the legacy Fragment + Adapter +
ViewModel and account for EVERY hit:

```
PreferenceHelper\.   getInt\(   getPaidUser   arguments\?\.
visibility =   getItemViewType   setFragmentResult   saveInt\(|saveString\(
```

Map each hit to a `state` field or an action. The categories that bite:

**1. Entitlement gating**
- Non-paid users often get **extra** UI (promotional cards) **and** gated actions. Port both.
- **Open the specific feature's plan sheet, not the generic upgrade screen.** The legacy passes a
  feature key matching the promoted feature. Carry that key through: card → `onClick(featureKey)` →
  action → event → Fragment navigates with the key in the bundle. Collapsing every gated action into
  the generic plan list silently drops the per-feature context.
- A menu/option list built in code is usually gated. Build with `buildList { if (flag) add(...) }`,
  not a fixed `listOf`.
- Match the legacy comparison exactly (`!= 0` vs `== 1`) unless you have confirmed the value is
  strictly 0/1.

**2. Per-item conditional rendering (`onBindViewHolder` + `getItemViewType`)**
- `getItemViewType` branches (loading footer, promo card, section headers) become extra `item { }`
  blocks keyed off `loadState`/`state` — they are **not** just the normal row.
- Each `View.GONE/VISIBLE` toggle in the row is a condition. Counts shown from list sizes need a
  corresponding field added to the domain model and mapper.

**3. Persisted UI state (save-on-change + restore-on-entry)**
- Selected category/filter/sort the legacy stores must be saved when changed and restored on init.
  Restore **once** (guard with a `private var restored = false`) so it never clobbers an in-session
  change. For paged screens, set the restored value into the params **before** the first load, or the
  initial query is wrong.

**4. Notification / deep-link flags**
- `onCreateView` often checks a "from notification" preference plus an argument and auto-opens a sheet
  or pre-checks a filter. Read these in the host Fragment, **reset the preference**, and dispatch an
  action.

**5. Side-effect-only fetches**
- The screen may call an API purely to cache a preference other screens read. Replicate it: repo
  method + call on load + save.

**Constants:** any `:app` constant you need must be **re-declared in the shared constants file with
the same string value** and imported from there. Never import `:app`'s `Constants` — and never retype
the string from memory; copy it from the source line.

**Deliverable:** finish a migration with a short table of every legacy condition and where it now
lives (state field / action / restored preference), so nothing is silently dropped.
