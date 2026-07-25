---
name: explore
description: "Explore the local codebase before making changes — read code, trace dependencies, scan git history, discover tests, and audit build and tool configuration, persisting an EXPLORE.md index plus sidecars. Dispatches a fresh-context subagent by default so the file reads stay out of the main conversation, with a documented inline escape hatch. Use when: 'explore the codebase', 'what exists for X' investigation, 'how does this work', 'where is X implemented', 'trace the dependencies', 'what tests cover this', or as step 1 before any code change."
argument-hint: "[scope] (e.g., /discovery:explore payments module dependencies, /discovery:explore tests, /discovery:explore git, /discovery:explore config)"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo "clean"`
Project root: !`git rev-parse --show-toplevel 2>/dev/null || echo "unknown"`

These values orient this session only. The project root is an absolute machine path — use it to resolve files while working, but never echo it into `EXPLORE.md`; the handoff artifact records relative paths (see the outcome gate below).

## Routing — dispatch by default

**From the main conversation, this skill dispatches the `discovery:explorer` subagent.** Exploration reads many files; keeping that out of the orchestrator's context window is the point. The agent loads the project's path-scoped rules, runs the six dimensions, writes the artifact set, and returns a bounded summary plus a file pointer — not the reads. The parent resolves the **pre-dispatch envelope** first (scope, memory-slice path, budget, capability flags) and owns the **post-dispatch boundary** after: re-surfacing `open_questions` to the user, and dispatching the sibling verifier.

**Run inline instead when any of these holds** — inline runs the identical workflow, and the escape hatch relaxes nothing:

- **Tight turn-by-turn iteration** — ≤~5 known files, findings feeding a same-session edit, and you will redirect as results land.
- **Cost** — a dispatched run pays the full six dimensions every time; a single-file question does not need an envelope.
- **The invoking context is already a subagent** — dispatch-by-default is scoped to the main-conversation boundary. Hoisting, not nesting: the outer dispatch already supplied the fresh context, so a second hop only spends the inner agent's own window.

**Two named alternatives:**

- **Built-in Explore subagent** — for raw "where is X / how does Y work" search. Fast, read-only, context-isolated. It skips project memory (convention-blind) and neither runs this 6-dimension workflow nor writes `EXPLORE.md` — pass key constraints in the prompt when conventions matter, and expect to write the artifact yourself. Scale 1→N by dispatching more, each owning a disjoint area.
- **`/explore-deep`** — this workflow in a forked subagent that loads project memory and persists `EXPLORE.md` itself. Pass explicit scope in the invocation arguments; a fork does not see the parent conversation.

**Preload-liveness sentinel.** A dispatched agent receives this body through its `skills:` preload, and a preload that fails to resolve is skipped **silently** — logged to the debug log and nowhere else. A dispatched run therefore echoes this token verbatim as `preload_token` in its return payload:

```text
discovery-explore-preload-8e2b7d
```

A missing or mismatched token is a **hard failure: the parent discards the run**, never downgrades or accepts the artifact. Without it, a preload miss produces an undisciplined run that still writes an artifact — indistinguishable from success at every other seam.

**Coverage discipline** when fanning out: (1) write a numbered gap-list before any deepen pass; (2) fan out by disjoint area — never split the six dimensions across agents; (3) whoever holds the workflow writes `EXPLORE.md` — `discovery:explorer` writes its own, while built-in Explore agents cannot write one at all, so their caller does.

## Purpose

Exploration is the prerequisite for everything — you cannot change what you do not understand. Goal: **maximum local knowledge** before any action. Skipping exploration leads to wrong assumptions, missed patterns, broken conventions, and rework.

Local counterpart to `/research` (external sources). Together: `/explore` for what IS, `/research` for what SHOULD BE.

**Philosophy**: invest in understanding before acting. Reading 20 files takes seconds; fixing a wrong assumption takes minutes to hours. When in doubt, read more code.

**Plan-mode for high-risk exploration (optional, inline only)**: when exploring unfamiliar code in a high-blast-radius area (security boundaries, critical infrastructure, code you might accidentally modify mid-investigation), switch into plan mode for harness-level read-only protection. Routine exploration of well-understood code does not need this. **A dispatched run cannot reach it** — `EnterPlanMode` and `ExitPlanMode` are filtered out of every non-fork subagent — so there the read-only boundary is the agent's own instruction, honored deliberately rather than enforced by the harness.

## Scope

Explore the following: $ARGUMENTS

**A dispatched run does not read that line.** `$ARGUMENTS` substitutes to the empty string on the preload path, and a non-fork subagent has no view of the conversation to fall back on — so for a dispatched run the scope arrives in the dispatch prompt, and its absence is a parent-envelope failure the agent reports rather than repairs. There is no unscoped orientation mode under dispatch: a general repository sweep would hand back a plausible artifact answering a question nobody asked. Running **inline** with no scope supplied above, infer it from the current conversation context — identify what area of the codebase is relevant to the task at hand and explore that.

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
- **Project references / imports** — map the dependency graph by grepping the ecosystem's import/reference token across its build-config files (per-ecosystem tokens: `${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/ecosystem-discovery.md`)
- **Solution / workspace membership** — check the repo's solution or workspace file at the root for what's included
- **Layer boundaries** — respect any dependency-direction rules the project declares
- **Planned direction** — cross-reference findings with any stated direction in the project's own `CLAUDE.md` or docs. Assess how changes must fit the repo's current state AND planned direction

### 4. Test discovery

Tests are executable documentation. They reveal intended behavior, edge cases, and existing coverage.

- **Find test projects** — Glob the per-ecosystem test patterns in `${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/ecosystem-discovery.md`
- **Co-located tests** — check whether unit tests live next to their source (sibling test project, `__tests__/`, adjacent `_test.go`) or in a separate tree
- **Cross-cutting tests** — a repo-root `tests/` for architecture, dependency, or naming-rule tests that span multiple libraries
- **Test patterns** — read existing tests (start with 2-3, scale to the number of distinct patterns in play) to understand naming conventions, assertion style, and fixture patterns before writing new ones
- **Coverage gaps** — identify areas with no test coverage that the current task touches

### 5. Configuration and build state

Build configuration constrains what's possible. Understand it before fighting it.

- **Build configs** — read the ecosystem's build / package / config files (per-ecosystem lists in `${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/ecosystem-discovery.md`)
- **Analyzer / lint config** — `.editorconfig` for shared severity levels; ecosystem-specific analyzer/linter files
- **Package versions** — check the ecosystem's manifest (lockfile + central-version-management file if applicable)
- **CI/CD** — `.github/workflows/` (or the project's CI equivalent) for what's validated on every PR

### 6. Environment and machine state

When the task involves tooling, MCP servers, or infrastructure:

- **Installed versions** — run the per-ecosystem version commands in `${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/ecosystem-discovery.md`
- **MCP server status** — test with a read-only call before depending on it
- **Worktree state** — `git worktree list`, current branch, uncommitted changes
- **Local config** — project-local settings for env vars and tokens (don't read secrets, just verify presence)

## Exploration modes

The resolved scope shapes the exploration focus — read from `$ARGUMENTS` inline, and from the dispatch prompt under dispatch, where `$ARGUMENTS` is empty:

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

**`EXPLORE.md` is always an INDEX**, at every size — not only past an overflow threshold. It carries a task restatement, a one-line abstract per sidecar copied verbatim from that sidecar's header, a section → file + anchor table, and the closing Next-stage-handoff naming what external research (`/research`) or planning needs. The 7-point Output format's content lives in sibling `EXPLORE-<scope>.md` sidecars in the same directory, each opening with a machine-readable YAML header so a consumer can grep headers and read exactly one file. Schema and the two load-bearing placement rules — sidecars stay inside `<memory_dir>/<slug>/`, and `EXPLORE.md` stays the entry point: [`${CLAUDE_PLUGIN_ROOT}/skills/research/context/artifact-shape.md`](${CLAUDE_PLUGIN_ROOT}/skills/research/context/artifact-shape.md).

**If an unrelated `EXPLORE.md` already exists** in that slice, do not clobber it: write `EXPLORE-<scope>.md` instead and name the filename you chose in the return. A prior exploration lost to a filename collision is silent and unrecoverable.

## Gotchas

- **Fan-out without a numbered gap-list** — dispatching subagents before writing gaps produces duplicate reads and missed areas. The gap-list is the coverage-discipline gate.
- **Handing off with placeholder sections** — every Output-format section needs specifics or an explicit numbered gap. "TBD" fails the outcome gate.
- **Inferring from filenames without Read** — grep hits are discovery only; conclusion-driving claims need Read verification.
- **Investigating deleted files without asking** — when `git status` shows intentional deletes, ask before archaeology.

## What this skill does NOT do

- **Does not research externally** — that's `/research`. This skill reads local code, git, and file system only
- **Does not make changes** — it explores. Execution is a separate step
- **Does not make decisions** — it presents what IS. The planning step decides what SHOULD BE
- **Does not skip dimensions for "simple" tasks** — a quick bug fix still benefits from reading the surrounding code and checking for tests
- **Does not substitute for reading** — when uncertain, Read the file. Don't infer from file names or git log alone
