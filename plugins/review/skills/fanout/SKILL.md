---
description: "Breadth review: fans a change out to many reviewers at once (this plugin's reviewer agents, the project's per-concern criteria docs, orchestrator review plugins) and merges their findings into one deduplicated, severity-ranked report on disk. Use when asked for a breadth review of a change (every reviewer at once, every angle or side, one combined ranked report), or to 'fix the review findings' (the fix action applies the merged set of persisted findings)."
argument-hint: "[run-everything|fix] [--yes]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Workflow(review:fanout-sweep)", "Bash(node \"${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/setup-apply.mjs\" --check:*)", "Bash(node ${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/setup-apply.mjs --check:*)"]
shell: bash
metadata:
  workflow-stage: review
  summary: Fan review out across every reviewer surface into one ranked report
---

**Arguments.** `[run-everything|fix] [--yes]`. e.g., /review:fanout, /review:fanout run-everything, /review:fanout fix, /review:fanout fix --yes

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single invocation:

- Current branch, `git branch --show-current`
- Working tree status (empty = clean), `git status --porcelain | head -20`
- Uncommitted diff size, `git diff --shortstat HEAD`

Keep the pipe in the command; it is the bound. Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as separate body Bash calls, not pre-compute lines. Pointer: the [gather-block convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/gather-block/README.md#the-pre-compute-block-runs-as-one-shell-invocation), "The pre-compute block runs as one shell invocation", which holds the dated record and its recheck trigger.

## Pre-computed context

Open PRs (match headRefName to current branch above; baseRefName is the PR's real base): !`gh pr list --json number,title,headRefName,baseRefName --limit 10 2>/dev/null || echo "unknown"`
Committed diff size vs default-base merge base (recompute against the PR's baseRefName when it differs): !`bash "${CLAUDE_PLUGIN_ROOT}/skills/fanout/scripts/diff-vs-base.sh" 2>/dev/null || echo "unavailable"`

## Purpose

Breadth review: fan out across MANY finding-producing surfaces at once (`quality-gate` picks ONE lens), then normalize their heterogeneous free-text, which carries two independent axes (severity, confidence) with most surfaces filling only one, through a 5-stage pipeline (extraction → severity crosswalk → confidence enum → dedup → agreement/rank, [findings-normalization.md](../../reference/findings-normalization.md)) into one severity-ranked report persisted to disk.

**Review modes report; a separate `fix` action applies.** The `default` and `run-everything` modes fan out, normalize, and persist findings, mutating nothing but the findings file. The `fix` action consumes the persisted findings and is the only mode that touches the working tree.

**Stub-scaffold phase.** When a stub-scaffold phase (the planning plugin's `scaffold_stubs` setting) is committed, fanout may review that diff before the bodies are filled in, so file layout and signatures get a review while they are still cheap to change. It runs as an ordinary review of the committed diff, with no argument, setting or step of its own.

## Shared inputs

- **Review diff base**: [change-set.md](../../reference/change-set.md) "Review diff base". The pre-computed PR list above is the capped list that section names.
- **Severity vocabulary**: [change-set.md](../../reference/change-set.md) "Severity vocabulary".
- **Findings location**: [change-set.md](../../reference/change-set.md) "Findings location". The review modes' writer and the `fix` action's reader both resolve it there.

## Arguments

A positional mode token (Step 0) plus one flag:

| Flag | Default | Effect |
|---|---|---|
| `--yes` / `-y` | Off | Skip the pre-execution confirmation gate for the `fix` action. Required for headless runs. |

`--yes` applies ONLY to the tree-mutating `fix` action; it is inert for the report-only review modes, which mutate nothing to gate. Its role for `fix` is the explicit headless opt-in: in a non-interactive session, `fix` applies only under this flag, without it the fix action emits its classification plan and STOPs ([context/fix-pass-mode.md](context/fix-pass-mode.md) "Step 3: Plan + confirmation gate").

**`fanout_diversity` (run-everything and its fallback only).** It sets how the leaf fan-out
spreads: `lens` runs one reviewer agent per concern, `model` sends one review prompt to each
distinct fan-out model tier, and `codex` runs the `lens` roster with the Codex reviewer as the
model-diversity panel in place of those tiers
([context/run-everything-mode.md](context/run-everything-mode.md) steps 3 and 5). The default
mode does not read it. Resolve it before step 5, lowest layer first: the
default `lens`; the user option `${user_config.fanout_diversity}` (a literal, unexpanded
placeholder means unset); the `PASS fanout_diversity:` line of
`node "${CLAUDE_PLUGIN_ROOT}/skills/setup/scripts/setup-apply.mjs" --check`, run from the project
root, for the repository's `docs/conventions/review.yaml` (`(unset)` means no value there). When
the reviewed change set edits `docs/conventions/review.yaml`, skip that layer and say so, so the
change cannot pick how it is reviewed; without node, skip it and say so. Invalid values, WARN
lines and when the repository file is read at all: "Resolution" and "Root rule" in
[`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](../../reference/config.md). Report one line,
`fanout_diversity: <value> (<layer>)`, for example `fanout_diversity: lens (default)`.

**`fanout_act_on_cap` (both review modes).** How many rows under each `## By axis` heading
Step 2 marks act on. Resolve it before Step 2 from the same layers and with the same skip rules as
`fanout_diversity`: the default `2`; the user option `${user_config.fanout_act_on_cap}` (a
literal, unexpanded placeholder means unset; a value that is not a whole number of at least 1 is
invalid: name it and drop that layer); the `PASS fanout_act_on_cap:` line of the `--check` run
above, which the default mode runs for this key alone. Report one line, `fanout_act_on_cap: <value> (<layer>)`, for example
`fanout_act_on_cap: 2 (default)`.

## Step 0: Mode

Parse the flag (`--yes` / `-y`) out of `$ARGUMENTS` first, then route on the remaining mode token:

- `run-everything` / `everything` / `all` → the full-breadth sweep. Read [context/run-everything-mode.md](context/run-everything-mode.md) and follow it end-to-end (availability gate → main-thread orchestrators → leaf fan-out → normalize → persist); skip Step 1 and rejoin at Step 2. Its leaf fan-out launches the saved `review:fanout-sweep` workflow.
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
low) and an estimated severity. You are done when every changed file has been reviewed for your
concern; if part of the change set cannot be reviewed, name that part and return what you have."
The clause restores recall without moving the precision work: the pipeline's dedup and
agreement/rank stages remain the filter. Pointer: when judging whether current models still need
it, fetch the code-review guidance in [prompting Claude Opus 5: capability improvements](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5#capability-improvements)
live. Recheck trigger: a current-model prompting guide gains a code-review
section, or one says a finder no longer under-reports when given a severity bar.

**Intent paragraph.** Every surface this skill dispatches itself (the default mode's leaves, and
the orchestrator plugins in either mode) gets the same short paragraph in its prompt, labeled as
the author's account of what the change is for. Reviewers test the change against that account and
report each place the two disagree; the paragraph is a claim under test, never proof that the
change works. Write it once, in your own words, before the first dispatch. Its sources are the PR
title and body if a PR exists, the commit subjects on the branch, and the user's request. If none
of them states a purpose, an interactive session asks the user once; any other session writes
`Intent: not stated` and reviews without it.

**Finding class.** Every per-concern brief this skill writes (criteria slices and reviewer briefs)
names the class of finding it wants (the leaf's concern, for example correctness) and what to leave
out (for example style); the coverage clause applies inside that class. The `model` diversity
hunters are the deliberate exception: they sweep every concern. Pointer:
[best practices: review against your spec](https://code.claude.com/docs/en/best-practices#review-against-your-spec).

## Pre-flight gate (both review modes)

Run the gate in [change-set.md](../../reference/change-set.md) "Pre-flight gate" (the ask-shape check, then the unresolvable-base and nothing-to-review stops) BEFORE any surface is spawned. The `fix` action is exempt: it consumes persisted findings and spawns no reviewers.

**Pilot a wide fan-out.** Before dispatching more than about 4 surfaces, in either review mode, dispatch one surface alone, wait for its return, and confirm plan usage remains (the return carries no usage-limit error, and any usage reading the session has shows room for the rest) before dispatching the others. In default mode the pilot is the first of the per-surface Agent-tool calls; in run-everything mode it is one slice run before the workflow launch ([context/run-everything-mode.md](context/run-everything-mode.md) step 5). What a session, its agents and a workflow run do at a usage limit is upstream's rule:

- **Pointer**: Agent-tool surfaces, [Wait for a usage limit to reset](https://code.claude.com/docs/en/interactive-mode#wait-for-a-usage-limit-to-reset); workflow leaves, [When a run hits your usage limit](https://code.claude.com/docs/en/workflows#when-a-run-hits-your-usage-limit)

## Step 1: Detect lifecycle tier (default mode)

Read the pre-computed facts (the pre-flight gate above has already screened out unresolvable and empty change sets). Classify the change into a tier (thresholds + the judgment layer in [context/default-mode.md](context/default-mode.md)):

| Tier | Trigger | Surfaces dispatched |
|---|---|---|
| **small** | <50 changed lines | `code-reviewer` (always) + `security-reviewer` when security-sensitive paths touched |
| **medium** | 50–300 changed lines | small set + orchestrator plugin(s) + `architecture-guardian` when structural paths touched |
| **large** | >300 lines OR cross-cutting | medium set + the project's ownerless review-criteria docs as slice-subagents |

**Tier transparency (mandatory):** before dispatch emit ONE line. `Tier: <small|medium|large>; surfaces run: [...]; surfaces SKIPPED at this tier: [...]`. A skip is a fidelity choice; naming it makes it overridable.

## Step 2: Normalize

Run the 5-stage pipeline in [findings-normalization.md](../../reference/findings-normalization.md) over every surface's raw output. Before a CRITICAL finding enters the report, read its cited `file:line` in the diff; a finding the code does not bear out drops to `low` confidence with that note, never silently removed.

**Axis.** Then give each finding one axis, `spec` or `standards`, by the rule in
[findings-normalization.md](../../reference/findings-normalization.md) "Axis assignment": `spec`
when it says the change does not do, or only partly does, what the intent paragraph says it is for.
The report lists the findings again under `## By axis`, after `## By dimension`, with `### Spec`
before `### Standards` (shape: [`findings-file-shape.md`](../../reference/findings-file-shape.md)
"Findings-file shape"). Fanout reviews the code against its stated purpose; it does not review a
spec or plan document.

**Act on.** Under each of `### Spec` and `### Standards` on its own, the first
`fanout_act_on_cap` rows in merged-rank order get `yes` in a last `Act on` cell and every later row
gets `no`. The count restarts at the second heading, so with a cap of 2 the first two Standards
rows read `yes` whatever their merged rank. A row listed under `## Dismissed` reads `no` and is
not counted. Every row stays in the report.

**Dismissed.** The report gains a `## Dismissed` section after `## By axis`: one line per
finding this step demoted, giving its rank, its location and the reason in one sentence taken from
what the cited line shows. The finding itself stays in `## Findings` at its demoted confidence. The
section lists demotions only; no finding leaves the report, so nothing is listed as dropped. With
no demotion, the section reads `none`. The fix action does not parse it.

When a surface returns after findings were presented for a decision and before the user answers,
the next message that presents findings ends with every open finding in full:
`docs/contracts/async-round-presentation/README.md` in the marketplace.

## Step 3: Persist findings

Run the self-ignore guard ("Shared inputs"), then write the ranked report into the resolved findings location as `<UTC-timestamp>-<topic>.md`, with `<topic>` sanitized to `[a-z0-9._-]`. The timestamp format is in "Shared inputs". Relativize machine paths BEFORE writing. Findings cite `file:line` repo-relative only. File-name collision rule and file shape contract: [`${CLAUDE_PLUGIN_ROOT}/reference/findings-file-shape.md`](../../reference/findings-file-shape.md) "Findings-writer contract" and "Findings-file shape".

## Orchestrator plugins

Three optional orchestrator plugins add adversarial breadth. Two same-vendor Claude plugins from the `claude-plugins-official` marketplace, plus the OpenAI Codex plugin (`codex@openai-codex`) as a different-model surface. All run on the MAIN THREAD: they fan out their own agents, and how deep a subagent may nest is a user setting outside this skill's control. Pointer: for the nesting default, how to change it, and what happens at the limit, fetch [sub-agents: let subagents spawn their own subagents](https://code.claude.com/docs/en/sub-agents#let-subagents-spawn-their-own-subagents) live. Recheck trigger: the main conversation gains a nesting limit, or nesting depth stops being user-configurable. Each is a graceful enhancement, not a hard dependency:

- **`pr-review-toolkit`**. `/pr-review-toolkit:review-pr`: aspect-scoped agent fan-out. Absent → this plugin's leaf agents cover most of the same dimensions; note that orchestrator breadth was skipped.
- **`code-review`**. `/code-review:code-review`: parallel reviewers plus validation subagents, for an existing PR. Distinct from the bundled `/code-review` command and the managed service covered under "Boundary" below, despite the shared name. **Applicability gate:** a PR is its only target, so it is dispatchable only when the branch has an open PR. On a branch with none, the ordinary local-branch review, skip it and name the skip in `## Surfaces` rather than dispatching a surface that cannot produce findings. **PR-mutation gate:** where it does apply, its `--comment` form posts the findings to the PR, which violates the review modes' report-only contract. Its default run has no parse contract here, so this skill never dispatches it as a surface. Pointer: for where the default run's findings go, fetch [code-review plugin: Commands](https://github.com/anthropics/claude-plugins-official/tree/main/plugins/code-review#commands) and the command file, [`commands/code-review.md`](https://github.com/anthropics/claude-plugins-official/blob/main/plugins/code-review/commands/code-review.md), live. Recheck trigger: the command gains a documented output schema a parse contract could rest on. Dispatch it only on explicit user opt-in ("post the review comment"), and then pass `--comment`, since the fetch-back below needs a posted comment; otherwise skip it and name the skip. **Its raw text comes from the PR, not the dispatch:** having posted rather than returned its findings, an opted-in run is followed by fetching that comment back ([findings-normalization.md](../../reference/findings-normalization.md)) so the normalization step has an input at all. That fetch identifies the comment by which IDs are new, so the snapshot has to be taken HERE. Step 2 opens findings-normalization.md only after this step has already dispatched, too late to observe a pre-dispatch state. Before dispatching, run `gh pr view <n> --json comments --jq '[.comments[].id]'` and record the printed array verbatim, then carry that literal into the retrieval. Carry it as a value, not a shell variable: the retrieval runs in a later invocation with a fresh shell. Absent → note the skip; a repository's own CI review bot (when present) still provides PR coverage.
- **`codex`** (OpenAI Codex). Its review is read-only cross-vendor review, so it satisfies the review modes' report-only contract with no PR-mutation gate; its adversarial review red-teams the diff, fitting the intentional adversarial-breadth intent. The first surface backed by a **different model**. Its blind spots are uncorrelated with the same-vendor leaf agents and Claude orchestrators, so a finding only Codex raises is signal the rest structurally cannot see. Never invoke the plugin's `/codex:*` commands; run the script instead. Whether the model may invoke those commands is upstream's choice: read it live at [`plugins/codex/commands/review.md`](https://github.com/openai/codex-plugin-cc/blob/main/plugins/codex/commands/review.md) in `openai/codex-plugin-cc`. Run, from the repository root, `bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-review.sh" --base <review-base>` (add `--adversarial` for the adversarial review). With `--base`, Codex reviews committed history from the base only: on a branch that also carries uncommitted tracked edits, the other surfaces cover those edits and Codex does not, so name that gap in `## Surfaces`. It finds the plugin through `claude plugin list --json` and runs the plugin's own companion runtime, `codex-companion.mjs`, in the foreground, so findings return in the same turn. `--base` carries this skill's resolved review diff base ("Shared inputs"), so Codex diffs the same change set as every other dispatched surface; without it Codex auto-picks the working tree or default branch. A review can run for minutes, so give the Bash call the tool's longest timeout. The script's first line is the surface's status. `codex: ran` puts the lines after it into normalization as Codex's raw output. `codex: skipped (<reason>)` means Codex never started (plugin, CLI or login absent): never list it under `Ran`; end the `## Surfaces` line with `codex: skipped (<reason>)`. `codex: failed (<reason>)` lists it under `Returned no result` with the reason, and so does a call that times out or prints no status line, as `codex (timed out)`. When the Bash call itself is denied, end the line with `codex: skipped (permission denied)`. Skipped → the same-vendor surfaces still cover most dimensions.

## Boundary, the bundled command and the managed service

Two further Claude Code surfaces overlap this skill's job on an open PR: the **bundled `/code-review` command** and the **managed Code Review GitHub App service**. Neither is a marketplace plugin, which is what separates them from the `code-review` orchestrator plugin dispatched above. [`${CLAUDE_PLUGIN_ROOT}/skills/quality-gate/context/pr.md`](../quality-gate/context/pr.md)'s "Boundary" section describes all three surfaces and what each one mutates; that description is not repeated here. What is specific to this skill:

Neither is dispatched as a normalized fan-out surface and [findings-normalization.md](../../reference/findings-normalization.md) carries no parse contract for either, but for different reasons. The managed service posts its findings to the PR instead of returning them to this skill. A bare `/code-review` run is left out because it is a second review of the same diff, overlapping this skill's own leaf reviewers, and this skill has no parse contract for its output. Run it directly when you want that second review. Pointer: for what a bare run writes and where its findings appear, fetch [code-review: what the review reads and edits](https://code.claude.com/docs/en/code-review-local#what-the-review-reads-and-edits) and [code-review: how findings are reported](https://code.claude.com/docs/en/code-review-local#how-findings-are-reported) live. Recheck trigger: a bare run starts editing or posting, or its findings gain a documented schema a parse contract could rest on. This skill names the overlap in `## Surfaces` rather than dispatching it. **PR-mutation gate:** `/code-review --comment` and triggering the managed service both post to the PR, which violates the review modes' report-only contract; when the branch has an open PR, invoke either only on explicit user opt-in ("post the review comment"), otherwise note the overlap in `## Surfaces` without invoking it. Not enabled/available → note the skip; a repository's own CI review bot (e.g. the managed service, when enabled) still provides PR coverage independently.

## Spoke paths

The `context/` files write the plugin root as `<plugin-root>`, which is `${CLAUDE_PLUGIN_ROOT}`. Substitute it before running a command or writing it into a brief: a spoke arrives as plain bytes, so a `${…}` token in it would reach Bash unexpanded. Pointer: <https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves>.

## Next

- Findings to apply: /review:fanout fix.
- No blocking findings: /verification:confirm.
- A configured panel chosen for this change, with fix rounds: /review:council.

## What this skill does NOT do

- **Review modes do not apply fixes**. Mutation happens only through the explicit `fix` action; it never auto-runs after a review.
- **Does not duplicate `quality-gate`**. That picks ONE lens; this fans out across many.
- **Does not run builds or tests**. Use the project's build/test tooling (or this plugin's `ecosystem-specialist` agent) separately.
