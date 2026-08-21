---
description: "Explore the local codebase before making changes — read code, trace dependencies, scan git history, discover tests, and audit build and tool configuration, persisting an EXPLORE.md index plus sidecars. Dispatches a fresh-context subagent by default so the file reads stay out of the main conversation, with a documented inline escape hatch. Use when: 'explore the codebase', 'what exists for X' investigation, 'how does this work', 'where is X implemented', 'trace the dependencies', 'what tests cover this', or as step 1 before any code change. Skip when: the question is why a thing was built the way it was rather than what it is or how it works — reconstructing the reasoning behind a past decision from review discussion, tickets, and design documents is '/discovery:trace-intent'; this skill's git mode reports what changed and by whom, not the intent behind it."
argument-hint: "[scope] (e.g., /discovery:explore payments module dependencies, /discovery:explore tests, /discovery:explore git, /discovery:explore config)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: explore
  summary: Explore code, history, tests, and config before changing anything
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo "clean"`
Project root: !`git rev-parse --show-toplevel 2>/dev/null || echo "unknown"`

These values orient this session only. The project root is an absolute machine path — use it to resolve files while working, but never echo it into `EXPLORE.md`; the handoff artifact records relative paths (see the outcome gate below).

## Routing — dispatch by default

**From the main conversation, this skill dispatches the `discovery:explorer` subagent.** Exploration reads many files; keeping that out of the orchestrator's context window is the point. The agent loads the project's path-scoped rules, runs the six dimensions, writes the artifact set, and returns a bounded summary plus a file pointer — not the reads. The parent resolves the **pre-dispatch envelope** first — six fields (scope, reason, memory-slice path, memory root, budget, capability flags), written into the dispatch prompt as the labelled template in [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md), not as prose the agent has to parse — and owns the **post-dispatch boundary** after: re-surfacing `open_questions` to the user, dispatching the sibling verifier, and **writing its verdict back into `EXPLORE.md`** — the explorer always returns `verification: pending` because it may not grade its own work, so an artifact left saying `pending` after the parent verified it cannot be told apart from one whose verifier never ran, and this artifact is the whole handoff a fresh session resumes from.

**Run inline instead when any of these holds** — inline runs the identical workflow, and the escape hatch relaxes nothing:

- **Tight turn-by-turn iteration** — ≤~5 known files, findings feeding a same-session edit, and you will redirect as results land.
- **Cost** — a dispatched run pays the full six dimensions every time; a single-file question does not need an envelope.
- **The invoking context is already a subagent** — dispatch-by-default is scoped to the main-conversation boundary. Hoisting, not nesting: the outer dispatch already supplied the fresh context, so a second hop only spends the inner agent's own window.

**When selecting the dispatched route:** probe `check-dispatch-artifact.sh --help` before dispatching; a denied or errored probe **halts**. An un-runnable post-dispatch gate is not a reason to take the inline escape hatch *in order to dodge the gate*. A legitimate inline run (tight iteration, cost, already-a-subagent) does not owe that script — it has no script verdict to self-grade — so do not apply this precondition to the inline path. Invocation forms: [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md).

**One named alternative:** the **built-in Explore subagent**, for raw "where is X / how does Y work" search. Fast, read-only, context-isolated. It skips project memory (convention-blind) and neither runs this 6-dimension workflow nor writes `EXPLORE.md` — pass key constraints in the prompt when conventions matter, and expect to write the artifact yourself. Scale 1→N by dispatching more, each owning a disjoint area.

**Preload-liveness sentinel.** A dispatched agent receives this body through its `skills:` preload, and a preload that fails to resolve is skipped **silently** — logged to the debug log and nowhere else. A dispatched run therefore echoes this token verbatim as `preload_token` in its return payload:

```text
discovery-explore-preload-8e2b7d
```

A missing or mismatched token is a **hard failure: the parent discards the run**, never downgrades or accepts the artifact. Without it, a preload miss produces an undisciplined run that still writes an artifact — indistinguishable from success at every other seam.

**Post-dispatch acceptance gate — parent-side, before the payload is believed.** `status: complete` is the agent's claim about its own run, and a claim is not evidence. Grade the run **off disk**, against the memory-slice path from the parent's own pre-dispatch envelope — **carry that path across the dispatch, because it is this gate's input** — and never a path read out of the payload, because the failure this gate exists to catch is a payload that comes back carrying no pointer at all. In order:

**Pre-dispatch:** create the memory slice and touch `<that slice>/.explore-dispatch` as the gate's freshness baseline, then hand that file to the gate as `--newer-than`. Without it a slice that already holds an earlier run's artifact set passes every on-disk check even when this dispatch wrote nothing at all. **Both shell forms of that one command are in [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md) ("The pre-dispatch baseline") — copy the one matching this session's shell, because the POSIX form's `touch` is not a command in PowerShell and its directory flag is a parameter error there. Same file carries the envelope template this dispatch also owes.** The memory root's self-ignoring `.gitignore` guard is a separate obligation this gate does not grade — same file, "What this gate does not grade".

1. **The payload is well-formed** — `preload_token` matches the sentinel verbatim, and an `artifact:` pointer is present. Missing either is a **failed dispatch** whatever the `status` field says; a missing token is a discard, per the rule above.

   **And `scope_as_received` matches the scope the parent actually sent** — compared against the envelope the parent wrote, not against what it meant. It is the only check here that fires on an input that is present and wrong. A mismatch is a **failed dispatch**: re-dispatch with the scope restated in a form that survives the trip (see the caveat under **Scope**); do not accept the artifact and mentally translate it. A well-formed payload carrying no `scope_as_received` is an out-of-date agent definition, not a pass.
2. **The artifact set is actually on disk, and this run put it there:**

   ```bash
   "${CLAUDE_PLUGIN_ROOT}/scripts/check-dispatch-artifact.sh" <the retained memory-slice path> \
     --index-name EXPLORE.md \
     --newer-than <that slice>/.explore-dispatch --expect-index <the payload's artifact: value>
   ```

   `--index-name` is required, not defaulted — the same gate grades `/discovery:research` runs, the two artifact families differ only in that name, and a gate that fails closed everywhere else must not guess which family it is looking at.

   Cite the **exit status** — 0 usable, 1 no usable artifact set, 2 ungradeable — not a reading of the directory, because the context most motivated to call the dispatch finished is the one that would be doing the reading. Only the slice path and `--index-name` are required, and that bare form is still a real gate: every optional check reports `unchecked` rather than passing quietly. Append `--expect-sidecars <n>` when the payload reported a `sidecars:` count, and **drop any flag whose value the payload did not supply**.

   **The `index=` path in that output is authoritative** downstream: the verifier's target and the handoff pointer both come from it, not from `artifact:`. `pointer=mismatch` means the payload named a file this gate never graded — a defect in the payload, not a naming preference to reconcile.

**Any non-zero exit halts the workflow — and a gate that could not run at all is a FAIL, never a skip.** An invocation above that is denied, prompts and is declined, or errors out halts exactly as a non-zero exit does; do not fall back to reading the directory. (This plugin ships no `allowed-tools` grant, and that is a sourced conclusion rather than an omission: [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md).) Do **not** proceed to research, planning, or an edit on the strength of an exploration that did not happen — proceeding is the damage a silently-empty return actually causes; the missing artifact is only how it starts. Recovery ladder, and why a resume beats a re-dispatch: [`${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/dispatch.md`](${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/dispatch.md).

**One named exception, and it is an exception to the halt, not to the gate.** Exit 1 with `persistence: by-value` in the payload means the agent finished and its environment refused every write — the one failure the ladder previously had no rung for, and the one where a re-dispatch pays full price to reproduce the same refusal. There the parent **writes the slice itself** from the artifact bodies the payload carries verbatim, into the memory-slice path it resolved before dispatch (on that path the payload's `artifact:` value is a *destination* the agent names, never the anchor), and then **re-runs the identical gate command above**. The workflow proceeds only on a subsequent exit 0. If the second run is non-zero, the halt stands and the ladder resumes at the rung it was on. The freshness check needs nothing special: the parent writes after its own pre-dispatch `touch`, so the index is strictly newer than the baseline.

Two conditions bind that write, both spelled out in the ladder. **Filenames are checked before anything is written** — this is the only place a name the worker produced becomes a write the parent performs, at the parent's wider permission, so only `EXPLORE.md` and `EXPLORE-<section>.md` are accepted, as bare filenames, and anything carrying a directory separator, a `..` segment or a leading `/` is a failed dispatch rather than a name to sanitize. **And the collision rule still applies** — a slice root already holding an unrelated `EXPLORE.md` gets a parent-assigned sub-slice here exactly as it would for a worker that could write, because overwriting the index that rule protects would be a silent, unrecoverable loss arriving through the recovery path.

Nothing in the payload is ever accepted *in place of* the gate passing. `persistence: by-value` routes the parent; it does not grade anything, and it is never a reason to believe a run. A by-value payload carrying a summary of findings rather than the artifact bodies is a **failed dispatch**, not a fallback — the whole discipline rests on the artifact being real, and a claim the gate is invited to accept on trust is the laundering this skill exists to refuse. Why the mode exists and where its boundary sits: [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md).

**Coverage discipline** when fanning out: (1) write a numbered gap-list before any deepen pass; (2) fan out by disjoint area — never split the six dimensions across agents; (3) whoever holds the workflow writes `EXPLORE.md` — `discovery:explorer` writes its own, while built-in Explore agents cannot write one at all, so their caller does.

## Purpose

Exploration is the prerequisite for everything — you cannot change what you do not understand. Goal: **maximum local knowledge** before any action. Skipping exploration leads to wrong assumptions, missed patterns, broken conventions, and rework.

Local counterpart to `/discovery:research` (external sources). Together: `/discovery:explore` for what IS, `/discovery:research` for what SHOULD BE.

**Philosophy**: invest in understanding before acting. Reading 20 files takes seconds; fixing a wrong assumption takes minutes to hours. When in doubt, read more code.

**Plan-mode for high-risk exploration (optional, inline only)**: when exploring unfamiliar code in a high-blast-radius area (security boundaries, critical infrastructure, code you might accidentally modify mid-investigation), switch into plan mode for harness-level read-only protection. Routine exploration of well-understood code does not need this. **A dispatched run cannot switch into it** — `EnterPlanMode` is filtered out of every non-fork subagent unconditionally, and `ExitPlanMode` is filtered from every non-fork subagent too, "unless the subagent's `permissionMode` is `plan`". `discovery:explorer` lists neither tool in its `tools` allowlist, so it holds neither either way. There the read-only boundary is the agent's own instruction, honored deliberately rather than enforced by the harness.

## Scope

Explore the following: $ARGUMENTS

**A dispatched run does not read that line.** The scope does not reach a preloaded body by argument substitution, and a non-fork subagent has no view of the conversation to fall back on — so **do not rely on seeing an unfilled slot**: for a dispatched run the scope arrives in the dispatch prompt, and its absence is a parent-envelope failure the agent reports rather than repairs, whatever the line above renders as. There is no unscoped orientation mode under dispatch: a general repository sweep would hand back a plausible artifact answering a question nobody asked. What is documented about that path — and what is not, in either direction — is recorded once in [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md). Running **inline** with no scope supplied above, infer it from the current conversation context — identify what area of the codebase is relevant to the task at hand and explore that.

**Caveat — a `${CLAUDE_…}`-shaped token in a scope may not arrive as you typed it**, which is a different question from the paragraph above and not evidence for or against it. What was observed, what is documented, what is not, and the practical rule: [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md) ("A different question"). The `scope_as_received` echo-back in the acceptance gate is what catches it whichever way the substitution actually runs.

## Exploration dimensions

Cover the relevant subset of these dimensions. Not all apply to every task — use judgment about which matter for the current scope.

### 1. Codebase reading

Read the actual code before forming opinions about it.

- **Targeted files** — Read files directly relevant to the task. Use Glob by pattern, Grep by content
- **Adjacent code** — Read code that calls, is called by, or is structurally similar to the target. Understand the neighborhood, not just the target
- **Existing patterns** — Before proposing a new pattern, search for how the same concern is handled elsewhere in the repo. Reuse > reinvent (unless the existing pattern is an anti-pattern or well outside modern best practices and not documented as a pragmatic decision)
- **Convention files** — Check the consuming project's own `CLAUDE.md` and project rules for conventions that constrain the solution space
- **Reference source as spec** — when the task points at an existing implementation to match (a vendored library, another module, even another language), READ that source as the authoritative spec

### 2. Git history

Code has context only git reveals — who changed it, when, why, and what else changed alongside it.

- `git log --oneline -20 <path>` — recent change frequency and commit style
- `git log --oneline --all --since="2 weeks ago"` — recent repo-wide activity
- `git diff HEAD~5 -- <path>` — what changed recently in the target area
- `git blame <file>` — when specific lines were last touched and by whom
- **Missing files** — when `git status` or history references files that don't exist on disk, they may be intentionally deleted, so do not open git archaeology on them unprompted. Inline, ask first. **Dispatched, you cannot ask** — record the file as an `open_questions` entry for the parent to surface and move on; asking is not optional here, so proceeding anyway would silently violate the rule that protects a deliberate deletion

### 3. Project structure

Understand how the pieces fit together before moving any of them.

- **Directory layout** — if the project documents its repository structure, verify the doc matches reality; otherwise map the tree yourself
- **Project references / imports** — map the dependency graph by grepping the ecosystem's import/reference token across its build-config files (per-ecosystem tokens: `${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/ecosystem-discovery.md` — compose `/toolchain:check`'s covered-ecosystem set when the `toolchain` plugin is installed, retaining fallback ecosystems the seam does not cover; otherwise the reference's fallback table)
- **Solution / workspace membership** — check the repo's solution or workspace file at the root for what's included
- **Layer boundaries** — respect any dependency-direction rules the project declares
- **Planned direction** — cross-reference findings with any stated direction in the project's own `CLAUDE.md` or docs. Assess how changes must fit the repo's current state AND planned direction

### 4. Test discovery

Tests are executable documentation. They reveal intended behavior, edge cases, and existing coverage.

- **Find test projects** — Glob the per-ecosystem test patterns in `${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/ecosystem-discovery.md` (`test-globs` / `test-content-grep` are explore-owned even when composing the toolchain seam)
- **Co-located tests** — check whether unit tests live next to their source (sibling test project, `__tests__/`, adjacent `_test.go`) or in a separate tree
- **Cross-cutting tests** — a repo-root `tests/` for architecture, dependency, or naming-rule tests that span multiple libraries
- **Test patterns** — read existing tests (start with 2-3, scale to the number of distinct patterns in play) to understand naming conventions, assertion style, and fixture patterns before writing new ones
- **Coverage gaps** — identify areas with no test coverage that the current task touches

### 5. Configuration and build state

Build configuration constrains what's possible. Understand it before fighting it.

- **Build configs** — read the ecosystem's build / package / config files per `${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/ecosystem-discovery.md` (explore-owned `build-configs` even when composing the toolchain seam; resolved `project-discovery` / `anchor` locate roots)
- **Analyzer / lint config** — `.editorconfig` for shared severity levels; ecosystem-specific analyzer/linter files
- **Package versions** — check the ecosystem's manifest (lockfile + central-version-management file if applicable)
- **CI/CD** — `.github/workflows/` (or the project's CI equivalent) for what's validated on every PR

### 6. Environment and machine state

When the task involves tooling, MCP servers, or infrastructure:

- **Installed versions** — probe per `${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/ecosystem-discovery.md` (explore-owned `runtime-version-cmd` even when composing the toolchain seam; `install-hint` is install prose, not a version probe)
- **MCP server status** — test with a read-only call before depending on it
- **Worktree state** — `git worktree list`, current branch, uncommitted changes
- **Local config** — project-local settings for env vars and tokens (don't read secrets, just verify presence)

## Exploration modes

The resolved scope shapes the exploration focus — read from `$ARGUMENTS` inline, and from the dispatch prompt under dispatch, which is the only place a dispatched run gets it:

| Argument | Focus | Key actions |
|----------|-------|-------------|
| *(empty)* | Infer from conversation context | Read relevant code, check git history, verify tests exist |
| `<area>` (a module, namespace, or directory) | Targeted area deep-dive | Read all files in area, trace dependencies in and out, find tests |
| `deps` or `dependencies` | Dependency graph analysis | Map project references, check for circular deps, verify layer rules |
| `tests` | Test structure and coverage | Find all test projects, read test patterns, identify gaps |
| `git` | Recent change history | `git log`, active branches, recent contributors, change velocity |
| `config` | Build and tool configuration | Read `.editorconfig`, build configs, analyzer settings, CI workflows |
| `<file-path>` | Single file deep-dive | Read file, its tests, its callers, its git history |

Multiple arguments combine: `/discovery:explore payments deps tests` explores that area's dependencies AND test coverage.

> Surfacing the USER's unknown-unknowns before they work in unfamiliar territory — a better-prompt deliverable, not the `EXPLORE.md` artifact — is the sibling [`/discovery:blindspot`](${CLAUDE_PLUGIN_ROOT}/skills/blindspot/SKILL.md) skill.

## Output format

Present exploration findings as:

1. **Summary** — 2-3 sentence overview of what was found
2. **Current state** — key facts about the explored area (structure, patterns, dependencies). When the explored module has a domain-vocabulary or glossary file, frame findings using the module's domain vocabulary
3. **Existing patterns** — how similar concerns are handled elsewhere in the repo
4. **Test coverage** — what's tested, what's not, what test patterns are used
5. **Constraints** — analyzers, conventions, layer rules, or CI gates that constrain the solution
6. **Planned direction alignment** — how findings relate to any direction the project documents
7. **Open questions** — anything that needs clarification before proceeding, each with a one-line recommended default + escape hatch. **Inline, surface these to the USER. Dispatched, return them as `open_questions` in the payload and the parent surfaces them** — `AskUserQuestion` is filtered out of every non-fork subagent, so the payload is how they reach a human at all. Either way, silent downstream resolution of a surfaced open question is an anti-pattern; the hand-off changes, the rule does not

If invoked standalone, present findings directly. If invoked as part of a larger workflow, findings feed into subsequent research and planning steps.

## Outcome gate (before EXPLORE.md handoff)

Before writing EXPLORE.md (or returning the summary), check the artifact against **binary criteria read off it** — not a "did I explore enough?" recap. Any FAIL → return to the named dimension and fix before handoff:

- **Every Output-format section populated with specifics** — each of the 7 sections carries concrete findings, not placeholders or "TBD".
- **Every load-bearing area covered OR listed as a numbered gap** — nothing the task plausibly depends on is silently unexplored.
- **Conclusion-driving claims are Read-verified, not inferred from a filename or grep hit** — anything a downstream decision rests on came from reading the file or code.
- **Paths are machine-agnostic** — no finding in the artifact echoes an absolute machine path (notably the pre-computed project root); every path it records is written relative to the repo root, or — when there is no repo root — to the current working directory, so the handoff stays portable across machines.
- **Open questions handed off, never dropped** — surfaced to the user inline, or carried in the payload's `open_questions` for the parent to surface under dispatch. Each with a recommended default.

## Final step: persist artifact for handoff

Write the exploration output to `<memory_dir>/<slug>/EXPLORE.md` — a memory-tier artifact, never committed. Destination, slug, and runtime guards resolve per the plugin's topic-docs binding ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)).

This file is the authoritative stage summary — a fresh session must be able to resume external research or planning reading only this artifact.

**`EXPLORE.md` is always an INDEX**, at every size — not only past an overflow threshold. It carries a task restatement, a one-line abstract per sidecar copied verbatim from that sidecar's header, a section → file + anchor table, and the closing Next-stage-handoff naming what external research (`/discovery:research`) or planning needs. The 7-point Output format's content lives in sibling `EXPLORE-<section>.md` sidecars in the same directory, each opening with a machine-readable YAML header so a consumer can grep headers and read exactly one file. Schema and the two load-bearing placement rules — sidecars stay inside `<memory_dir>/<slug>/`, and `EXPLORE.md` stays the entry point: [`${CLAUDE_PLUGIN_ROOT}/skills/research/context/artifact-shape.md`](${CLAUDE_PLUGIN_ROOT}/skills/research/context/artifact-shape.md).

**Sidecar bodies match their length to what the section needs** — cover the substance, but do not pad with filler sections, redundant summaries, or boilerplate; the index's one-line abstracts and the outcome gate's specifics are the floor, not an invitation to narrate.

**Sidecar filenames are keyed on the SECTION, not the scope** — a run has one scope and many sections, so a scope-keyed name gives every sidecar the same filename and later sections overwrite earlier ones. Use the same stable id the header's `section` field and the index anchor carry.

**Sidecar headers use the EXPLORE schema, not the research one.** Local evidence is a repository path and whether the file was actually Read — `verified: read | grep | inferred` — not a URL, a source tier, and a publishing pool. Handed the research header, a run either fabricates fields it has no values for or improvises a shape no consumer can parse; the fabrication is worse, because it launders a grep hit into the field a fetched primary would occupy. Schema and why `verified` is load-bearing: the artifact-shape spoke's "EXPLORE.md sidecar header" section.

**If an unrelated `EXPLORE.md` already exists** in that slice, do not clobber it — and do not rename the index to dodge it, since `EXPLORE-*.md` is the sidecar pattern and a renamed index collides with its own sidecars. Write the whole artifact set, under its normal names, into a sub-slice `<memory_dir>/<slug>/<scope-slug>/`, and report that path. A prior exploration lost to a filename collision is silent and unrecoverable.

## Gotchas

- **Fan-out without a numbered gap-list** — dispatching subagents before writing gaps produces duplicate reads and missed areas. The gap-list is the coverage-discipline gate.
- **Handing off with placeholder sections** — every Output-format section needs specifics or an explicit numbered gap. "TBD" fails the outcome gate.
- **Inferring from filenames without Read** — grep hits are discovery only; conclusion-driving claims need Read verification.
- **Investigating deleted files without asking** — when `git status` shows intentional deletes, ask before archaeology.

## What this skill does NOT do

- **Does not research externally** — that's `/discovery:research`. This skill reads local code, git, and file system only
- **Does not make changes** — it explores. Execution is a separate step
- **Does not make decisions** — it presents what IS. The planning step decides what SHOULD BE
- **Does not skip dimensions for "simple" tasks** — a quick bug fix still benefits from reading the surrounding code and checking for tests
- **Does not substitute for reading** — when uncertain, Read the file. Don't infer from file names or git log alone
