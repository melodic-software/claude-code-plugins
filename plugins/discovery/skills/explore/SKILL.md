---
name: explore
description: "Explore the local codebase before making changes — read code, trace dependencies, scan git history, discover tests, and audit build and tool configuration. Use as step 1 before any code change, for 'what exists for X' investigation, or in blindspot mode to surface the user's unknown-unknowns in unfamiliar territory."
argument-hint: "[scope] (e.g., /discovery:explore payments module dependencies, /discovery:explore tests, /discovery:explore git, /discovery:explore config, /discovery:explore blindspot <area-or-domain>)"
user-invocable: true
disable-model-invocation: false
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Working tree status: !`git status --porcelain 2>/dev/null | head -20 || echo "clean"`
Project root: !`git rev-parse --show-toplevel 2>/dev/null || echo "unknown"`

## Routing — context preservation first (three ways to explore)

Exploration reads many files; keeping that out of the main conversation is what subagents are for. Three ways to run it, by how much context it burns and whether you need this structured workflow:

- **Built-in Explore subagent — context-preserving default.** For raw "where is X / how does Y work" search, delegate to a fresh Explore subagent ("use a subagent to investigate X"). Fast, read-only, context-isolated. It skips project memory (convention-blind) and does NOT run this 6-dimension workflow or write `EXPLORE.md` — pass key constraints in the prompt when conventions matter. Scale 1→N for coverage: dispatch more Explore subagents (each owning a disjoint area) until nothing relevant to the task is left undiscovered; the main session synthesizes their summaries and persists the artifact.
- **Inline `/explore` — this structured workflow, scoped.** Stay here when ALL hold: ≤~5 known files; tight turn-by-turn iteration; findings feed a same-session edit; you need the `EXPLORE.md` artifact with project rules already loaded. Runs the full 6 dimensions in main context.
- **`/explore-deep` — this structured workflow, forked.** For a single deep pass whose synthesis must ALSO stay off main context: a forked subagent that loads project memory and persists `EXPLORE.md` itself before returning only a summary. Pass explicit scope in the invocation arguments — a fork does not see the parent conversation. Requires `CLAUDE_CODE_FORK_SUBAGENT=1`; if unset, fall back to the built-in Explore subagent or inline.

**Coverage discipline** when fanning out: (1) write a numbered gap-list before any deepen pass; (2) fan out by disjoint area — never split the six dimensions across agents; (3) the main session synthesizes and writes `EXPLORE.md` (built-in Explore agents cannot write it).

## Purpose

Exploration is the prerequisite for everything — you cannot change what you do not understand. Goal: **maximum local knowledge** before any action. Skipping exploration leads to wrong assumptions, missed patterns, broken conventions, and rework.

Local counterpart to `/research` (external sources). Together: `/explore` for what IS, `/research` for what SHOULD BE.

**Philosophy**: invest in understanding before acting. Reading 20 files takes seconds; fixing a wrong assumption takes minutes to hours. When in doubt, read more code.

**Plan-mode for high-risk exploration (optional)**: when exploring unfamiliar code in a high-blast-radius area (security boundaries, critical infrastructure, code you might accidentally modify mid-investigation), switch into plan mode for harness-level read-only protection. Routine exploration of well-understood code does not need this.

## Scope

Explore the following: $ARGUMENTS

If no specific scope was provided above, infer the exploration scope from the current conversation context — identify what area of the codebase is relevant to the task at hand and explore that.

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
- **Missing files** — when `git status` or history references files that don't exist on disk, **ask the user before investigating** via git archaeology. They may be intentionally deleted

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

The `$ARGUMENTS` value shapes the exploration focus:

| Argument | Focus | Key actions |
|----------|-------|-------------|
| *(empty)* | Infer from conversation context | Read relevant code, check git history, verify tests exist |
| `<area>` (a module, namespace, or directory) | Targeted area deep-dive | Read all files in area, trace dependencies in and out, find tests |
| `deps` or `dependencies` | Dependency graph analysis | Map project references, check for circular deps, verify layer rules |
| `tests` | Test structure and coverage | Find all test projects, read test patterns, identify gaps |
| `git` | Recent change history | `git log`, active branches, recent contributors, change velocity |
| `config` | Build and tool configuration | Read `.editorconfig`, build configs, analyzer settings, CI workflows |
| `<file-path>` | Single file deep-dive | Read file, its tests, its callers, its git history |
| `blindspot <area-or-domain>` | The USER's unknown-unknowns, not the agent's | See "Blindspot mode" below |

Multiple arguments combine: `/discovery:explore payments deps tests` explores that area's dependencies AND test coverage.

## Blindspot mode

Every other mode builds the AGENT's local knowledge; blindspot mode builds the USER's. Run it when the user is about to work in territory they don't know — an unfamiliar codebase area OR an unfamiliar domain vocabulary — and the goal is a better prompt.

1. **Intake** — ask the user's starting point first (one question). Blindspot output calibrates to that disclosure.
2. **Scan** — codebase lane: read the target area (dimensions 1-3 above) looking specifically for things the user's framing didn't account for — existing patterns they'd duplicate, constraints they'd violate, historical decisions they'd re-litigate, adjacent code their change would break. Domain lane: build a lightweight vocabulary ladder grounded in sources fetched this session (repo files, official docs) — never bare training recall.
3. **Output — blindspot cards.** One card per blindspot: the gap, why it matters here, and a copyable prompt-fix line. Close by assembling the fixes into ONE improved implementation prompt the user can run next.
4. **Escalate when depth warranted** — a domain too deep for a lightweight ladder gets a recommendation to run proper external research (`/research`) or whatever structured-learning capability the environment provides.

Blindspot mode does NOT write EXPLORE.md by default — its deliverable is the user's understanding plus the improved prompt. Offer the persist only when findings double as stage-1 exploration.

## Output format

Present exploration findings as:

1. **Summary** — 2-3 sentence overview of what was found
2. **Current state** — key facts about the explored area (structure, patterns, dependencies). When the explored module has a domain-vocabulary or glossary file, frame findings using the module's domain vocabulary
3. **Existing patterns** — how similar concerns are handled elsewhere in the repo
4. **Test coverage** — what's tested, what's not, what test patterns are used
5. **Constraints** — analyzers, conventions, layer rules, or CI gates that constrain the solution
6. **Planned direction alignment** — how findings relate to any direction the project documents
7. **Open questions** — anything that needs clarification before proceeding. **Surface these to the USER**, each with a one-line recommended default + escape hatch. Silent downstream resolution of surfaced open questions is an anti-pattern

If invoked standalone, present findings directly. If invoked as part of a larger workflow, findings feed into subsequent research and planning steps.

## Outcome gate (before EXPLORE.md handoff)

Blindspot-only runs SKIP this gate — their deliverable is blindspot cards plus an improved prompt, not the 7-section artifact (run it only when the user opts into the EXPLORE.md persist). For all other modes: before writing EXPLORE.md (or returning the summary), check the artifact against **binary criteria read off it** — not a "did I explore enough?" recap. Any FAIL → return to the named dimension and fix before handoff:

- **Every Output-format section populated with specifics** — each of the 7 sections carries concrete findings, not placeholders or "TBD".
- **Every load-bearing area covered OR listed as a numbered gap** — nothing the task plausibly depends on is silently unexplored.
- **Conclusion-driving claims are Read-verified, not inferred from a filename or grep hit** — anything a downstream decision rests on came from reading the file or code.
- **Open questions surfaced to the user**, each with a recommended default.

## Final step: persist artifact for handoff

Blindspot-only runs SKIP this step (see "Blindspot mode"). For all other modes: write the exploration output to `<memory_dir>/<slug>/EXPLORE.md` — a memory-tier artifact, never committed. Destination, slug, and runtime guards resolve per the plugin's topic-docs binding ([`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)).

This file is the authoritative stage summary — a fresh session must be able to resume external research or planning reading only this artifact. The artifact's Findings section follows the 7-point Output format above, and a closing Next-stage-handoff names what external research (`/research`) or planning needs.

If exploration spans many sub-areas and EXPLORE.md exceeds ~2000 words, split overflow into sibling `EXPLORE-<scope>.md` files in the same directory and keep EXPLORE.md as the index.

## Gotchas

- **Fan-out without a numbered gap-list** — dispatching subagents before writing gaps produces duplicate reads and missed areas. The gap-list is the coverage-discipline gate.
- **Handing off with placeholder sections** — every Output-format section needs specifics or an explicit numbered gap. "TBD" fails the outcome gate.
- **Inferring from filenames without Read** — grep hits are discovery only; conclusion-driving claims need Read verification.
- **Investigating deleted files without asking** — when `git status` shows intentional deletes, ask before archaeology.

## What this skill does NOT do

- **Does not research externally** — that's `/research`. This skill reads local code, git, and file system only. Sole carve-out: the blindspot domain lane may fetch official docs to ground its vocabulary ladder
- **Does not make changes** — it explores. Execution is a separate step
- **Does not make decisions** — it presents what IS. The planning step decides what SHOULD BE
- **Does not skip dimensions for "simple" tasks** — a quick bug fix still benefits from reading the surrounding code and checking for tests
- **Does not substitute for reading** — when uncertain, Read the file. Don't infer from file names or git log alone
