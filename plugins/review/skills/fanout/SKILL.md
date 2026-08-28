---
description: "Fan out review across many finding-producing surfaces at once, this plugin's reviewer agents, the project's own per-concern review criteria docs, and orchestrator review plugins, then normalize the heterogeneous outputs into one severity-ranked, deduplicated report persisted to disk. Use when: 'fan out review', 'breadth review', 'run all reviewers', 'review from every angle', 'review this from all sides', or 'fix the review findings' (the fix action applies the merged set of persisted findings)."
argument-hint: "[mode] [--yes] (e.g., /review:fanout, /review:fanout run-everything, /review:fanout fix, /review:fanout fix --yes)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: review
  summary: Fan review out across every reviewer surface into one ranked report
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree status (empty = clean): !`{ git status --porcelain 2>/dev/null || echo "(git status unavailable)"; } | head -20`
Open PRs (match headRefName to current branch above; baseRefName is the PR's real base): !`gh pr list --json number,title,headRefName,baseRefName --limit 10 2>/dev/null || echo "unknown"`
Committed diff size vs default-base merge base (recompute against the PR's baseRefName when it differs): !`bash "${CLAUDE_PLUGIN_ROOT}/skills/fanout/scripts/diff-vs-base.sh" 2>/dev/null || echo "unavailable"`
Uncommitted diff size: !`git diff --shortstat HEAD 2>/dev/null || echo "unavailable"`

## Purpose

Breadth review. Where this plugin's `quality-gate` skill picks ONE lens per invocation, this skill fans out across MANY finding-producing surfaces at once, then normalizes their incomparable outputs into one severity-ranked report persisted to disk.

**The hard problem this skill owns:** the surfaces emit heterogeneous free-text on two independent axes (severity, confidence), and most populate only one. A 5-stage normalization pipeline (extraction → severity crosswalk → confidence enum → dedup → agreement/rank) is therefore unavoidable. [context/findings-normalization.md](context/findings-normalization.md).

**Review modes report; a separate `fix` action applies.** The `default` and `run-everything` modes fan out, normalize, and persist findings, mutating nothing but the findings file. The `fix` action consumes the persisted findings and is the only mode that touches the working tree.

## Shared inputs

- **Review diff base**, when an open PR exists for the branch, its `baseRefName` is the base: dispatched surfaces diff `git merge-base origin/<baseRefName> HEAD`. The pre-computed PR list above is capped; when the current branch is absent from it, run `gh pr list --head <current-branch> --json number,baseRefName` before concluding no PR exists. Otherwise `git merge-base origin/HEAD HEAD` (falling back to the remote's resolved default branch via `git ls-remote --symref`, then `origin/main`, then `HEAD`). Never a hardcoded `git diff HEAD`, which is empty on a clean committed branch.
- **Severity vocabulary**, the project's own review docs when present; else `${CLAUDE_PLUGIN_ROOT}/context/severity.md`.
- **Findings location**. Resolve through the plugin binding, [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md), which owns the resolution ladder, the `<branch-slug>` and timestamp spec, the non-interactive collapse, and the self-ignore guard. **Resolve the home; never assume its shape**, the ladder's rungs do not all compose a `reviews/<branch-slug>` segment, and the review modes' writer and the `fix` action's reader must land in the same directory or findings go silently unseen. Read the binding rather than working from the default's shape.

## Arguments

A positional mode token (Step 0) plus one flag:

| Flag | Default | Effect |
|---|---|---|
| `--yes` / `-y` | Off | Skip the pre-execution confirmation gate for the `fix` action. Required for headless runs. |

`--yes` applies ONLY to the tree-mutating `fix` action; it is inert for the report-only review modes, which mutate nothing to gate. Its role for `fix` is the explicit headless opt-in: in a non-interactive session, `fix` applies only under this flag, without it the fix action emits its classification plan and STOPs ([context/fix-pass-mode.md](context/fix-pass-mode.md) "Step 3: Plan + confirmation gate").

## Step 0: Mode

Parse the flag (`--yes` / `-y`) out of `$ARGUMENTS` first, then route on the remaining mode token:

- `run-everything` / `everything` / `all` → the full-breadth sweep. Read [context/run-everything-mode.md](context/run-everything-mode.md) and follow it end-to-end (availability gate → main-thread orchestrators → leaf fan-out → normalize → persist); skip Step 1 and rejoin at Step 2.
- `fix` / `fix-pass` (with or without `--yes`) → consume the merged set of unconsumed persisted findings for the current branch, every conforming producer's, not just the newest file, split by finding class, and apply. Read [context/fix-pass-mode.md](context/fix-pass-mode.md) and follow it end-to-end; skip Steps 1–3.
- empty → the default lifecycle-tiered review. Read [context/default-mode.md](context/default-mode.md) before dispatching.
- any other value → emit one diagnostic line `Unknown action '<value>'. Available: run-everything, fix. Defaulting to standard review.`, then run the default review, a typo is surfaced, never silently absorbed. The `--yes` / `-y` flag is not a mode value; stripping it before this match keeps `fix --yes` from tripping the diagnostic.

Both review modes share the roster ([context/leaf-roster.md](context/leaf-roster.md)) and the normalization pipeline. No duplicated roster or pipeline.

**Dispatch contract (both review modes):** every dispatched finding-producing leaf prompt carries
this coverage clause verbatim, appended to the leaf's own instructions. For slice leaves, appended
to the instantiated per-slice template (whose own coverage sentence is quality-gate's standalone
posture and states the same rule, not a competing contract): "Your goal at this stage is coverage:
it is better to surface a finding that later gets filtered out than to silently drop a real bug.
Report every issue you find, including ones you are uncertain about or consider low-severity. Do
not filter for importance or confidence at this stage, a separate normalization pass deduplicates
and ranks findings downstream. For each finding, include your confidence level (high / medium /
low) and an estimated severity." Current models follow a stated severity bar faithfully at the
finding stage, they investigate fully, then withhold findings judged below the bar, so a harness
with a downstream filter that does not say so converts investigations into silence (Sonnet 5
prompting guide, "Code review harnesses",
<https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5>;
the Opus 4.8 guide states the same). The clause restores recall without moving the precision work:
the pipeline's dedup and agreement/rank stages remain the filter.

## Pre-flight gate (both review modes)

**Ask-shape check first, before any diff resolution:** when the ask is a whole-repository security audit rather than a change review, emit the deep-scan escalation from [context/leaf-roster.md](context/leaf-roster.md) "Deep-scan escalation" and STOP. Regardless of diff state. A tracked diff or open PR does not convert that ask into a change review; a diff-scoped fan-out would answer a question the user did not ask.

Otherwise resolve the review diff base ("Shared inputs") and confirm it yields a non-empty diff BEFORE any surface is spawned:

- **Unresolvable base**, an open PR's `origin/<baseRefName>` fails `git rev-parse --verify` even after a fetch (do NOT silently substitute a different base. That reviews the wrong diff), or no ladder ref resolves at all → report which ref failed and STOP.
- **Nothing to review**. Truly clean tree, or untracked-only changes → emit the matching diagnostic (full logic: [context/default-mode.md](context/default-mode.md) "Clean-tree short-circuit + untracked-only diagnostic") and STOP; never stage files.

Either outcome spawns ZERO reviewers, a fan-out against an empty or wrong change set burns the whole roster to produce noise. The `fix` action is exempt: it consumes persisted findings and spawns no reviewers.

## Step 1: Detect lifecycle tier (default mode)

Read the pre-computed facts (the pre-flight gate above has already screened out unresolvable and empty change sets). Classify the change into a tier (thresholds + the judgment layer in [context/default-mode.md](context/default-mode.md)):

| Tier | Trigger | Surfaces dispatched |
|---|---|---|
| **small** | <50 changed lines | `code-reviewer` (always) + `security-reviewer` when security-sensitive paths touched |
| **medium** | 50–300 changed lines | small set + orchestrator plugin(s) + `architecture-guardian` when structural paths touched |
| **large** | >300 lines OR cross-cutting | medium set + the project's ownerless review-criteria docs as slice-subagents |

**Tier transparency (mandatory):** before dispatch emit ONE line. `Tier: <small|medium|large>; surfaces run: [...]; surfaces SKIPPED at this tier: [...]`. A skip is a fidelity choice; naming it makes it overridable.

## Step 2: Normalize

Run the 5-stage pipeline in [context/findings-normalization.md](context/findings-normalization.md) over every surface's raw output.

## Step 3: Persist findings

Run the self-ignore guard ("Shared inputs"), then write the ranked report into the resolved findings location as `<UTC-timestamp>-<topic>.md`, with `<topic>` sanitized to `[a-z0-9._-]`. The timestamp format is the binding's ("Shared inputs"), not restated here. Relativize machine paths BEFORE writing. Findings cite `file:line` repo-relative only. File-name collision rule and file shape contract: [`${CLAUDE_PLUGIN_ROOT}/reference/findings-file-shape.md`](../../reference/findings-file-shape.md) "Findings-writer contract" and "Findings-file shape".

## Orchestrator plugins

Three optional orchestrator plugins add adversarial breadth. Two same-vendor Claude plugins from the `claude-plugins-official` marketplace, plus the OpenAI Codex plugin (`codex@openai-codex`) as a different-model surface. All run on the MAIN THREAD: they fan out their own agents, and the main thread is the one context whose `Agent` tool the nesting-depth limit never disables. A subagent CAN nest, but only inside a depth budget that is settings-configurable (`CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`, where `1` turns nesting off) and so outside this skill's control; at the limit the tool is withheld, or in a fork kept but erroring ([sub-agents](https://code.claude.com/docs/en/sub-agents#let-subagents-spawn-their-own-subagents)). Each is a graceful enhancement, not a hard dependency:

- **`pr-review-toolkit`**. `/pr-review-toolkit:review-pr`: aspect-scoped agent fan-out. Absent → this plugin's leaf agents cover most of the same dimensions; note that orchestrator breadth was skipped.
- **`code-review`**. `/code-review:code-review`: parallel reviewers + confidence scorer for an existing PR. Distinct from the bundled `/code-review` command and the managed service covered under "Boundary" below, despite the shared name. **Applicability gate:** a PR is its only target, so it is dispatchable only when the branch has an open PR. On a branch with none, the ordinary local-branch review, skip it and name the skip in `## Surfaces` rather than dispatching a surface that cannot produce findings. **PR-mutation gate:** where it does apply, its final step posts the surviving findings back as a PR comment, there is no mode that returns them to the session instead, so every invocation violates the review modes' report-only contract. Dispatch it only on explicit user opt-in ("post the review comment"), otherwise skip it and name the skip. **Its raw text comes from the PR, not the dispatch:** having posted rather than returned its findings, an opted-in run is followed by fetching that comment back (`context/findings-normalization.md`) so the normalization step has an input at all. That fetch identifies the comment by which IDs are new, so the snapshot has to be taken HERE. Step 2 opens `context/findings-normalization.md` only after this step has already dispatched, too late to observe a pre-dispatch state. Before dispatching, run `gh pr view <n> --json comments --jq '[.comments[].id]'` and record the printed array verbatim, then carry that literal into the retrieval. Carry it as a value, not a shell variable: the retrieval runs in a later invocation with a fresh shell. Absent → note the skip; a repository's own CI review bot (when present) still provides PR coverage.
- **`codex`** (OpenAI Codex). `/codex:review`: read-only cross-vendor review, so it satisfies the review modes' report-only contract with no PR-mutation gate; `/codex:adversarial-review`: red-teams the diff, fitting the intentional adversarial-breadth intent. The first surface backed by a **different model**. Its blind spots are uncorrelated with the same-vendor leaf agents and Claude orchestrators, so a finding only Codex raises is signal the rest structurally cannot see. Invoke it with `--wait` so the review runs in the foreground and returns findings in the same turn (its default prompts and may run in a background task the synchronous normalization step would miss), and pass `--base <review-base>` carrying this skill's resolved review diff base ("Shared inputs") so Codex diffs the same change set as every other dispatched surface, without it Codex auto-picks the working tree or default branch. Absent → note the skip; the same-vendor surfaces still cover most dimensions.

## Boundary, the bundled command and the managed service

Two further Claude Code surfaces overlap this skill's job on an open PR: the **bundled `/code-review` command** and the **managed Code Review GitHub App service**. Both ship with Claude Code itself rather than as marketplace plugins, which is what separates them from the `code-review` orchestrator plugin dispatched above. [`${CLAUDE_PLUGIN_ROOT}/skills/quality-gate/context/pr.md`](../quality-gate/context/pr.md)'s "Boundary" section describes all three surfaces and what each one mutates; that description is not repeated here. What is specific to this skill:

Neither is dispatched as a normalized fan-out surface and [context/findings-normalization.md](context/findings-normalization.md) carries no parse contract for either, but for different reasons. The managed service posts its findings to the PR instead of returning them to this skill. Bare `/code-review` **is** report-only (findings arrive in the conversation; only `--fix` and `--comment` mutate); it is left out because it is itself a multi-agent review of the same diff, overlapping this skill's own leaf reviewers, and its finding output has no documented schema to write a parse contract against. Run it directly when you want that second orchestration. This skill names the overlap in `## Surfaces` rather than dispatching it. **PR-mutation gate:** `/code-review --comment` and triggering the managed service both post to the PR, which violates the review modes' report-only contract; when the branch has an open PR, invoke either only on explicit user opt-in ("post the review comment"), otherwise note the overlap in `## Surfaces` without invoking it. Not enabled/available → note the skip; a repository's own CI review bot (e.g. the managed service, when enabled) still provides PR coverage independently.

## What this skill does NOT do

- **Review modes do not apply fixes**. Mutation happens only through the explicit `fix` action; it never auto-runs after a review.
- **Does not duplicate `quality-gate`**. That picks ONE lens; this fans out across many.
- **Does not run builds or tests**. Use the project's build/test tooling (or this plugin's `ecosystem-specialist` agent) separately.
