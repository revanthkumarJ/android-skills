---
name: android-review-agent-comments
description: |
  Handling automated PR review comments from bots - the verify, report, ask, then fix rule, fetching comments via the GitHub CLI, verifying each claim against the current code, known false-positive patterns, and when to ask versus just fix. Use this skill whenever handling review comments from CodeRabbit, Gemini Code Assist, or any automated reviewer. Trigger on phrases like "check this review", "CodeRabbit says", "the bot flagged", "fix the review comments", or "are these review findings real".
---

# Skill: Handling Automated Review Comments

How to triage and resolve automated PR review comments (CodeRabbit, Gemini Code Assist, and similar)
without letting a confident bot break your codebase.

---

## 0. The rule that comes before everything else

**Verify, report, ask — then fix. Never edit code straight from a review.**

This holds for every source of review findings: agent output pasted into the chat, bot PR comments, a
human reviewer's list. The sequence is:

1. Check each finding against the actual code (read the files, follow the call chain, check the types).
2. Report per finding: **real / not real / real but a product decision**, with the `file:line`
   evidence that settles it.
3. **Stop and ask which ones to fix.** Do not start editing because a fix is obvious or one line long.

Only after the user picks do the edits happen. Ordinary user-given tasks are unaffected — those stay
in auto mode (make the change, then report).

Why the asymmetry: a user's request is an instruction; a review finding is a *claim*. Claims get
verified before they become work.

---

## 1. Accessing the comments

The GitHub CLI must be authenticated. It is interactive, so the **user** runs the login themselves —
in Claude Code, prefix a command with `!` to run it in the session:

```
! gh auth login --web --hostname github.com
```

Then:

```bash
# Find the PR for a branch
gh pr list --head <branch> --state all --json number,title,url,state

# All inline (code) review comments
gh api "repos/<owner>/<repo>/pulls/<PR>/comments?per_page=100" \
  --jq '.[] | "\(.id) | \(.user.login) | \(.path):\(.line) | outdated=\(.position==null)\n\(.body[:400])"'

# One comment in full
gh api "repos/<owner>/<repo>/pulls/comments/<comment_id>" --jq '.body'
```

Notes:
- `.position == null` ⇒ the comment is anchored to a line no longer in the diff — often stale, or on
  since-deleted code.
- Bots put severity and effort tags at the top (`🔴 Critical`, `⚡ Quick win`). **Treat the severity
  as a claim to verify, not a fact.**

---

## 2. Core discipline

**Bots comment without full repo context and are regularly wrong.** On a single real PR, three of the
higher-severity flags — including one marked *Critical* and one *High* — were outright false
positives. Always verify before touching code.

For every comment:

1. **Reproduce the claim in the current code.** Open the file at the cited line. Confirm the issue
   exists on `HEAD` of the branch, not on a stale path.
2. **Check the false-positive patterns** in §3.
3. **Check codebase convention.** Don't apply a suggestion that fights an established pattern — e.g.
   introducing the module's only `stringResource` when every sibling hardcodes strings.
4. **Weigh blast radius.** Changes to a shared UI module or app-wide code affect every caller. Prefer
   asking.
5. **Decide:**
   - Clear-cut valid + low-risk + in-scope → **fix directly**, then report.
   - Judgment call (shared component, behaviour change, convention conflict, out of scope) → **ask
     one question with concrete options** before acting.
   - False positive / already resolved / moot → **skip**, and state why.
6. **Commit** with a descriptive message, in logical batches. Never add an agent co-author trailer.

Verification uses grep/read in the same session — never memory. See **android-working-discipline**.

---

## 3. False-positive patterns worth checking first

These are the shapes that recur across projects:

| Bot claim | Reality to check |
|---|---|
| "This won't compile without importing X" | Many Compose APIs are **scope members**, not extensions — e.g. `items(count: Int, …)` is a `LazyListScope` member; the import is only needed for the `items(List)` / `items(Array)` extensions. Sibling screens compiling without the import settle it. |
| "This `.toLong()` will crash on startup" | Check whether the call is already inside a `try { … } catch { return default }`. Also check whether the identical pattern exists at a dozen other sites — if so, it is a convention, not a bug. |
| "Rotation triggers a full reload via `onResume`" | Check the manifest. If the activity is orientation-locked, it cannot rotate. |
| A comment on a path that no longer exists | Modules get folded into others and deleted. Verify with `git ls-files <path>` before spending time on it. |
| A suggestion that changes behaviour rather than hardening it | Read the semantics. A "safer" null-coalescing rewrite can let a bad value *fall through and enable* a feature, where the current code disables it on bad state. That is a regression dressed as a fix. |
| "Add a null check" on a value that is non-null by type | Kotlin's type system may already guarantee it; the bot may be reasoning about the Java view. |

Add to this table every time a bot is wrong in your repo. It compounds.

---

## 4. When to ask vs. just fix

**Just fix** — verified valid, low risk, in scope: missing `contentDescription`, an unreleased
resource in an `AndroidView` `onRelease`, a missing defence-in-depth permission check, an unhandled
`LoadState.Error`, an uncaught exception in a bare `flow { }`.

**Ask first** — with concrete options:
- Any change to a shared UI or app-wide component (blast radius).
- A suggestion that conflicts with a module convention.
- A "fix" that changes runtime behaviour, not just robustness.
- Work outside the PR's scope (a separate refactor wearing a review comment's clothes).
