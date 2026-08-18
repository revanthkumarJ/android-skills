# Android Agent Skills

A set of **agent skills** for AI coding assistants (Claude Code, Codex, Cursor, Gemini CLI, Copilot)
working in a **multi-module Android codebase** that is part-legacy XML and part-Jetpack Compose.

These are not generic "write good Kotlin" prompts. Each file encodes a specific procedure, the
failure it prevents, and the grep or check that proves you did it — the kind of knowledge that
usually only exists in a senior engineer's head and gets rediscovered by every new contributor.

## What's here

Each skill is an **Agent Skill**: a folder with a `SKILL.md` whose YAML frontmatter carries a trigger
description. The agent pre-loads those descriptions and pulls in the full skill only when your
request matches — so you never have to name them.

```
CLAUDE.md                 always-on rules (Claude Code)
AGENTS.md                 the same contract for Codex and other agents
skills/
├── android-working-discipline/          SKILL.md
├── android-module-creation/             SKILL.md
├── android-compose-architecture/        SKILL.md
└── … 13 more
```

| Skill | What it covers |
|---|---|
| `android-working-discipline` | The meta-skill: intent-reading, decomposition, verification, self-attack, the final gate. **Apply this on every task** |
| `android-module-creation` | Creating a feature module with convention plugins |
| `android-compose-architecture` | Screen/ViewModel/state shape for a feature module |
| `android-compose-ui-patterns` | Reusable-component discipline, layout patterns, bottom sheets, previews |
| `android-compose-best-practices` | Official Compose/architecture guidance, mapped onto a real project |
| `android-compose-ui-guidelines` | Official Compose **UI** guidance — scoped to migrations and new screens only |
| `android-coroutines-flow` | Coroutines/Flow discipline, one-shot events, cancellation, dispatchers |
| `android-room-offline-cache` | Room migrations, the destructive-fallback trap, cache-first repositories |
| `android-cross-module-navigation` | Navigating between modules without a dependency cycle; feature-flag gating |
| `android-xml-to-compose-migration` | Migrating an XML+Fragment screen to Compose with behavioural parity |
| `android-legacy-flow-removal` | Deleting a dead flow end to end without breaking a live one |
| `android-gotchas` | Cross-cutting pitfalls: DI collisions, serialization, nullability, module boundaries |
| `android-platform-compliance` | Modern targetSdk behaviour changes that silently kill working code |
| `android-dependency-hygiene` | Finding genuinely unused dependencies without the usual false positives |
| `android-review-checklist` | Reviewing a branch or PR |
| `android-review-agent-comments` | Handling automated PR review bots (they are wrong more often than you'd think) |

## Assumed project shape

The skills are written against this structure. Adapt the names; the reasoning transfers.

```
:app                        legacy XML host, navigation graph, DI wiring, manifest
:core:ui                    shared Compose components and theme
:core:models                domain models
:core:network               Retrofit API surface, request/response DTOs
:core:data                  preferences, shared data access
:core:database              Room database, entities, DAOs
:core:utils                 pure helpers
:core:common                shared constants and small types
:core:resource              shared drawables/strings
:feature:<name>:data        mappers, repositories
:feature:<name>:presentation  screens, ViewModels, host Fragment
```

Stack assumed: Kotlin, Jetpack Compose + leftover XML, a constructor-DI framework, Retrofit with a
reflective JSON converter, Room, Paging 3, Navigation Component, and a remote-config feature-flag
service. Nothing here depends on *which* DI or JSON library you use — where a code sample needs an
annotation, substitute your framework's equivalent.

## Installing

The `SKILL.md` format is a shared standard, so the **same folders work in both tools** — only the
install directory differs.

**Claude Code**

```bash
cp -r skills/* ~/.claude/skills/          # available in every project
# or, for one project only:
cp -r skills/* /path/to/project/.claude/skills/
```

**Codex CLI**

```bash
cp -r skills/* ~/.codex/skills/           # available in every project
# or, for one project only:
cp -r skills/* /path/to/project/.codex/skills/
```

Then drop `CLAUDE.md` and/or `AGENTS.md` in your repo root. Those hold the always-on rules — the ones
that must apply to *every* task, which is precisely what a trigger-based skill cannot guarantee.

**Two things to do before you rely on them**

1. **Rename the placeholders.** `com.example` → your package, `App…` → your component prefix. See
   [Conventions](#conventions-used-in-these-docs).
2. **Read `android-working-discipline` yourself.** It is the one skill that should apply to every
   task rather than waiting for a trigger, which is why `CLAUDE.md` and `AGENTS.md` both instruct the
   agent to apply it unconditionally. If you only take the skills folder and skip those two files,
   add that instruction wherever your agent reads its always-on context.

Everything here is written as **orders, not advice** — agents follow imperative instructions with a
stated rationale far more reliably than they follow suggestions.

## Conventions used in these docs

- `com.example.…` is the placeholder package root.
- `App…` is the placeholder prefix for shared UI components (`AppTextField`, `AppBottomSheet`).
- `AppNetworkApi` is the placeholder for the project's Retrofit interface.
- `safeCall`, `Resource<T>`, `NetworkResult<T>`, `ScreenState` and `Paddings.*` are placeholder names
  for a shared network wrapper, a loading/success/error type, a Retrofit result type, a screen's
  sealed UI state, and the theme's spacing tokens. Most codebases have all five under some name —
  substitute yours.
- `main` is the default branch.

**On opinionated rules.** A few entries — no comments in generated code, no CLI builds, which layers
a feature has — are *choices*, and are flagged as such where they appear. They are included because
an agent follows an explicit convention far more reliably than it infers one from the code. Swap them
for your team's answers; don't delete them and leave the question open.

## Credits and context

The `CLAUDE.md`, `AGENTS.md` and `skills/` files are what I actually use day to day. They have grown
out of the projects I have worked on, and I keep updating them as I hit new things — so they lean
heavily Android, because that is what I have been building lately.

They were **inspired by and extracted from the work of [Philipp Lackner](https://github.com/philipplackner)**.
I want to be clear about that credit: my set is not a copy of his, but his approach is where a lot of
the structure came from, and he deserves the tag.

**His skills are not included here** — they are his to distribute, not mine. I downloaded mine from
**<https://www.pl-coding.com/claude-skills>**; if that is still up when you read this, you can grab
them there too. Go and get them from the source — they are worth the two minutes.

**Read both if you are setting this up for yourself**, and take whichever fits your situation. They
solve different problems:

| | this repo | Philipp Lackner's Android/KMP skills |
|---|---|---|
| Written for | an existing Android app: Jetpack Compose for new screens, XML for the legacy ones still in production | Android **and** Kotlin Multiplatform, Compose throughout, greenfield projects |
| Shape | Agent Skills (`SKILL.md` + frontmatter), auto-invoked — plus `CLAUDE.md`/`AGENTS.md` for always-on rules | Agent Skills (`SKILL.md` + frontmatter), auto-invoked |
| Bias | migration reality — parity, dead-code removal, not breaking the old flow | clean architecture done properly from day one |

- **Mine** is written for a real, existing codebase: Jetpack Compose for anything new, XML screens
  still in production for everything old, and the migration between the two. A lot of it is about
  *not* breaking the legacy flow while replacing it.
- **Philipp's** covers Android *and* Kotlin Multiplatform, and assumes Compose throughout. It is the
  better starting point for a new project, and the stricter architecture reference — a proper domain
  layer, a typed `Result<T, E>`, Ktor, type-safe Compose Navigation, and a testing skill mine does not
  have.

Neither is meant to be installed unchanged. Pick a base, adapt it to your codebase, and keep editing
it as your project teaches you things — that is the whole point.

Thanks, and I hope this is useful to you.

## Licence

MIT — `CLAUDE.md`, `AGENTS.md`, and every `SKILL.md` under `skills/`. Use them, fork them, strip the parts
that don't fit your codebase.

Nothing in this repo is anyone else's work. Philipp's skills are credited above and linked, not
redistributed.
