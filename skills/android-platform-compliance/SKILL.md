---
name: android-platform-compliance
description: |
  Modern targetSdk behaviour changes that silently kill working code - predictive back making onBackPressed overrides dead, enforced edge-to-edge making system-bar colours no-ops, fixed orientation ignored on large screens, 16 KB page sizes, and per-module compileSdk drift, each with the audit command and an on-device verification procedure. Use this skill when touching an Activity, a theme, window insets, back handling, or when raising targetSdk. Trigger on phrases like "raise targetSdk", "edge to edge", "status bar colour", "onBackPressed", "predictive back", "insets", "screenOrientation", "16 KB", or "this used to work and now does nothing".
---

# Skill: Platform Compliance (modern `targetSdk`)

Raising `targetSdk` opts the app into **every** behaviour change for that API level at once. Several
of those changes turn working code into **silently dead code** — no crash, no warning, no compile
error. This file lists the ones that bite hardest, with the audit command for each, so a "small UI
fix" doesn't ship a regression.

Sources: [Behavior changes: Android 15](https://developer.android.com/about/versions/15/behavior-changes-15),
[Behavior changes: Android 16](https://developer.android.com/about/versions/16/behavior-changes-16),
[16 KB page sizes](https://developer.android.com/guide/practices/page-sizes),
[App orientation & resizability](https://developer.android.com/develop/adaptive-apps/guides/app-orientation-aspect-ratio-resizability).

## When to use this skill

- Touching an `Activity`, a theme/style, window insets, the system bars, or back handling.
- Adding a dependency that ships native code (`.so`).
- Investigating "this used to work and now does nothing on a new phone".
- Before any release-readiness question about Play Store requirements.

---

## 0. Establish the SDK levels first — they are rarely uniform

```bash
grep -rn "compileSdk\|targetSdk\|minSdk" --include="build.gradle.kts" . | grep -v "/build/"
```

A mature multi-module project routinely has `:app` at the newest level, a shared UI module one
behind, and most library modules on whatever the convention plugin was pinned to two years ago.

**Consequence:** an API added in a newer SDK **will not resolve** inside a module compiled against an
older one. It is not a Gradle sync glitch. Options, in order of preference:

1. Put the call in `:app` and expose it to feature modules through an interface provided by DI.
2. Use the AndroidX compat wrapper (`WindowCompat`, `WindowInsetsCompat`, `ContextCompat`) — these
   exist at older compileSdk levels and do the version check for you. Prefer this.
3. Raising a module's `compileSdk` is a build-wide change — **ask first**, never as a side effect of a
   feature task.

`minSdk` matters just as much: everything must degrade on the oldest supported release.

---

## 1. Predictive back — `onBackPressed()` overrides become dead code ⚠️

**The rule.** For apps targeting **API 36+** running on an **API 36+ device**, predictive back system
animations are on by default, **`onBackPressed` is not called and `KeyEvent.KEYCODE_BACK` is not
dispatched anymore.**

**Note both halves of the condition.** It is gated on the device too. On older phones the old
behaviour persists, so these bugs will not reproduce on most test devices.

**Why an override specifically dies.** Assuming activities extend `AppCompatActivity` (i.e. AndroidX
`ComponentActivity`):

```
OLD:  system -> Activity.onBackPressed() -> your override
NEW:  system -> OnBackInvokedCallback (registered by AndroidX)
             -> OnBackPressedDispatcher.onBackPressed()
             -> enabled OnBackPressedCallback(s)
             -> else fallback: ComponentActivity.super.onBackPressed() -> finish()
```

`ComponentActivity.onBackPressed()` is not on the new chain, and that is the method a subclass
override replaces. `OnBackPressedCallback` **is** on the chain — hence the migration target.

**Audit your repo:**
```bash
grep -rn "override fun onBackPressed" --include="*.kt" .
grep -rn "enableOnBackInvokedCallback" --include="*.xml" .   # empty = no opt-out, new behaviour is live
```

**Impact is not uniform — read each body before acting:**

| Override body | Real impact |
|---|---|
| Rewinds a multi-step form (`if (step2) { showStep1() } else super`) | **Worst.** Back now leaves the whole activity, losing entered data. |
| Blocks back with a toast, no `super` call | Back was deliberately blocked; now the screen exits. |
| `super.onBackPressed(); finish()` | **Harmless.** Super already finishes; the extra call is a no-op. |
| Delegates to a method that also has an `OnBackPressedCallback` registered elsewhere | **Partial.** The callback still runs; the override's own logic does not. Read it fully. |

**Rules going forward:**
- Never write `override fun onBackPressed()`. It compiles, it is deprecated, and it will not run.
- Activity/Fragment → `onBackPressedDispatcher.addCallback(owner) { … }`.
- Compose → `BackHandler(enabled) { … }`.
- Calling `onBackPressedDispatcher.onBackPressed()` **yourself** to pop a screen is still fine — that
  is a direct invocation, not the system callback.
- **Do not mass-refactor legacy overrides as part of an unrelated task.** Report them; fix one only
  when the task is actually in that file.

### Verifying a back-handling claim on device

1. Needs an **API 36+** emulator/device — on older ones the legacy path is still used and you will
   wrongly conclude nothing is broken.
2. Breakpoint the first line inside the override, run in debug, trigger back. No hit = bypassed.
   Requires no code change.
3. **Counter-test to prove causation:** temporarily add `android:enableOnBackInvokedCallback="false"`
   to the `<application>` tag, rebuild, repeat. The override should start running again. Remove it
   afterwards — it is a deprecated opt-out with a deadline, not a fix.

## 2. Edge-to-edge is enforced — system-bar colours are no-ops ⚠️

From API 35, apps draw edge-to-edge and **cannot opt out**; at API 36 even the temporary
`windowOptOutEdgeToEdgeEnforcement` escape hatch is gone.

**Deprecated and with no effect** at targetSdk 35+:

`Window#setStatusBarColor` · `setNavigationBarColor` (gesture nav) · `setNavigationBarDividerColor` ·
`setNavigationBarContrastEnforced` · `setDecorFitsSystemWindows` — and the theme attributes
`android:statusBarColor`, `android:navigationBarColor`, `android:navigationBarDividerColor`.

**Audit:**
```bash
grep -rn "statusBarColor\|navigationBarColor\|setDecorFitsSystemWindows" --include="*.xml" --include="*.kt" .
```
Most codebases find these set in several theme files. Those lines do nothing on a modern device. Do
not add more, and do not "fix a status bar colour" by editing them — the answer is always insets plus
a real background drawn behind the bar.

**Still works:** `WindowInsetsControllerCompat` for **icon appearance**
(`isAppearanceLightStatusBars`), alongside `enableEdgeToEdge()`.

**What to do in new UI:**
- Compose → `Scaffold` handles insets for its slots; outside a Scaffold use
  `Modifier.safeDrawingPadding()`, or `windowInsetsPadding(WindowInsets.systemBars)` /
  `.navigationBarsPadding()` / `.imePadding()`.
- **A sticky bottom button must have `navigationBarsPadding()`** or the gesture bar sits on top of
  it. This is the single most common edge-to-edge bug — check it on every screen with a sticky
  bottom bar.
- XML → `fitsSystemWindows` only works if the whole parent chain cooperates. For a new XML screen use
  `ViewCompat.setOnApplyWindowInsetsListener`.
- Also changed at API 35: `Configuration.screenWidthDp/screenHeightDp` **now include** the system bar
  area. Layout maths off those values shifted. Use
  `WindowMetricsCalculator.computeCurrentWindowMetrics()`.

## 3. Fixed orientation is ignored on large screens

For apps targeting **API 36**, these are **ignored on displays with smallest width ≥ 600dp** —
tablets, foldable inner screens, desktop windowing:

`android:screenOrientation` · `android:resizeableActivity` · `android:maxAspectRatio` /
`minAspectRatio` · `setRequestedOrientation()` / `getRequestedOrientation()`

Still honoured on: displays < 600dp (most phones, flip phones, foldable outer screens), games (via
`android:appCategory`), and when the user opts into the app's default behaviour in system settings.

**Audit:**
```bash
grep -o 'screenOrientation="[^"]*"' app/src/main/AndroidManifest.xml | sort | uniq -c
find app/src/main/res -maxdepth 1 -name "layout-land" -o -name "layout-sw*"
```

If the first command shows a pile of `portrait` and the second returns nothing, every locked screen
will be drawn in landscape at tablet width using a layout designed only for a phone in portrait.

**Temporary opt-out** (buys roughly one release cycle):
```xml
<property
    android:name="android.window.PROPERTY_COMPAT_ALLOW_RESTRICTED_RESIZABILITY"
    android:value="true" />
```
in `<application>` or a single `<activity>`. **It stops working at API 37** — restrictions are then
always ignored, with no opt-out. It defers the problem; it does not solve it.

**Verify:** an emulator that is API 36 **and** ≥ 600dp wide (a tablet or Resizable profile in tablet
mode). Rotate it. If the activity rotates despite a `portrait` lock, confirmed. Control test on a
phone emulator of the same API level — it should stay locked.

## 4. 16 KB page sizes

Play requires 16 KB-aligned native libraries for apps targeting Android 15+. Pure Kotlin/Java is
automatically fine; **`.so` files are not**.

**Audit:** look for dependencies with a `-native` classifier, hardware SDKs (printers, scanners,
crop/imaging libraries), and media/ML libraries. Then verify for real: build a release bundle →
**Analyze APK** → check `lib/arm64-v8a/` for `.so` files; the NDK also ships `check_elf_alignment.sh`.

If a library is misaligned the only fixes are upgrading it, replacing it, or dropping it. Report that
as a release blocker; do not try to patch it.

## 5. Other API-35 traps — grep for each

| Trap | What to search | Fix |
|---|---|---|
| `List.removeFirst()` / `removeLast()` — Kotlin stdlib collides with the new Java `SequencedCollection` methods; **crashes at runtime on Android ≤ 14** when compiled at compileSdk 35+ | `\.removeFirst()\|\.removeLast()` | `removeAt(0)` / `removeAt(lastIndex)`. Never write these. |
| `String.format("%0$s", …)` — argument index 0 now throws | `String.format("%0` | Indices start at `%1$s`. (`%02d` is a *width* flag and is fine.) |
| `(String[]) Arrays.asList(...).toArray()` now throws `ClassCastException` | `asList(.*).toArray()` | `toArray(new String[0])` |
| TLS 1.0 / 1.1 disallowed | custom `ConnectionSpec` | Don't re-enable them. |
| `dataSync` foreground service capped at 6 h / 24 h | `foregroundServiceType` | Handle `Service.onTimeout()`. |
| Cleartext traffic | `usesCleartextTraffic` in the manifest vs `network_security_config.xml` | The manifest flag is far broader than the config. Add domains to the config, never widen the manifest flag. |

---

## Checklist — run when your change touches an Activity, theme, or window

1. No new `override fun onBackPressed()`; back goes through `OnBackPressedDispatcher` / `BackHandler`.
2. No new `android:statusBarColor` / `navigationBarColor` / `setDecorFitsSystemWindows`.
3. Any new full-screen surface applies insets; sticky bottom buttons have `navigationBarsPadding()`.
4. No `removeFirst()` / `removeLast()` on a `List`.
5. A new dependency was checked for `.so` files before it was added.
6. The API you used exists at **that module's** compileSdk — or you used the `*Compat` wrapper.
7. Your device-verify step names a **gesture-navigation** device, since that is where inset bugs show.

## What NOT to do

- Do not lower `targetSdk` to dodge a behaviour change.
- Do not add `android:enableOnBackInvokedCallback="false"` app-wide — it is an opt-out with a
  deadline and it disables predictive back everywhere.
- Do not raise a module's `compileSdk` without asking.
- Do not bulk-migrate legacy back-press overrides or dead theme attributes as part of an unrelated
  task; flag them and let the user schedule it.
