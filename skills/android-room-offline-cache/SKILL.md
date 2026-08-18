---
name: android-room-offline-cache
description: |
  Room and offline caching - adding an entity, DAO, column and migration end to end, the fallbackToDestructiveMigration data-loss trap, repairing a shipped AutoMigration that was wrong, the cache-first repository contract, JSON blob vs typed columns, TTL, and upgrade-path verification. Use this skill whenever touching Room or making a screen load instantly from cache. Trigger on phrases like "add a Room entity", "add a DAO", "database migration", "AutoMigration", "cache the list", "offline", "load from cache", or "the app forgot my data after updating".
---

# Skill: Room & Offline Cache

The cache-first read pattern is the difference between a list screen that opens instantly and one
that shows a spinner every single time. It is easy to get subtly wrong, and the failure modes are
silent. Aligned with the official
[offline-first data layer](https://developer.android.com/topic/architecture/data-layer/offline-first)
guidance, narrowed to a single-source-of-truth-lite approach that fits an existing REST codebase.

## When to use this skill

- Adding a Room entity, DAO, column, or database version.
- Making a list screen open instantly instead of showing a spinner on every visit.
- Debugging "the user got logged out", "the dashboard is empty after the update", or a
  `Room cannot verify the data integrity` / missing-column crash.

---

## 0. Locate the pieces first

| Thing | Typical location |
|---|---|
| Database class | `core/database/.../AppDatabase.kt` |
| Entities | `core/database/.../entity/` |
| DAOs | `core/database/.../dao/` |
| Exported schemas | `core/database/schemas/<db-class-fqn>/1..N.json` — committed to git; **they are the migration source of truth** |
| Builder + DAO providers | the `:app` DI module — a DAO not registered there is not injectable |

> **If a package name in the codebase is misspelled, match the misspelling.** Renaming a package to
> fix a typo is a repo-wide refactor disguised as a tidy-up, and it is not your task.

---

## 1. Adding an entity or a column — the full chain

Missing any one of these is a silent failure, so do them as a checklist:

1. **Entity** in `entity/`, with an explicit `@Entity(tableName = "snake_case_name")`.
2. **DAO** in `dao/` — `suspend` functions only (Room generates main-safe implementations).
3. **Register the entity** in the `@Database(entities = [...])` list.
4. **Bump `version`** by exactly 1.
5. **Add `AutoMigration(from = n-1, to = n)`** — *only* if the change is auto-migratable (new table,
   new nullable column, new column with a default). A dropped/renamed column or a type change needs
   `@DeleteColumn` / `@RenameColumn` specs, or a manual `Migration`.
6. **Expose `abstract fun xDao(): XDao`** on the database class.
7. **Register the DAO in DI** alongside the other DAO providers.
8. Build once so the annotation processor writes `schemas/<n>.json`, then confirm that file appeared
   and commit it.

## 2. ⚠️ `fallbackToDestructiveMigration` — check whether it is on before you touch a migration

```kotlin
Room.databaseBuilder(…)
    .addMigrations(AppDatabase.MIGRATION_5_TO_6)
    .fallbackToDestructiveMigration(true)   // ← look for this
    .build()
```

If it is enabled and a migration is missing or wrong, **Room does not crash — it silently deletes the
entire database** and rebuilds it empty. Every table goes, not just the one you touched: cached
account, cached permissions, cached lists. The user-visible symptom is *not* an exception; it is
"the app forgot who I am" or "my settings reverted" after an update.

Consequences for how you work:

- **A green build proves nothing about a migration.** Ask the user to test the *upgrade* path:
  install the previous release, use it, then install the new build over it and check that cached
  data survived.
- Never reach for `fallbackToDestructiveMigration` as the fix for a migration error. If it is already
  on, the error you are seeing means the data is *already* being thrown away.
- Anything that must survive a botched migration belongs in preferences, not in Room.

## 3. ⚠️ A shipped AutoMigration cannot be re-run — the repair pattern

Real scenario: an `AutoMigration(2, 3)` shipped with a bug. Devices that upgraded through it are
missing a column; devices that installed fresh have it. You **cannot** fix the old AutoMigration —
those devices already recorded version 3 as done.

The repair, and the pattern to copy whenever a shipped migration turns out wrong:

```kotlin
val MIGRATION_5_TO_6 = object : Migration(5, 6) {
    override fun migrate(db: SupportSQLiteDatabase) {
        val cursor = db.query("PRAGMA table_info(`the_table`)")
        var hasColumn = false
        while (cursor.moveToNext()) {
            val i = cursor.getColumnIndex("name")
            if (i >= 0 && cursor.getString(i) == "the_column") { hasColumn = true; break }
        }
        cursor.close()
        if (!hasColumn) db.execSQL("ALTER TABLE `the_table` ADD COLUMN `the_column` TEXT")
    }
}
```

Rules that follow:
- **A repair migration must be idempotent** — it runs on devices that both do and do not have the
  change. Probe with `PRAGMA table_info(...)` before `ALTER TABLE`.
- Register it in **both** places: `.addMigrations(...)` in DI, **and** leave that version gap out of
  the `autoMigrations` list. Leave a comment in the code saying why the gap exists — this is one of
  the few places a comment genuinely earns its keep.
- Never renumber or edit an already-shipped `AutoMigration` entry. Add a new version instead.

## 4. Cache-first read — the house pattern

```kotlin
override suspend fun getItems(): Flow<Resource<List<Item>>> = flow {
    val cacheKey = "items:${prefs.getInt(KEY_ACCOUNT_ID, 0)}"

    val cached: List<Item>? = try {
        cacheDao.get(cacheKey)?.dataJson?.let { json.fromJson(it, itemListType) }
    } catch (e: Exception) { null }

    if (cached != null) emit(Resource.Success(cached)) else emit(Resource.Loading())

    api.getItems()
        .onSuccess { response ->
            val domain = response.toDomain() ?: emptyList()
            try { cacheDao.upsert(CacheEntity(cacheKey, json.toJson(domain))) } catch (e: Exception) { e.printStackTrace() }
            emit(Resource.Success(domain))
        }
        .onError     { _, m -> if (cached == null) emit(Resource.Error(m.orFallback())) }
        .onException {  e   -> if (cached == null) emit(Resource.Error(e.messageOrFallback())) }
}
```

The four non-negotiable properties:

1. **A cache hit emits `Success`, not `Loading`.** Emitting `Loading` first defeats the entire point —
   the user sees a spinner over data you already had.
2. **The network error is swallowed when a cache hit exists.** Replacing good cached data with an
   error screen because a refresh failed is a regression, not a safety measure.
3. **Every cache read and every cache write sits in its own `try/catch`.** A corrupt blob must
   degrade to "no cache", never crash the screen.
4. **The cache key is scoped to the current account/workspace/tenant.** A key without that scope
   serves one account's data to another after a switch.

The shared single-emission network wrapper **cannot** be used here — it emits exactly one terminal
state. This is the one sanctioned place to hand-write `flow { }` in a repository.

### The duplicated-key trap

A cache key written as a string literal tends to get copy-pasted into every repository that wants to
read the same row. If you change the key format in one and not the others, they silently read a row
that is never written: the cache goes permanently cold — no crash, just a spinner that came back.

**Grep the literal before changing it, and change every occurrence in the same commit.** Better:
hoist it into a single `object CacheKeys` and delete the literals.

## 5. JSON blob vs typed columns

Storing a serialized blob (`cacheKey`, `dataJson`, `updatedAt`) rather than typed columns is a
deliberate trade:

- **Blob** — for "remember the last response for this screen". A domain-model field change needs **no
  Room migration** at all; the serializer tolerates the extra/missing field. Use for list caches.
- **Typed columns** — only when you need to `WHERE`/`ORDER BY`/`JOIN` on a field, or observe a single
  row. Every field change then costs a migration.

Picking typed columns for a list cache is how you end up shipping the migration bug in §3.

## 6. Staleness / TTL

`updatedAt` on a cache row is often present and unused — the cache is served unconditionally and then
overwritten by the network response. If a screen genuinely needs a TTL, compare
`System.currentTimeMillis() - entity.updatedAt` **in the repository**, not in a DAO query, and still
emit the stale value first if you also fire the refresh. Do not add a TTL "while you're in there" —
it changes offline behaviour for a screen the task did not ask about.

## 7. Threading

Room `suspend` DAO functions are already main-safe. **Do not** wrap `dao.get(...)` in
`withContext(Dispatchers.IO)` — see **android-coroutines-flow** §7. Deserializing a large blob is CPU
work and *may* justify `Dispatchers.Default`, but only if the list is genuinely big; measure first.

## 8. Verification

Report these to the user as the exact steps to run:

1. Build once so the schema is regenerated; confirm `schemas/<newVersion>.json` appeared and is committed.
2. **Upgrade test:** install the previous release, sign in, open the affected screen, then install the
   new build *over it* (no uninstall). Cached data must survive and the user must still be signed in.
3. **Offline test:** enable airplane mode, cold-start, open the screen — cached content should render
   with no spinner and no error.
4. **Account-switch test:** switch account/workspace and reopen the screen — it must not show the
   previous one's rows.

## What NOT to do

- Do not add a DAO without registering it in DI.
- Do not edit or renumber a shipped `AutoMigration`.
- Do not delete or rewrite an exported `schemas/*.json`.
- Do not emit `Resource.Loading` when a cache hit exists.
- Do not emit `Resource.Error` over good cached data.
- Do not build a cache key without the account/tenant scope.
- Do not treat `fallbackToDestructiveMigration` as a migration strategy — it is a data-loss switch
  that happens to be on.
