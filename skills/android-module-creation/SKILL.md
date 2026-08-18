---
name: android-module-creation
description: |
  Creating a new feature module in a multi-module Android project - folder layout, Gradle convention plugins, version catalogs, DI module wiring, navigation-graph registration, and the Application-class registration that is easy to forget. Use this skill whenever creating a new feature module or deciding where a new module should live. Trigger on phrases like "create a feature module", "add a new module", "scaffold a feature", "set up a module", "convention plugin", "build-logic", or "where should this module go".
---

# Skill: Feature Module Creation

> Apply **android-working-discipline** (verification, self-attack, final gate) while executing this skill.

## When to use this skill

Whenever the user asks to create a new feature module.

---

## Step 1 — Ask for the feature name

Before doing anything, ask:

> "What is the feature name? (e.g. products, referral, login)"

Use the answer as `[FeatureName]` (PascalCase for class names, lowercase for package/folder names).

Example, for the input `products`:

- Package base: `com.example.feature.products`
- Class prefix: `Products`
- Folder name: `products`

**Never assume the feature name.** A wrong name means every file, package, and Gradle path has to be
redone.

---

## Convention plugins (`build-logic`)

All module boilerplate belongs in composite-built convention plugins. Module `build.gradle.kts` files
**apply these instead of re-declaring** the Android/Kotlin/SDK/dependency setup by hand. Plugin
aliases live in the version catalog.

| Plugin alias | What it provides |
|---|---|
| `app.android.library` | `com.android.library` + `kotlin.android`, compileSdk/minSdk, Java + Kotlin 17, release build type, consumer proguard, baseline deps (`core-ktx`, `appcompat`, `material`, test runners) |
| `app.android.library.compose` | everything above **plus** the Compose compiler plugin |
| `app.android.di` | KSP + the DI framework's runtime, annotations and compiler |
| `app.android.feature` | `app.android.library.compose` + `app.android.di` + all `core:*` modules + the Compose / Coroutines / Lifecycle / Navigation / serialization stack |

**Rule:** a module's `build.gradle.kts` declares only the plugins it needs, its `namespace`, and the
dependencies that are *unique* to it. Never re-add anything the applied convention plugin already
provides.

> This is worth enforcing hard. When modules stop applying the convention plugin and hand-declare
> everything, you end up with dozens of copy-pasted dependency blocks that drift, and the audit in
> **android-dependency-hygiene** turns up hundreds of "unused" entries that are
> really just template rot.

---

## Step 2 — Create the data module

This skill assumes a feature is **two modules: `data` + `presentation`**, with the ViewModel calling
a repository interface directly. Adapt the layout to whatever layering your project uses — if you
also have a `domain` module, create it here too and add it to the wiring steps below.

Whichever shape you pick, **apply it to every feature**. A codebase where half the features have a
domain layer and half don't is worse than either choice made consistently.

### Folder structure

```
feature/
└── [featurename]/
    └── data/
        ├── build.gradle.kts
        └── src/main/java/com/example/feature/[featurename]/data/
            ├── di/
            │   └── [FeatureName]DataModule.kt
            ├── mappers/        (empty)
            ├── repo/           (empty)
            └── repoImpl/       (empty)
```

### `build.gradle.kts`

```kotlin
plugins {
    alias(libs.plugins.app.android.library)
    alias(libs.plugins.app.android.di)
}

android {
    namespace = "com.example.feature.[featurename].data"
}

dependencies {
    implementation(project(":core:models"))
    implementation(project(":core:network"))
    implementation(project(":core:utils"))
}
```

> Do NOT re-add `compileSdk`, `minSdk`, `compileOptions`, `kotlinOptions`, the release `buildTypes`,
> the androidx/test baseline deps, or the DI/KSP deps — the convention plugins already provide them.

### `di/[FeatureName]DataModule.kt`

```kotlin
package com.example.feature.[featurename].data.di

import androidx.annotation.Keep

@Keep
@Module(includes = [NetworkModule::class])
@ComponentScan("com.example.feature.[featurename].data")
class [FeatureName]DataModule
// annotations above are DI-framework specific — use your framework's module declaration
```

`@Keep` matters: with R8 enabled, a DI module class discovered only by reflection or annotation
processing can otherwise be stripped from a release build, and the failure appears at runtime only.

---

## Step 3 — Create the presentation module

### Folder structure

```
feature/
└── [featurename]/
    └── presentation/
        ├── build.gradle.kts
        └── src/main/java/com/example/feature/[featurename]/presentation/
            ├── di/
            │   └── [FeatureName]Module.kt
            ├── screens/        (empty)
            ├── viewmodels/     (empty)
            └── [FeatureName]Fragment.kt
```

### `build.gradle.kts`

```kotlin
plugins {
    alias(libs.plugins.app.android.feature)
}

android {
    namespace = "com.example.feature.[featurename].presentation"
}

dependencies {
    implementation(project(":feature:[featurename]:data"))

    // Add only what is genuinely unique to this feature, e.g.:
    // implementation(libs.coil.compose)
}
```

> Do NOT re-add the `core:*` modules, the Compose stack, Coroutines, Lifecycle, Navigation, DI, the
> serializer, the androidx/test baseline, or any SDK/Java/build-type config.

### `di/[FeatureName]Module.kt`

```kotlin
package com.example.feature.[featurename].presentation.di

@Module(includes = [[FeatureName]DataModule::class])
@ComponentScan("com.example.feature.[featurename].presentation")
class [FeatureName]Module
// again: your DI framework's equivalent
```

### `[FeatureName]Fragment.kt`

```kotlin
package com.example.feature.[featurename].presentation

import android.os.Bundle
import android.view.LayoutInflater
import android.view.View
import android.view.ViewGroup
import androidx.compose.material3.Text
import androidx.compose.ui.platform.ComposeView
import androidx.compose.ui.platform.ViewCompositionStrategy
import androidx.fragment.app.Fragment

class [FeatureName]Fragment : Fragment() {

    override fun onCreateView(
        inflater: LayoutInflater,
        container: ViewGroup?,
        savedInstanceState: Bundle?
    ): View = ComposeView(requireContext()).apply {
        setViewCompositionStrategy(ViewCompositionStrategy.DisposeOnViewTreeLifecycleDestroyed)
        setContent {
            AppTheme {
                Text("Hello from [FeatureName]")
            }
        }
    }
}
```

`DisposeOnViewTreeLifecycleDestroyed` is not optional in a Fragment — the default strategy disposes on
window detach, which leaks the composition across fragment transactions that keep the view attached.

---

## Step 4 — Wire up the app module

### Ask before editing `settings.gradle.kts`

> "Where in settings.gradle.kts should I add the new module includes? I'll show you the current end of
> the file first."

Then append at the confirmed location:

```kotlin
include(":feature:[featurename]:presentation")
include(":feature:[featurename]:data")
```

### `app/build.gradle.kts`

Presentation only — it pulls data in transitively:

```kotlin
implementation(project(":feature:[featurename]:presentation"))
```

### The navigation graph

Add inside `<navigation>`, before the closing tag:

```xml
<fragment
    android:id="@+id/[featureName]Fragment"
    android:name="com.example.feature.[featurename].presentation.[FeatureName]Fragment"
    android:label="[FeatureName]Fragment" />
```

### Register the DI module in the Application class

**Without this the module's DI graph is never started**, so resolving the ViewModel in the screen
fails at runtime — with a green build. Three edits, mirroring every other feature module:

1. Import the presentation DI module (keep the import list alphabetical).
2. Declare a local module alongside the other feature modules:
   ```kotlin
   val [featureName]Module = module { includes([FeatureName]Module().module) }
   ```
3. Add that value to the DI start-up `modules(...)` list.

---

## Naming reference

| Placeholder | Example (input: `products`) |
|---|---|
| `[featurename]` | `products` |
| `[FeatureName]` | `Products` |
| Class names | `ProductsDataModule`, `ProductsModule`, `ProductsFragment` |
| Packages | `com.example.feature.products.data.di` |
| Gradle path | `:feature:products:presentation` |

---

## What NOT to do

- Do NOT invent a module layout that differs from the rest of the codebase.
- Do NOT hand-write `compileSdk`, `minSdk`, `compileOptions`, `kotlinOptions`, `buildTypes`, or
  baseline androidx/test/DI/Compose deps in a module — apply the matching convention plugin.
- Do NOT apply raw `com.android.library`, `kotlin.android`, the Compose plugin, or KSP directly —
  they come through the convention plugins.
- Do NOT create any files inside `screens/`, `viewmodels/`, `mappers/`, `repo/`, or `repoImpl/` —
  leave them empty for the follow-up task.
- Do NOT add the data module to `app/build.gradle.kts` — only the presentation module.
- Do NOT modify `settings.gradle.kts` without asking where to insert first.
- Do NOT assume the feature name — always ask first.
