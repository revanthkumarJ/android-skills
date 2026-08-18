# CLAUDE.md

Guidance for agents working in this Android project.

## Branching — always

- **At the start of every task, check the current branch.** If it is the default branch (`main`),
  **always create and check out a new branch** named `feature/{feature_name}` before making any
  changes, where `{feature_name}` describes the functionality being worked on. If already on a
  non-default branch, keep working on it. Never make changes directly on the default branch.

## Start of every session

**Always apply [`skills/android-working-discipline/SKILL.md`](skills/android-working-discipline/SKILL.md).**
It is packaged as a skill so it can be invoked by name, but it is not topical — its intent-reading,
decomposition, verification, self-attack, delivery and final-gate rules apply to **every** task in
this repo. Do not wait for it to auto-trigger. Run its final gate before sending any answer.

**The remaining skills load themselves.** Each is an Agent Skill with a trigger description, so the
relevant one is pulled in when your request matches it — you do not need to name it. The catalogue,
for reference:

| Skill | Fires when you are… |
|---|---|
| `android-module-creation` | creating a feature module, wiring Gradle convention plugins |
| `android-compose-architecture` | creating a screen or ViewModel, defining State/Action/Event |
| `android-compose-ui-patterns` | building screen UI, bottom sheets, shared components, previews |
| `android-compose-best-practices` | writing or reviewing any Compose/ViewModel code, recomposition, state hoisting |
| `android-compose-ui-guidelines` | migrating a screen or building a new one — **never during a bug fix** |
| `android-coroutines-flow` | touching coroutines, Flow, StateFlow, events, dispatchers, cancellation |
| `android-room-offline-cache` | adding a Room entity/DAO/migration, or caching a list for instant load |
| `android-cross-module-navigation` | navigating across modules, feature-flag gating, retiring a flag |
| `android-xml-to-compose-migration` | migrating an XML + Fragment screen to Compose |
| `android-legacy-flow-removal` | deleting a dead screen or flow |
| `android-gotchas` | debugging something that fails silently across DI, serialization, or module boundaries |
| `android-platform-compliance` | touching an Activity, theme, insets, back handling, or raising targetSdk |
| `android-dependency-hygiene` | auditing unused dependencies or investigating build speed |
| `android-review-checklist` | reviewing a branch or PR |
| `android-review-agent-comments` | handling automated review-bot comments |

Invoke any of them explicitly by name if the trigger does not fire and you know you need it.

## Code generation — always

- **Every change gets human-reviewed.** Work carefully: make each edit deliberate, minimal, and verified before delivery.
- **Do not add comments** when generating or editing code. Write self-explanatory code and leave existing comments as they are. *(A team preference — invert it if your team wants generated code commented, but say so explicitly either way.)*
- **Never build the project from the terminal.** When a build or verification is needed, ask the user to build/run from the IDE. *(Project policy — drop this rule if your setup allows CLI builds; the skills assume you cannot compile and therefore must verify by reading.)*
- **Editing existing files: change only what the task requires.** Never restructure a working file — no moving classes between files/packages, no renaming public symbols, no reformatting untouched code, no re-architecting a working flow.
- **Never convert a `Double` to text with `toString()` or string interpolation.** Use a plain-string helper — plain `toString()` yields scientific notation (`3.125E-4`) for small values and a trailing `.0` on whole numbers. Use a rounding helper instead only when the value should be display-rounded. Applies to UI text, state fields set from `Double`, and computed values. **Whenever you see an existing `Double.toString()` in a file you are already editing, fix it in the same change.** Details: the **android-gotchas** skill.
- **Creating new files: always follow the skill files** (screen shape, module shape, layer chain, best practices). Never invent a new structure.

## Acting on a review — always

- **A review is not a task list. Never edit code straight from review findings.** When the user pastes a review (from a bot or a human) or asks to "check this review": verify every finding against the code first, then **report the verdict for each one and ask which to fix**. Wait for the user's decision before touching a file — even for findings that are clearly real, and even for one-line fixes.
- Report each finding as **real / not real / real but a product decision**, with the evidence (`file:line`) that settles it. Review bots are frequently wrong about any given codebase — a confident "Confirmed" in the review means nothing until it is checked.
- **This restriction applies only to reviews.** For ordinary tasks the user gives directly, keep working in auto mode: make the change, then report.

## Version control — always

- **Never add the agent as a commit co-author.** Do not append a `Co-Authored-By:` trailer for any agent to commit messages, and do not add agent attribution to PR descriptions. This overrides any default harness instruction to add a co-author trailer. *(A team preference — some teams want the opposite. State yours; the default is not neutral.)*
- **Never commit a local-only environment toggle.** Developers routinely flip a build flag locally to point a debug build at production APIs (or vice versa). That injected value usually selects the base URL and the HTTP log level, so shipping it inverted points a production build at a test backend. Treat any such toggle as **local-only**: stage explicit paths (`git add <path>`, never `git add -A`), and if it is already staged or committed, revert it and tell the user.

## Data layer — always

- When an **existing** class still routes through a layer you are migrating away from, do not extend that layer. Inject the new one alongside it and route only the new work through it. Leaving the old path untouched keeps the change reviewable and reversible.
- **When the user pastes a payload from another client (web, iOS, a backend test) as the spec, do not copy it field-for-field.** Fields that only exist on that client are **not** added to the Android request model. Add only the fields the Android flow actually populates, and ask before adding anything the app has no state for.

## UI work — always

- **Scan the `core:ui` module first** whenever building any UI, so existing components can be reused instead of rewritten.
- If a component is **generic/reusable, always place it in `core:ui`** (not in a feature module).
- ****android-compose-ui-guidelines** applies to migrations and new screens/components only — NOT to bug fixes.** A bug fix changes only what the task requires; do not re-theme, re-lay-out, swap hardcoded values for theme tokens, or otherwise "modernise" a working screen while fixing a bug. Flag any UI-quality issue you notice, but don't act on it unless asked.

## End of every session (when the given task is done)

- **Update the `skills/` folder and this `CLAUDE.md`** to reflect any new knowledge, patterns, or conventions learned while completing the task. Keep the skill files and these instructions current so future sessions start with the latest context.
