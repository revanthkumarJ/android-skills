---
name: android-cross-module-navigation
description: |
  Navigating between modules without a dependency cycle - a navigation destination registry so feature modules never see the app module's R.id, feature-flag gated old-vs-new flows, gating EVERY entry point, nav-args maps, retiring a graduated flag, and cross-flow reload via fragment results. Use this skill whenever a feature module must navigate to a screen it cannot import, or when wiring a feature flag between an old and new flow. Trigger on phrases like "navigate from this module", "feature flag", "old flow vs new flow", "R.id not visible", "nav args", "remove the flag", or "refresh the previous screen after saving".
---

# Skill: Cross-Module Navigation & Flow Integration

> Apply **android-working-discipline** (verification, self-attack, final gate) while executing this skill.

## When to use this skill

Whenever a Compose feature module needs to navigate to an `:app` (XML) destination, when wiring a
feature-flag-gated "old vs new" flow, or when one flow must trigger a refresh in another after the
user returns.

---

## 1. Feature modules cannot see `:app` `R.id.*`

Feature modules are separate Gradle modules with no access to the `:app` module's `R.id.*`. Do **not**
thread destination ids through argument bundles for new code — use a central registry.

### A `NavigationDestinationRegistry` in the shared UI module

- `:app` registers all destinations once in the host Activity
  (`NavigationDestinationRegistry.init(mapOf(...))`), before `super.onCreate`.
- Each value is a **lazy lambda evaluated on every lookup**, so a destination can reflect current
  feature-flag state rather than the value at startup.
- `NO_DESTINATION = -1` is the "not registered / not applicable" sentinel.
- Any module reads a destination through a typed accessor:
  `NavigationDestinationRegistry.settingsScreen`.

### To add a new destination for a feature module to use

1. Add a key constant + typed accessor in the registry (shared UI module).
2. Register it in the host Activity's `initNavigationDestinations()` → `KEY to { R.id.someFragment }`.
3. Read it in the feature module via the accessor and `findNavController().navigate(id, bundle?)`.

Navigating by **destination id** (not action id) works from any fragment in the app graph.

---

## 2. Feature-flag-gated "old vs new" flow pattern

A remote-config helper in `:app` exposes `useNewX()` booleans. The recurring shape:

- a JSON config string per environment, parsed into a model,
- excluded when an allow/deny list contains the current account id,
- otherwise `BuildConfig.VERSION_CODE >= config.versionCode`.

Copy an existing method when adding a new toggle, rather than inventing a second shape.

> ### ⚠️ Gate EVERY entry point, not just the one the user named
>
> A legacy screen usually has more ways in than the obvious menu row. Gating only one leaves users on
> the old screen half the time while the flag is on. Grep the destination id **and** its `action_*`
> ids across the whole `:app` source set.
>
> A real example: one profile screen had **four** entry points — a settings list, a chip in a list
> row, a dashboard banner, and a deep link from the host Activity. The deep link additionally passed
> a `FROM_DEEP_LINK` extra, which had to be carried through to the new destination or the new screen
> silently lost context.

### Two ways the toggle can drive navigation

**A. The registry provider gates it.**

```kotlin
SETTINGS to { if (useNewSettings()) NO_DESTINATION else R.id.legacySettingsFragment }
```

A `NO_DESTINATION` result is itself the "use the new flow" signal — feature modules branch on it
**without** needing feature-flag access at all:

```kotlin
val legacy = NavigationDestinationRegistry.settings
if (legacy != NavigationDestinationRegistry.NO_DESTINATION) navigate(legacy)      // old
else navigate(NavigationDestinationRegistry.newSettings, newFlowBundle)           // new
```

A key can also resolve **directly to whichever screen the flag picks**, so the caller never branches:

```kotlin
ITEM_DETAILS to { if (useNewItemDetails()) R.id.itemDetailsComposeFragment else R.id.itemDetailsFragment }
```

**Prefer this** over threading `use_new_x` plus both ids through arguments when several fragments open
the same flow: the gate lives in one place and every existing caller inherits it.

**B. A nav-args map carries the flag + ids** (see §3).

### Bundles, start destinations, and one host per entry point

A new destination usually needs a **bundle** the host reads (`open_sub_screen=true`,
`bottom_sheet_destination_id=…`). The registry carries only ids, so pass the bundle at the
`navigate(...)` call.

A host fragment that supports several start destinations via flags gets confusing fast:

| Flag | Start destination |
|---|---|
| `open_print_settings` | `PrintSettings` |
| `open_custom_fields` | `CustomFields` |
| _(none)_ | `Settings` |

**Give a distinct entry point its own fragment, not another flag on a shared host.** A start-destination
flag works identically at runtime, but the call site then reads "navigate to settings" when the user
is opening something else entirely — and that gets mis-reviewed. **One fragment per user-visible
entry point; share the *screens*, not the host.**

Do **not** repurpose an existing registry key's meaning — other consumers may rely on its current
old-id / `NO_DESTINATION` behaviour. Add a **new** key instead.

---

## 3. Nav-args maps

Several fragments build a `mapOf(...)` of destination ids + feature flags passed into a new flow.
There is usually a shared builder plus a private copy in each fragment that predates it.

Entries look like:

```kotlin
"use_new_create_flow" to remoteConfig.enableNewCreateFlow(),
"print_setting"      to (if (useNewSettings()) R.id.settingsComposeFragment else R.id.printSettingFragment),
"plan_upgrade"       to R.id.planListFragment,
```

**When adding a destination/flag used by the new flow, add it to EVERY such map** — the shared builder
AND each fragment's copy. Grep an existing sibling key to find all the sites. A missing entry does not
crash; it resolves to `0` and the onward navigation silently does nothing.

---

## 3b. Retiring a graduated flag (deleting the old flow)

Once a new flow is stable, the toggle and the legacy screen come out together. Removing only the
`useNewX()` method leaves the old destination reachable — it is never the whole job. Work the full
chain:

1. **The flag method** + its per-environment config key constants. Check for an older orphaned pair
   too; dead flag constants routinely survive for years.
2. **Every `if (useNewX())` branch** — keep the new arm, delete the old. The arms are often **not**
   equivalent: the legacy arm may set keys the new one never did, or build a plain `Bundle` where the
   new one passes a nav-args map. Keep the new arm's behaviour as-is; do not port the legacy extras
   across.
3. **Both nav-args entries in every map** (§3): the flag `"use_new_x"` **and** the legacy id
   `"x_details" to R.id.oldFragment`.
4. **Forwarding bundles that relay args onward** — any navigation-handler class in a feature module
   that branched on the flag, plus its `private const val`s.
5. **The registry**: the key, its typed accessor, and the host-Activity provider entry. Confirm the
   accessor has no remaining consumers first.
6. **Unconditional callers of the old destination that never saw the flag.** This is the easy miss —
   screens that navigated straight to `R.id.oldFragment` with a bare `Bundle()`. They have no
   nav-args of their own, so give them the shared args builder instead; a bare bundle leaves every id
   at `0` and the new screen's onward navigation dies silently.

Then delete the fragment, its **exclusive** layouts, and the nav-graph `<fragment>` block **plus every
`<action>` elsewhere in the graph that targets it** — actions live under the *source* destination, so
grep the id across the whole file, not just the block you deleted.

Check shared helpers before deleting the package: adapters and callback interfaces often live in the
old fragment's package while being used by an unrelated screen.

Verify with a repo-wide grep for every removed symbol, then parse the nav graph and assert no
`app:destination` / `app:popUpTo` points at a missing id — **an orphaned action is a runtime crash,
not a compile error.**

The flag and the fragment are only the top of the removal. The screen's ViewModel, shared-ViewModel
fields, repository methods, service endpoint and request/response models die with it — see
**android-legacy-flow-removal** for the full layer-by-layer checklist, including
the case where the old flow has **no** flag at all.

---

## 4. Cross-flow reload after returning (fragment result → Compose refresh)

To make screen A reload after the user edits data in screen B and navigates back, use the
FragmentManager result API on the **activity's** `supportFragmentManager`:

**Producer** (screen B, on save/delete success — often bridged from a ViewModel one-shot event
through the host fragment):

```kotlin
requireActivity().supportFragmentManager.setFragmentResult(
    "add_edit_item_request",
    bundleOf("add_edit_item_success" to true)
)
```

**Consumer** (screen A's host fragment, in `onViewCreated`):

```kotlin
activity?.supportFragmentManager?.setFragmentResultListener(REQUEST_KEY, viewLifecycleOwner) { _, b ->
    if (b.getBoolean(SUCCESS_KEY)) viewModel.onAction(RefreshX)   // ViewModel re-fetches
}
```

Notes:

- `FragmentManager` **buffers** the result until a `STARTED` listener is registered, so it survives
  the producer setting it while the consumer's view is destroyed during navigation — it is delivered
  when the consumer returns and re-registers.
- Register the listener with `viewLifecycleOwner`, not the fragment.
- To avoid a cross-feature Gradle dependency, the request/success **string keys are duplicated as
  literals on both sides**. Keep them identical — this is failure mode #8 in
  **android-working-discipline**. Copy-paste from the consumer's source line and note both locations in
  your answer.
- For a ViewModel-driven Compose screen, emit a one-shot event on success, collect it in the screen,
  and invoke an `onXChanged: () -> Unit` callback that the host fragment wires to `setFragmentResult`.
  The Compose screen never touches the FragmentManager itself.
