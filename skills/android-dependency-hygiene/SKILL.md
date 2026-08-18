---
name: android-dependency-hygiene
description: |
  Auditing Gradle modules for genuinely unused dependencies - resolving real package names from the Gradle cache instead of guessing from group ids, checking project() edges against namespaces, and the false-positive classes that fool every automated tool (empty -ktx shims, runtime-only providers, resource-only libraries). Also covers what unused module edges actually cost in build time. Use this skill when cleaning up dependencies or investigating build speed. Trigger on phrases like "unused dependencies", "clean up build.gradle", "why is the build slow", "reduce APK size", "do we still need this library", or "dependency audit".
---

# Skill: Dependency Hygiene — Finding Genuinely Unused Dependencies

Auditing `build.gradle.kts` files for unused dependencies sounds trivial and is not. Every naive
approach produces a wall of false positives, and acting on them breaks the build in ways that are not
compile errors. This is the procedure that survives contact with a real multi-module project.

## When to use this skill

- "Clean up unused dependencies" / "why is our build so slow" / "why is the APK so big".
- Before adding a dependency, to check whether something equivalent is already there.
- After deleting a feature, to find what it left behind.

---

## 0. Set expectations before you start

If the release build has **R8 + resource shrinking enabled**, unused library *code* is already
stripped from the production APK. Removing declarations then buys you:

| Real gain | Why |
|---|---|
| **Build time** | Fewer artifacts to resolve, transform and merge, on every build for every developer and CI run. |
| **Debug APK size / install time** | Debug builds are not minified, so everything ships to the developer's device on every run. |
| **Cold start — occasionally** | Some libraries register a startup `ContentProvider` in the merged manifest. That runs every cold start and R8 cannot remove it. |
| **Smaller graph** | Fewer version conflicts, fewer transitive CVEs, faster sync. |

It does **not** meaningfully speed up the shipped app. Say so plainly rather than overselling it.

---

## 1. Resolve real package names — do not guess from the group id

This is the step every naive tool skips, and it is where the false positives come from. A Maven
group id is not a Java package:

| Coordinate | Actual package |
|---|---|
| `com.github.bumptech.glide:glide` | `com.bumptech.glide` |
| `org.jetbrains.kotlinx:kotlinx-serialization-json` | `kotlinx.serialization` |
| `com.jakewharton.timber:timber` | `timber` |
| `io.coil-kt:coil-compose` | `coil` |
| `io.insert-koin:koin-android` | `org.koin` |
| `com.squareup.retrofit2:retrofit` | `retrofit2` |
| `com.google.code.gson:gson` | `com.google.gson` |

Guessing marks all of these "unused" when they are heavily used. Extract the truth from the artifact
in the Gradle cache instead:

```bash
CACHE=~/.gradle/caches/modules-2/files-2.1
d="$CACHE/<group>/<artifact>"
f=$(find "$d" \( -name "*.aar" -o -name "*.jar" \) ! -name "*sources*" | head -1)
# for an .aar: unzip it, then list packages inside classes.jar
unzip -p "$f" classes.jar > /tmp/c.jar 2>/dev/null && \
  unzip -l /tmp/c.jar | grep '\.class$' | awk '{print $4}' | sed 's|/[^/]*$||;s|/|.|g' | sort -u
```

Then grep the module's `src/main` (`.kt`, `.java`, **and `.xml`**) for those packages.

## 2. Check `project(...)` dependencies against namespaces

For module-to-module edges, resolve the target module's `namespace` from its `build.gradle.kts` and
grep the consumer for that string. Catches both `import com.example.core.foo.Bar` and fully-qualified
uses like `com.example.core.resource.R.drawable.x`.

## 3. The false-positive classes — never remove these on grep evidence alone

**A. Empty `-ktx` shim artifacts.** Modern AndroidX `-ktx` artifacts are *empty*; their code was
merged into the main artifact years ago. `androidx.lifecycle:lifecycle-viewmodel-ktx` contains
exactly one package with no classes anyone imports. Removing the declaration removes the transitive
pull of the real artifact.
> `lifecycle-viewmodel-ktx`, `lifecycle-livedata-ktx`, `navigation-fragment-ktx`, `navigation-ui-ktx`,
> `room-ktx`, `room-paging`, `paging-runtime-ktx`.

**B. Runtime-only providers — never imported by design.**

| Dependency | Why it is never imported |
|---|---|
| `kotlinx-coroutines-android` | Supplies only the Android `Main` dispatcher. The API you import lives in `-core`. Removing it breaks `Dispatchers.Main` at runtime with **no compile error**. |
| `androidx.credentials:credentials-play-services-auth` | Runtime provider for the `credentials` API. |
| `room-runtime` / `room-common` | Consumed by generated code. |
| any `-bom` | Version alignment only; contains no classes. |
| annotation processors (`ksp`/`kapt`) | Never on the compile classpath. |

**C. Resource- and theme-only libraries.** `material`, `appcompat`, `constraintlayout` are consumed
through XML tag names and `parent="Theme.…"` style references. In a pure Kotlin data module they
genuinely are dead weight, but a wrong removal produces a **resource-linking failure**, not a Kotlin
compile error. Batch these separately and build after each batch.

**D. Test configurations.** `testImplementation` / `androidTestImplementation` look unused when the
test suite is stubs. That is a testing problem, not a dependency problem.

## 4. Interpreting what you find

Two findings deserve special attention because grep alone misreads them:

**A dependency that is "used" but pointlessly.** Example: a Retrofit RxJava call-adapter registered on
ten service builders while **no service method returns an Rx type**. Retrofit only consults a call
adapter when a return type matches, so every registration is inert — it exists purely to drag a
multi-megabyte reactive library into the build. Grep says "used"; reality says dead.
> Check with: does any file import the library's *types*, or only its factory/registration class?

**A `project()` edge declared in many modules but used in few.** Especially when the shared module
exposes a third-party type in its **public API while declaring that library as `implementation`
rather than `api`** — consumers then each need their own declaration. Removing "unused" copies can
break a build in a non-obvious place. Check `api` vs `implementation` on the provider before touching
the consumers.

## 5. What unused module edges actually cost

Two distinct costs, and only one of them is usually worth acting on:

- **Lost parallelism.** Gradle compiles modules concurrently only when they don't depend on each
  other. A fake edge `A → B` makes A wait for B.
- **Recompilation propagation.** With `implementation`, an **ABI** change in B recompiles its direct
  dependents. A fake edge means a module recompiles for a change it cannot observe. Note: only ABI
  (public signature) changes propagate — editing a function *body* does not.

**Before claiming this matters, check how often the module actually changes:**
```bash
git log --since='6 months ago' --oneline -- core/thatmodule | wc -l
```
The modules with the most dramatic fake-edge counts are often the ones nobody has touched in a year,
which makes the saving theoretical. Weight the finding by edit frequency, or you will confidently
recommend a change nobody will feel.

Also worth knowing: in a full build of the app module, **every** module compiles anyway. Removing
fake edges takes *zero* tasks off a clean build. The effect is confined to incremental builds.

## 6. Report, don't delete

Produce a report with tiers, and let the human choose:

- **A — verified unused.** Symbol-level grep returned zero, twice, with a different query each time.
- **B — unused `project()` edges.** Compile catches most mistakes; runtime DI failures it will not.
- **C — do not remove.** The false-positive classes above, listed explicitly so the next person
  doesn't "find" them again.
- **D — structural findings.** Usually the root cause: modules not applying the shared convention
  plugin and hand-declaring everything it already provides. Fixing that deletes more lines than any
  amount of one-by-one removal.

Order removal batches by **risk**, smallest blast radius first, one commit per batch so a breakage
bisects cleanly.

## 7. Verification for every batch

1. **Rebuild** — catches compile and resource-linking failures.
2. Build a **release** variant too — R8 surfaces missing-class warnings that debug hides.
3. **Cold-start and exercise the affected flows.** DI "no definition found" errors and missing
   runtime providers appear only at runtime.
4. If you removed something that registers a startup provider, confirm it is gone from the merged
   manifest.

## What NOT to do

- Do not trust an automated "unused dependency" plugin's output without applying §3.
- Do not remove a dependency because an IDE inspection greyed out an import.
- Do not batch a `-ktx` removal with a real removal; when the build breaks you won't know which.
- Do not present build-time gains you have not measured. Use the IDE's build analyser, record a
  before number, and compare.
