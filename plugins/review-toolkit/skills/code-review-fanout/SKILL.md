---
name: code-review-fanout
description: "Fan out review across many finding-producing surfaces at once — this plugin's reviewer agents, the project's own per-concern review criteria docs, and orchestrator review plugins — then normalize the heterogeneous outputs into one severity-ranked, deduplicated report persisted to disk. Use for 'fan out review', 'breadth review', 'run all reviewers', 'review from every angle', or 'fix the review findings' (the fix action applies a persisted findings file)."
argument-hint: "[mode] (e.g., /review-toolkit:code-review-fanout, /review-toolkit:code-review-fanout run-everything, /review-toolkit:code-review-fanout fix)"
user-invocable: true
disable-model-invocation: false
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo "unavailable"`
Open PRs (match headRefName to current branch above; baseRefName is the PR's real base): !`gh pr list --json number,title,headRefName,baseRefName --limit 10 2>/dev/null || echo "unknown"`
Committed diff size vs default-base merge base (recompute against the PR's baseRefName when it differs): !`git diff --shortstat origin/HEAD...HEAD 2>/dev/null || git diff --shortstat origin/main...HEAD 2>/dev/null || echo "unavailable"`
Uncommitted diff size: !`git diff --shortstat HEAD 2>/dev/null || echo "unavailable"`

## Purpose

Breadth review. Where this plugin's `quality-gate` skill picks ONE lens per invocation, this skill fans out across MANY finding-producing surfaces at once, then normalizes their incomparable outputs into one severity-ranked report persisted to disk.

**The hard problem this skill owns:** the surfaces emit heterogeneous free-text on two independent axes (severity, confidence), and most populate only one. A 5-stage normalization pipeline (extraction → severity crosswalk → confidence enum → dedup → agreement/rank) is therefore unavoidable — [context/findings-normalization.md](context/findings-normalization.md).

**Review modes report; a separate `fix` action applies.** The `default` and `run-everything` modes fan out, normalize, and persist findings, mutating nothing but the findings file. The `fix` action consumes the persisted findings and is the only mode that touches the working tree.

## Shared inputs

- **Review diff base** — when an open PR exists for the branch, its `baseRefName` is the base: dispatched surfaces diff `git merge-base origin/<baseRefName> HEAD`. The pre-computed PR list above is capped; when the current branch is absent from it, run `gh pr list --head <current-branch> --json number,baseRefName` before concluding no PR exists. Otherwise `git merge-base origin/HEAD HEAD` (falling back to `origin/main`, then `HEAD`). Never a hardcoded `git diff HEAD`, which is empty on a clean committed branch.
- **Severity vocabulary** — the project's own review docs when present; else `${CLAUDE_PLUGIN_ROOT}/context/severity.md`.
- **Findings location** — when the project's conventions define a review-artifacts location (check its `CLAUDE.md` / project rules), use it; otherwise `.claude/review/<branch-slug>/` at the project root, where `<branch-slug>` is the branch name lowercased with non-`[a-z0-9._-]` characters replaced by `-`.

## Step 0: Mode

Route on `$ARGUMENTS`:

- `run-everything` / `everything` / `all` → the full-breadth sweep. Read [context/run-everything-mode.md](context/run-everything-mode.md) and follow it end-to-end (availability gate → main-thread orchestrators → leaf fan-out → normalize → persist); skip Step 1 and rejoin at Step 2.
- `fix` / `fix-pass` → consume the newest persisted findings file for the current branch, split by finding class, and apply. Read [context/fix-pass-mode.md](context/fix-pass-mode.md) and follow it end-to-end; skip Steps 1–3.
- empty → the default lifecycle-tiered review. Read [context/default-mode.md](context/default-mode.md) before dispatching.
- any other value → emit one diagnostic line `Unknown action '<value>'. Available: run-everything, fix. Defaulting to standard review.`, then run the default review — a typo is surfaced, never silently absorbed.

Both review modes share the roster ([context/leaf-roster.md](context/leaf-roster.md)) and the normalization pipeline — no duplicated roster or pipeline.

## Step 1: Detect lifecycle tier (default mode)

Read the pre-computed facts. **Dispatch gate first:** (1) truly clean tree + no open PR → "no changes to review", spawn nothing; (2) untracked-only changes → report ``only untracked files; `git add` them to include in review`` and spawn nothing (do NOT stage them); (3) otherwise proceed. Full logic: [context/default-mode.md](context/default-mode.md).

Classify the change into a tier (thresholds + the judgment layer in the context file):

| Tier | Trigger | Surfaces dispatched |
|---|---|---|
| **small** | <50 changed lines | `code-reviewer` (always) + `security-reviewer` when security-sensitive paths touched |
| **medium** | 50–300 changed lines | small set + orchestrator plugin(s) + `architecture-guardian` when structural paths touched |
| **large** | >300 lines OR cross-cutting | medium set + the project's ownerless review-criteria docs as slice-subagents |

**Tier transparency (mandatory):** before dispatch emit ONE line — `Tier: <small|medium|large>; surfaces run: [...]; surfaces SKIPPED at this tier: [...]`. A skip is a fidelity choice; naming it makes it overridable.

## Step 2: Normalize

Run the 5-stage pipeline in [context/findings-normalization.md](context/findings-normalization.md) over every surface's raw output.

## Step 3: Persist findings

Write the ranked report to `<findings-location>/<UTC-timestamp>-<topic>.md` (`date -u +%Y%m%dT%H%M%SZ`, colon-free; `<topic>` sanitized to `[a-z0-9._-]`). Relativize machine paths BEFORE writing — findings cite `file:line` repo-relative only. File shape contract: [context/default-mode.md](context/default-mode.md) "Findings-file shape".

## Orchestrator plugins

Three optional orchestrator plugins add adversarial breadth — two same-vendor Claude plugins from the `claude-plugins-official` marketplace, plus the OpenAI Codex plugin (`codex@openai-codex`) as a different-model surface. All run on the MAIN THREAD (they fan out their own agents; a subagent cannot dependably do that). Each is a graceful enhancement, not a hard dependency:

- **`pr-review-toolkit`** — `/pr-review-toolkit:review-pr`: aspect-scoped agent fan-out. Absent → this plugin's leaf agents cover most of the same dimensions; note that orchestrator breadth was skipped.
- **`code-review`** — `/code-review:code-review`: parallel reviewers + confidence scorer for an existing PR. **PR-mutation gate:** its PR mode posts findings as a PR comment, which violates the review modes' report-only contract; when the branch has an open PR, dispatch it only on explicit user opt-in ("post the review comment"), otherwise skip it and name the skip in `## Surfaces`. Absent → note the skip; a repository's own CI review bot (when present) still provides PR coverage.
- **`codex`** (OpenAI Codex) — `/codex:review`: read-only cross-vendor review, so it satisfies the review modes' report-only contract with no PR-mutation gate; `/codex:adversarial-review`: red-teams the diff, fitting the intentional adversarial-breadth intent. The first surface backed by a **different model** — its blind spots are uncorrelated with the same-vendor leaf agents and Claude orchestrators, so a finding only Codex raises is signal the rest structurally cannot see. Invoke it with `--wait` so the review runs in the foreground and returns findings in the same turn (its default prompts and may run in a background task the synchronous normalization step would miss), and pass `--base <review-base>` carrying this skill's resolved review diff base ("Shared inputs") so Codex diffs the same change set as every other dispatched surface — without it Codex auto-picks the working tree or default branch. Absent → note the skip; the same-vendor surfaces still cover most dimensions.

## What this skill does NOT do

- **Review modes do not apply fixes** — mutation happens only through the explicit `fix` action; it never auto-runs after a review.
- **Does not duplicate `quality-gate`** — that picks ONE lens; this fans out across many.
- **Does not run builds or tests** — use the project's build/test tooling (or this plugin's `ecosystem-specialist` agent) separately.
