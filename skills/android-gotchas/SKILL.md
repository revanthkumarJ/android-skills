---
name: android-gotchas
description: |
  Cross-cutting Android pitfalls - DI qualifier collisions, serializer null-omission and ignored annotations, getting a server flag through a Room cache into preferences, Double to String scientific notation, nullable fields through every layer, whole-object settings round-trips, module boundaries, bridging app-only SDKs into feature modules, sticky per-account toggles, the Compose infinite-loading trap, remote-config fetch policy and the BuildConfig import trap, coupled form fields, and verifying a fragment is really dead. Use this skill when debugging something that fails silently, or when a change spans DI, networking, models, or module boundaries. Trigger on phrases like "this value is not being sent", "field is always 0", "infinite loading", "wrong instance injected", "shows scientific notation", "flag is always false", or "why is this null".
---

# Skill: Cross-Cutting Gotchas & Conventions

> Apply **android-working-discipline** (verification, self-attack, final gate) while executing this skill. The failure modes here map to §10 of that document.

## When to use this skill

Reference when working across DI, networking, data models, module boundaries, or Compose loading
state — these are recurring pitfalls that are cheap to get wrong and expensive to debug.

---

## Dependency injection

**Two unqualified bindings of the same type collide.** Add a second provider for a type with no
qualifier and the container silently hands out whichever one wins; unrelated injection points then
resolve to the wrong instance. Qualify **both** the provider and the injection parameter.

> Real case: a streaming `OkHttpClient` in a network module collided with the app's main
> `OkHttpClient`. Every API request silently used the logger-less streaming client, so HTTP bodies
> stopped appearing in logcat — for weeks, with no error. The fix was a named qualifier on both sides.

Before adding any provider, grep the type name across every DI module in the repo.

---

## Networking & serialization

- **Know which serializer is actually wired.** If Retrofit uses a reflective JSON converter, models
  may carry annotations from a *different* serialization library that the converter **ignores**,
  falling back to raw field names. An annotation that looks authoritative can be doing nothing. Check
  the converter factory before trusting an annotation.
- **A reflective converter usually omits nulls** (no global "serialize nulls"), so a `null` field is
  **absent** from the JSON, not `"key": null`. That is how you "send nothing instead of 0" — make the
  field nullable end-to-end and drop the `?: 0.0`. Do **not** enable serialize-nulls globally to force
  explicit nulls; it changes every request in the app.
- Know your log tags: HTTP **BODY** logs appear under the HTTP client's own tag, in debug only. A
  second HEADERS-only interceptor elsewhere in the app can make you think logging is on when bodies
  are not being logged at all.

---

## A new server flag that must reach preferences — the whole chain

Adding a permission/entitlement key is **not** a one-line preferences edit. If the app caches the
response in Room, a field missing from the entity is **silently dropped before it reaches
preferences**. The full chain:

1. Network response model (exact key spelling).
2. **Room entity** + `@ColumnInfo(defaultValue = "0")` — required, or the auto-migration will not
   generate for a non-null column.
3. **Both** mappers: response → entity, and entity → domain. They are separate functions and both
   must be edited.
4. Database `version` bump + `AutoMigration`.
5. The preference key constant — often duplicated in two constants files that must stay identical.
6. The `savePermissions()` writer.
7. Any parallel copy of the response model used by another flow (onboarding often has one).
8. The accessor that feature modules call.

**Why the Room step decides it:** if the repository caches with a "DB is the source of truth" helper,
preferences are written from the *round-tripped* object, not the raw response. Skip step 2 or 3 and
the flag is permanently `0` — with no error anywhere.

Check for an existing victim of this before you start: there is usually one field already in the
response and not in the entity, quietly broken.

---

## Double → String: never `toString()`

`Double.toString()` switches to scientific notation for small or large magnitudes — `0.0003125`
renders as `3.125E-4` in a text field, that string then fails a `toDoubleOrNull()` round-trip, and
the user sees garbage. It also leaves a trailing `.0` on whole numbers.

**Always use a plain-string helper** when a `Double` becomes UI text or state:

- edit-load into a `String` state field
- derived/computed values — reciprocals and percentages are exactly where the exponent appears
- string templates: `"$rate"` has the identical problem

A `BigDecimal`-based rounding helper is also safe; use it when rounding is *wanted*, and the
plain-string helper when the full value must be preserved.

Only applies to `Double`/`Float`. `Int.toString()` is fine — don't churn those.

**Standing rule:** whenever you touch a file and see an existing `Double.toString()`, fix it in the
same change.

---

## Nullable fields through the layers

To make an optional numeric value truly optional (null, not `0.0`), it must be nullable at **every**
layer, and you must drop the coercions:

- network request/response model (`Double?`)
- domain model (`Double?`)
- mapper (`= source.field`, not `?: 0.0`)
- payload builder (`state.x.toDoubleOrNull()`, not `?: 0.0`)
- edit-load (`source.field?.toPlainString() ?: ""`, not `(… ?: 0.0)`)

One surviving `?: 0.0` anywhere in that chain silently converts "the user left it blank" into "the
user entered zero" — which usually means something completely different to the backend.

---

## Adding fields to widely-constructed domain models

Models constructed in many places (mappers, tests, screens) must take new fields **with a default**
(`val maxDiscount: Double? = null`) so existing positional or partial constructors keep compiling.
Prefer appending near the end of the constructor.

---

## Endpoints that round-trip a whole settings object

When `GET`/`POST` exchange the **entire** settings object, a new key needs every file in the chain or
it silently vanishes on the next save:

1. network response model (annotation + default value)
2. network request model (same annotation)
3. domain model (default value)
4. `toDomain` mapper
5. `toRequest` mapper
6. ViewModel action + handler, then the sub-screen UI

Because every sub-screen shares one domain object and one `toRequest()`, a field edited on one screen
is echoed back untouched by the others — **provided steps 1–5 are done**. Miss the request mapper and
saving any *other* settings screen wipes the field.

Watch for a **legacy request class** for the same endpoint that deliberately omits newer keys. If the
backend treats absent keys as "unchanged", that omission is load-bearing — do not "fix" it by adding
the new fields there.

---

## Module boundaries & the data-access standard

### A core module map

| Module | Holds |
|---|---|
| `core:network` | the main Retrofit interface (**add endpoints here**), request/response models, the result adapter, network DI |
| `core:models` | domain models, `Resource`, shared enums |
| `core:utils` | the network wrapper, constants, number/date/coroutine helpers |
| `core:ui` | Compose components, theme, spacing tokens, the navigation destination registry |
| `core:data` | preferences |
| `core:resource` | shared drawables/strings |
| `core:common` | app-wide constants |
| `core:database` | Room database, entities, DAOs |
| `core:service` | background/download services |

### The boundary that catches everyone

Feature `:data` modules depend on `core:models`, `core:network`, `core:utils` — but **not
`core:data`**. Preferences live in `core:data`, so they are reachable from a feature's
`:presentation` module but **not** from its `:data` module.

If a repository needs a preference value, **pass it in from the ViewModel**. Do not add a `core:data`
dependency to a `:data` module to make one call compile — that inverts the layering for everything
that comes after.

### Two same-named helpers with different signatures

A part-migrated app can end up with a legacy `PreferenceHelper` and a modern one. They read the same
underlying keys but their APIs drift — e.g. `getPaidUser()` returning `Boolean` in one and `Int` in
the other, which is why legacy code reads `getPaidUser() == 1`.

In a feature module always use the modern one, and **copying a comparison across from the legacy
module will not compile**. When it does compile, be more worried, not less.

### Entitlement gating is usually an upsell, not a hide

The common convention is to **show** the control to free users and route to a paywall on tap. Hiding
it outright is a deliberate product choice — confirm which is wanted before gating a new control.

---

## Reaching `:app`-only SDKs from a feature module

Some screens call SDKs only `:app` can see (support chat, push, analytics vendors, session
recording), or need the launcher `Activity`. A feature module cannot import these, and a ViewModel
must not hold an `Activity`.

The bridge is a **provider interface in `core:data`, implemented in `:app`**, bound in DI:

```
ViewModel emits Event.LogoutAndRestart
   → host Fragment: appModuleProvider.logoutAndRestart(requireActivity())
```

To add a capability: add the method to the interface, implement it in `:app`, then inject it **in the
host Fragment** — never the ViewModel — and drive it from a one-shot `Event`.

### SMS user-consent OTP inside a Compose feature module

If the consent `BroadcastReceiver` lives in `:app`, a migrated OTP screen needs its own copy: add the
auth + auth-api-phone dependencies to the presentation module, register the receiver in
`onStart`/`onStop` with `ContextCompat.RECEIVER_EXPORTED`, launch the consent intent with
`ActivityResultContracts.StartActivityForResult`, and the phone-number hint with
`StartIntentSenderForResult`.

> **When one Fragment hosts two OTP screens** (e.g. "change number" and "delete account"), route the
> auto-read OTP through a `var otpConsumer: ((String) -> Unit)?` that each route sets in a
> `DisposableEffect`. Firing the action on *both* ViewModels makes the inactive one send a stray OTP
> request — a bug that only appears when a user visits both screens in one session.

---

## Sticky per-account toggles (remembering the user's last choice)

Some create-screen toggles must persist across records. The pattern:

1. Add the key, then an **account-scoped** getter/setter pair (`"${KEY}${accountId}"`). Scoping
   matters: one login can hold several accounts and the toggle is a per-account habit.
2. Write the preference inside the toggle's **event handler**, so every user toggle persists.
3. Seed the state in the ViewModel's `init` — at the first point where the screen mode and all its
   modifier flags are known.
4. **Guard the seed with `mode == CREATE && !isDuplicate && !isDraft`** — the exact complement of the
   edit-load's own guard. EDIT / DUPLICATE / DRAFT must keep the value stored on the source record,
   and the guard is what makes the seed race-free against an edit-load running in a parallel
   coroutine.

Do **not** seed it inside a settings fetch that runs for every mode — its `collectLatest` re-emits and
races the edit-load.

---

## Compose loading-state pitfall (infinite loading)

When a fetch has a "refresh" mode that sets `screenState = Loading` in its `Resource.Loading` branch,
the **`Resource.Success` branch must reset it** — otherwise a refresh leaves the screen stuck on the
loading overlay forever. Gate the reset on the `refresh` flag so initial-load paths are untouched:

```kotlin
is Resource.Success -> _state.update {
    it.copy(
        data = …,
        screenState = if (refresh) ScreenState.Success else it.screenState
    )
}
```

Also worth knowing: in Compose, updating a text field's value **in state** does not re-fire its
`onValueChange`. Bidirectional derived fields (qty × price ⇄ total) therefore do **not** need the
`isFocused` loop-guards the old XML `TextWatcher` code used. Porting those guards across is a common
migration mistake that makes fields feel dead.

---

## Remote Config — fetch policy and the `BuildConfig` import trap

Route all access through one utility class; never touch the SDK singleton directly.

**Reads are free, fetches are not.** Getters read activated values from memory; only
`fetchAndActivate()` hits the network, and fetches are billed per request beyond a free tier. **The
number of call sites is irrelevant to cost — only `minimumFetchIntervalInSeconds` is.**

A workable policy is **one long interval (tune it to your publish cadence — 12h is a reasonable
start) for every build, plus a realtime update listener**: the
interval caps startup fetches, and the listener holds one idle connection the server pushes to on
publish, so a change lands within seconds without a relaunch. Do **not** shorten the interval to buy
freshness — that is what the listener is for, and it works in debug too. Reintroducing `0` for debug
burns fetches and trips the SDK's own throttle.

**The realtime push is best-effort mid-session — expected, do not re-debug it.** The stream drops and
reconnects with backoff, and the SDK stops listening in the background. The reconnect sends the
cached template version, so a missed change is delivered on next foreground. Worst case is therefore
"next foreground", still far better than "next cold start".

**If you add a guard that skips activation for certain keys, be careful what it costs.** A guard that
skips activating a push containing *only* an irrelevant key is fine. Dropping the "only" condition is
not: because updated keys are diffed against *activated* values, a key you declined to activate stays
in the diff of every later push — so a bare `key !in updatedKeys` check would also swallow the next
feature-flag flip bundled with it. That is precisely the revert-a-bad-release path the listener exists
for.

Note what such a guard does **not** do: it saves no network. The SDK fetches the new template
*before* invoking the callback, so activation is a purely local copy.

**Never import `BuildConfig` from a library package.** `com.google.firebase.ktx.BuildConfig` resolves
to the *Firebase library's* `BuildConfig`, which ships with `DEBUG = false` — so a
`if (BuildConfig.DEBUG)` branch guarded by it is dead code in every build. Always use your own
application's fully-qualified `BuildConfig`. This is a one-character IDE-autocomplete mistake with a
silent, permanent effect.

**If no defaults are configured**, every getter falls back to the SDK default before the first fetch
activates — `""` for strings, `false` for booleans. Every `useNewX()` gate returns `false` and every
JSON getter returns `null`. The window is short, but it is why the gates must stay null/false-safe.

**Do not snapshot parsed values into fields at init.** Getters must read live, or they both race the
startup fetch and defeat the realtime listener.

---

## Coupled fields must keep their coupling in a migration

When two form fields constrain each other, the coupling **is** the feature, and a Compose rewrite that
ports the layout but not the rules ships bad data.

The canonical example is a country picker coupled to a region/state field. Three rules, all of which
must survive:

1. Selecting a foreign country → force the region to a sentinel "other" value.
2. Selecting the home country → clear the region **only if** it currently holds that sentinel; a real
   region the user already picked is kept.
3. While a foreign country is selected, the region picker is **disabled** and the postal-code lookup
   is not offered — otherwise the home-country-only lookup API overwrites the region rule 1 just set.
   Length caps on the postal code are home-country-only too.

Put the shared constants and an `isHomeCountry()` helper in the shared UI module, and make the helper
treat an **empty** country as the home country if that is what the old flow did.

Two traps that recur in the legacy XML of such screens:

- A custom `app:maxLength` attribute may map to `maxEms` — a **width hint, not a length filter**. The
  only real cap is an `InputFilter.LengthFilter` set in code.
- A visibility expression like `binding.someEditText.isNotEmpty()` may be resolving the **ViewGroup**
  extension (`childCount != 0`, always true) rather than text emptiness. Read which extension it
  resolves to before replicating the condition.

**Do not add a field to a prop-sync `LaunchedEffect` when something else writes it.** If the effect
re-runs whenever city/region change — exactly what the postal lookup does — and the ViewModel never
writes the postal code back, syncing it wipes the digits the user just typed. Anything that must
rewrite the field belongs in a separate, narrowly-keyed effect.

---

## Nav-graph id ≠ class name: verifying a legacy fragment is really dead

Before deleting a "migrated ages ago" XML fragment, **never** judge reachability by grepping the class
name — grep the **nav-graph destination id that hosts it**, then grep every inbound `<action>` id.

> **Concrete case:** a legacy `SettingsFragment` was hosted by `@id/legacySettingsFragment`, while
> `R.id.settingsFragment` — the id every live caller navigates to — resolved to the *Compose*
> replacement. The names collide; the destinations do not. Grepping the class name makes the dead
> fragment look alive; grepping the real host id showed **zero** Kotlin references.

Procedure:

1. Find the `<fragment android:name="…TheFragment">` block; note its `android:id`.
2. Grep every `<action app:destination="@id/thatId">` and collect the action ids.
3. Grep each action id **and** the raw destination id in `*.kt`. Zero hits = unreachable.
4. Watch for **closed dead loops** — screen A references an action to screen B, but nothing can reach
   screen A either, so both are dead together.
5. Grep each sibling class in the package **individually**. Package proximity means nothing: a
   same-named-prefix ViewModel in the same folder can be injected by twenty live classes.
6. Deleting a layout kills its generated `*Binding` class — grep the binding name too, not just the
   layout file name.
7. **DI-registered adapters are invisible to a "who constructs this" grep.** Check for injection at
   the type, and delete the DI line with the class.

**Migrations leave one caller behind.** Expect exactly one straggler — typically a dashboard banner or
a deep link — even when the obvious menu entry was migrated long ago, and even when the *same file*
already routes elsewhere for the normal path. Repoint it to the new destination with whatever extras
the new start-destination switch expects; do not just delete the branch.

**Check whether an Activity hosts its own nav graph before trusting the main one.** A fragment that
looks orphaned in `nav_graph.xml` can still be live inside an Activity's private `NavHostFragment`.
One-line check:

```bash
grep -l "NavHostFragment\|navGraph" app/src/main/res/layout/activity_*.xml
```

**Finding an old flow that shares no name with its replacement.** Grepping the new feature's name
finds nothing legacy, because the old chain was named after the old product vocabulary. Read the
**new** flow's caller instead — a commented-out `// Intent(requireActivity(), OldActivity::class.java)`
line sitting above the new `navigate(...)` call names the old flow exactly.

**Deleting an Activity** means removing its `<activity>` entry from `AndroidManifest.xml` too — and
check `exported` and who starts it before assuming it is dead.
