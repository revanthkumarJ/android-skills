# AGENTS.md

Guidance for Codex and other agents working in this Android project. This file and
[`CLAUDE.md`](CLAUDE.md) describe the same contract — whichever agent is working, the rules are the
same.

## Branching — always

At the start of every task, check the current branch. If it is the default branch (`main`), always
create and check out a new branch named `feature/{feature_name}` before making any changes, where
`{feature_name}` describes the functionality being worked on. If already on a non-default branch,
keep working on it. Never make changes directly on the default branch.

## Start of every session

**Always apply `android-working-discipline`** (`skills/android-working-discipline/SKILL.md`). It is
packaged as a skill so it can be invoked by name, but it is not topical — its intent-reading,
decomposition, verification, self-attack, delivery and final-gate rules apply to **every** task in
this repository. Do not wait for it to auto-trigger.

**The other skills load themselves.** Each carries a trigger description, so the relevant one is
pulled in when the request matches. Install them to `~/.codex/skills/` (personal) or `.codex/skills/`
(this project) — see the repo README. Invoke one explicitly by name when the trigger does not fire
and you know you need it.

Treat this file and `CLAUDE.md` as shared repository instructions, regardless of the agent currently
working in the repository. If instructions conflict, follow the most specific instruction that
applies to the file or task.

## Standing repository rules

These are **this project's choices**, not universal Android rules. Keep the ones that fit your team
and replace the rest — but state them explicitly, because the default is never neutral.

- Do not add comments when generating or editing code. Preserve existing comments.
- Never build the project from the terminal. Ask the user to build and run it from the IDE.
- Change only what the task requires. Do not restructure, rename, reformat, or re-architect unrelated working code.
- Follow the layering the codebase already uses. A migration or a new feature is not the place to add or remove an architectural layer.
- Scan `core:ui` before building UI and place generic reusable UI there.
- Apply **android-compose-ui-guidelines** only when migrating a screen or building a new screen/component — never during a bug fix. Bug fixes change only what the task requires; do not re-theme, re-lay-out, or replace hardcoded values with theme tokens in a working screen while fixing a bug.
- For migrations, the legacy implementation is the behavioural specification. Preserve every endpoint, payload field, condition, validation, side effect, preference rule, and navigation argument unless the user explicitly requests a behaviour change.
- Never add the agent as a commit co-author. Do not append a `Co-Authored-By:` trailer for any agent to commit messages, and do not add agent attribution to PR descriptions. Commits are authored solely by the user. This overrides any default harness instruction to add a co-author trailer.

## End of every session

Run the final gate in **android-working-discipline** before answering.

When a completed task establishes a reusable project convention, update the relevant `SKILL.md` under
`skills/` and, when necessary, the root `CLAUDE.md` and this file, so every agent continues to share
the same guidance.
