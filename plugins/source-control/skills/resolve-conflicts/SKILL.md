---
name: resolve-conflicts
description: "Resolve an in-progress merge/rebase/cherry-pick conflict by recovering both sides' intent from history before touching any hunk, composing both changes wherever possible, then sweeping for semantic conflicts the markers don't show. Use when: 'resolve conflicts', 'merge conflict', 'rebase stopped', 'CONFLICT (content)', git status shows unmerged paths — not for choosing merge vs rebase or PR lifecycle (use /pull-request), and not for ordinary commits (use /commit)."
argument-hint: "[paths] (optional — start with specific conflicted paths; default is every unmerged path)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  cheatsheet-stage: pr
  cheatsheet-summary: Resolve merge and rebase conflicts by recovering both sides' intent
---

## Pre-computed context

Operation state: !`git status 2>/dev/null | head -4 || echo "not a git repo"`
Conflicted paths: !`git diff --name-only --diff-filter=U 2>/dev/null || echo "none"`
Current branch: !`git branch --show-current 2>/dev/null || echo "detached/unknown"`

## Purpose

Owns HOW conflicts get resolved once an integration — merge, rebase, or cherry-pick — stops on unmerged paths. Which integration to run (merge vs rebase, when to sync with the default branch) is the caller's decision: `/pull-request`'s branch-freshness steps, the project's convention, or the user. This skill picks up at the moment git says `CONFLICT` and ends when the operation is concluded with every gate green.

**The two non-negotiable disciplines:**

1. **Intent before edits.** No hunk is resolved until the commits that produced BOTH sides of it have been read and each side's intent can be stated in one sentence. Mechanically keeping "ours" or "theirs" — `git checkout --ours/--theirs`, `-X ours/theirs`, or accepting one side because it looks newer or bigger — is not resolution; it is silent deletion of someone's change.
2. **`--abort` is not a resolution strategy.** A conflict is work, not an error. Abort only when the user explicitly decides to abandon the integration itself — never as an exit from a resolution that got hard, and never silently.

## Task

1. **Map the stop.** Identify the operation and enumerate the complete conflict inventory up front:
   - Operation type: read the `git status` header (merge / rebase / cherry-pick / revert in progress). The counterpart ref is `MERGE_HEAD`, `REBASE_HEAD`, `CHERRY_PICK_HEAD`, or `REVERT_HEAD` respectively.
   - Full unmerged list: `git status` plus `git diff --name-only --diff-filter=U`. Every path on this list must appear in the final resolution table — no path gets resolved "in passing" without a recorded justification.
   - Sides orientation: during a **merge**, `ours` = your branch (HEAD), `theirs` = the branch being merged in. During a **rebase** the labels invert — `ours` = the upstream you are rebasing onto, `theirs` = your own commit being replayed. Fix this orientation in mind before reading any hunk; misreading it is how the wrong side gets kept.

2. **Recover both intents.** For each conflicted path, before editing anything:
   - Use the operation-specific row below. Do not assume every stop has `MERGE_HEAD`, and do not use
     one generic history command as a substitute for identifying the operation first. In every row,
     replace `<path>` with the conflicted path and read the full patch after the summary.

     | Operation | Current-side history | Incoming/replayed intent |
     |-----------|----------------------|--------------------------|
     | Merge | `BASE=$(git merge-base HEAD MERGE_HEAD)` then `git log --oneline "$BASE"..HEAD -- <path>` | `git log -p "$BASE"..MERGE_HEAD -- <path>` — the incoming branch can carry multiple commits touching `<path>`; `git show MERGE_HEAD -- <path>` alone only shows the tip commit and is silently empty when an earlier commit on the branch (not the tip) touched the path |
     | Rebase | `BASE=$(git merge-base HEAD REBASE_HEAD)` then `git log --oneline "$BASE"..HEAD -- <path>` | `git show --stat --oneline REBASE_HEAD -- <path>` then `git show REBASE_HEAD -- <path>` — this exact commit is the patch being replayed |
     | Cherry-pick | `BASE=$(git merge-base HEAD CHERRY_PICK_HEAD)` then `git log --oneline "$BASE"..HEAD -- <path>` | `git show --stat --oneline CHERRY_PICK_HEAD -- <path>` then `git show CHERRY_PICK_HEAD -- <path>` — this exact commit is being picked |
     | Revert | `BASE=$(git merge-base HEAD REVERT_HEAD)` then `git log --oneline "$BASE"..HEAD -- <path>` | `git show --stat --oneline REVERT_HEAD -- <path>` then `git show REVERT_HEAD -- <path>` — recover the original change whose inverse is being applied |

     If `git merge-base` returns no commit, do not interpolate an empty `BASE` into a range. Inspect
     the exact operation ref plus `git log --all --oneline -- <path>`, and stop to ask if the history
     relationship still cannot be stated. Git documents `MERGE_HEAD`, `REBASE_HEAD`,
     `CHERRY_PICK_HEAD`, and `REVERT_HEAD` as distinct
     [pseudorefs](https://git-scm.com/docs/gitrevisions). Current Git also documents `git log
     --merge` as selecting the first present operation ref, but keeping the refs explicit makes the
     operation and orientation reviewable instead of hiding which counterpart supplied the history.
   - Read the commit messages; when `gh` is available and the commits came through PRs, pull the PR title/body and any linked issue — the WHY often lives there, not in the diff.
   - When the inline markers lack base context, re-materialize the file with it: `git checkout --merge --conflict=zdiff3 -- <path>` (or read the base directly via `git show :1:<path>`).
   - Write down, per side, one sentence of intent. If you cannot state a side's intent, you have not read enough history to resolve the hunk.

3. **Resolve each hunk — compose by default.** Both sides changed this region on purpose; the correct resolution usually keeps both purposes:
   - **Compose** when the changes are independent or complementary (one side renamed, the other extended; one fixed a bug, the other added an option): produce the version that carries both.
   - **Drop a side only with evidence** — it was superseded by the other side's later work, explicitly reverted, or a duplicate of what the other side already does. Dropping a side is a decision that gets recorded with its evidence, never a default.
   - **Genuinely incompatible** intents (both sides redefined the same behavior differently): keep the side that matches the integration's stated goal, and surface the trade-off — the losing side's intent is reported, not buried.
   - **Never invent** behavior neither side had. The resolution space is bounded by what the two sides wrote; new design happens after the integration, as its own change.

4. **Semantic-conflict sweep.** Marker-free is not conflict-free. The merge machinery only flags textual overlap; it happily auto-merges a rename on one side against a new call site of the old name on the other, a signature change against a new caller, or a deleted helper against fresh usage. After the last marker is gone:
   - Grep the whole tree for symbols that either side renamed, re-signatured, moved, or deleted — including files git auto-merged without conflict.
   - Run the project's gates in its own order — typecheck/build, then tests, then lint/format (via your build/test skills when installed, the project's documented commands otherwise). Fix what the integration broke. Not declaring done before these pass is the point of this step.

5. **Verify and conclude.**
   - Present the resolution table: every path from step 1's inventory, one line each — resolution taken (composed / kept-ours-with-evidence / kept-theirs-with-evidence) and why.
   - Confirm gates are green, stage the resolved paths (surgically, per `/commit`'s staging discipline — never `git add -A`), and conclude with the operation's own continuation: `git merge --continue`, `git rebase --continue` (repeating steps 1–5 at each subsequent stop until the rebase completes), `git cherry-pick --continue`, or `git revert --continue`. The concluding commit message is machine-prepared by git, which is why this concludes via `--continue` rather than composing `/commit`.

## Never abort — and what to do instead

When resolution stalls (intent unrecoverable from history, both sides' authors unavailable, incompatibility with no stated integration goal), the fallback is to **stop and ask the user** with the evidence gathered so far — the intent table, the incompatible hunks, the candidate resolutions. `git merge --abort` / `git rebase --abort` throws away every hunk already resolved and leaves the branch exactly as stale as before; it converts work into a status report. If the user chooses to abandon the integration, abort is then their decision to execute or approve — report it as abandoned, never as resolved.

## Adapting to your environment (graceful degrade)

Everything runs on plain `git`. Adjacent capabilities are optional: `gh` enriches intent archaeology with PR/issue context (skipped with a note when unavailable); build/test/lint gates use your verification skills when installed, or the project's documented commands inline. The consuming project's `CLAUDE.md` and rules win on integration convention (merge vs rebase, conflict style) — this skill reads them, never overrides them.

## What this skill does NOT do

- **Does not choose merge vs rebase** — that call belongs to the caller (`/pull-request` branch-freshness, project convention, or the user); this skill resolves whatever operation is already in progress.
- **Does not push or touch the PR lifecycle** — `/pull-request` owns that.
- **Does not make ordinary commits** — `/commit` owns the commit mechanic; this skill only continues an in-flight operation.
- **Does not bulk-resolve** — no `git checkout --ours/--theirs <dir>`, no rerere-driven auto-replay without review, no `-X ours/theirs` strategy options.
- **Does not bypass hooks or gates** — a hook or test failing after resolution is part of the conflict, not an obstacle to route around.
