---
name: android-review-checklist
description: |
  Reviewing an Android branch or pull request - diffing against the merge base, tracing each changed flow end to end, functional checks, Compose checks, repository checks, severity-ranked findings with confidence markers and file:line evidence, and the delivery format. Use this skill when reviewing a branch, a PR, or a diff. Trigger on phrases like "review this branch", "review my PR", "check this diff", "is this ready to merge", or "code review".
---

# Skill: Branch Review

Use this checklist whenever reviewing the current branch before a pull request.

## Scope

Compare the current branch against the default branch using the merge base:

```shell
git diff --stat main...HEAD
git diff --name-status main...HEAD
git diff main...HEAD
git log --oneline main..HEAD
```

Review committed changes and report unrelated working-tree changes separately. **Do not modify files
during a review unless the user explicitly asks for fixes.**

## Review order

1. Read `AGENTS.md`, `CLAUDE.md`, `skills/**android-working-discipline**`, and the shared project skill files.
2. Identify the intended behaviour from the commit message, changed files, legacy implementation, and existing call sites.
3. Trace each changed flow end to end: UI action → ViewModel state/action/event → mapper → repository → payload → response load → navigation → side effects.
4. Run `git diff --check` and inspect deleted files, renamed symbols, new enum values, composable parameters, and DI definitions.
5. Self-attack every changed symbol by finding all callers, previews, sibling screens, exhaustive `when` expressions, and shared code paths.
6. Report only issues introduced by the branch. Keep pre-existing issues separate and clearly labelled.

## Functional checks

- Verify create, edit, update, delete, refresh, dismiss, back, loading, success, and error paths.
- Verify user-entered or selected data stays visible even when UI discoverability depends on a usage-frequency or personalisation signal.
- Verify collapsed sections still show their selected values and offer a way to expand again.
- Verify expandable sections can actually collapse when the UI says "View less".
- Verify state survives navigation where required and resets when a sheet or flow is dismissed.
- Verify every loading state returns to a usable state on **both** success and error.
- Verify buttons cannot submit repeatedly while a request is in flight.
- Verify dialogs dismiss correctly on confirm, cancel, outside tap, success, and failure.
- Verify list filtering preserves original indices when an item action indexes into the unfiltered source list.
- Verify empty lists, offline responses, null personalisation responses, and pre-existing edited values do not make controls unreachable.

## Compose checks

- State is collected with lifecycle awareness; one-time events use the established event flow.
- Business state is owned by the ViewModel; transient form state is hoisted to the right level.
- `remember` keys cover every value the calculation reads.
- Lazy lists use stable, unique keys.
- Scroll containers are not nested in the same direction.
- New reusable composables take `modifier: Modifier = Modifier`, reuse the project's shared components, and include a preview.
- Existing selected values are included in collapsed/filtered UI conditions, not only server-provided counters.
- Accessibility labels, touch-target sizes, long-text handling, and dark-mode drawables are preserved.

## Repository checks

- No new code comments were added; existing comments remain untouched.
- No unrelated restructure, rename, reformat, or architecture change is included.
- No layer was introduced that the project's architecture rules forbid.
- Repositories use the shared API interface, the shared network wrapper, and `Flow<Resource<Domain>>` where the architecture applies.
- Serialized fields use verified backend keys and stay nullable through every layer when absence is meaningful.
- New model fields have safe defaults when the model has multiple constructors or call sites.
- DI types do not collide without qualifiers.
- Navigation destinations, bundle keys, feature-flag gates, and fragment-result keys match every producer and consumer.

## Review findings

Order findings by severity:

- `P0`: release-blocking, destructive, security, or widespread outage.
- `P1`: a major user flow is broken, data can be lost or silently submitted incorrectly, or the app can crash.
- `P2`: normal behaviour is incorrect but has a practical workaround or limited scope.
- `P3`: maintainability, repo-rule, accessibility, or minor UX issue worth fixing before merge.

For every finding include:

- Priority and a concise title.
- A `Confirmed` / `Likely` / `Assumption` confidence marker.
- Clickable file and exact line.
- The concrete user flow or input that triggers it.
- The observable impact.
- The smallest appropriate fix direction.

Do not report speculative concerns without a reproducible path. If no issues are found, state that
explicitly and list the remaining verification gaps.

## Delivery

Lead with the findings, then summarise what the branch changes. State whether `git diff --check`
passed. If you cannot run a build, say so and give the user the exact flows that need device
verification.
