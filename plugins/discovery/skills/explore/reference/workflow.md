# Explore worker procedure

Load this file when you are the worker: an inline `/discovery:explore` run, or the dispatched
`discovery:explorer`. The parent does not load it in order to dispatch. `SKILL.md` keeps the
routing gates and the outcome gate; this file is the procedure those gates grade.

## Purpose

Read the code before changing it. This skill builds the local knowledge a change depends on: the code, its neighbors, its history, its tests, and the build and tool configuration that constrains the solution. The six dimensions below say what to read; the outcome gate says when it is enough.

Local counterpart to `/discovery:research` (external sources). Together: `/discovery:explore` for what IS, `/discovery:research` for what SHOULD BE.

**Plan-mode for high-risk exploration (optional, inline only)**: when exploring unfamiliar code in a high-blast-radius area (security boundaries, critical infrastructure, code you might accidentally modify mid-investigation), switch into plan mode for harness-level read-only protection. Routine exploration of well-understood code does not need this. **A dispatched run cannot switch into it**. `EnterPlanMode` is filtered out of every non-fork subagent unconditionally, and `ExitPlanMode` is filtered from every non-fork subagent too, "unless the subagent's `permissionMode` is `plan`". The dated record for that harness behavior is [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md), "Harness facts the dispatch design rests on". `discovery:explorer` lists neither tool in its `tools` allowlist, so it holds neither either way. There the read-only boundary is the agent's own instruction, honored deliberately rather than enforced by the harness.

## Scope

Explore the following: $ARGUMENTS

**A dispatched run does not read that line.** The scope does not reach a preloaded body by argument substitution, and a non-fork subagent has no view of the conversation to fall back on, so **do not rely on seeing an unfilled slot**: for a dispatched run the scope arrives in the dispatch prompt, and its absence is a parent-envelope failure the agent reports rather than repairs, whatever the line above renders as. There is no unscoped orientation mode under dispatch: a general repository sweep would hand back a plausible artifact answering a question nobody asked. What is documented about that path, and what is not, in either direction, is recorded once in [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md). Running **inline** with no scope supplied above, infer it from the current conversation context. Identify what area of the codebase is relevant to the task at hand and explore that.

**Caveat, a `${CLAUDE_…}`-shaped token in a scope may not arrive as you typed it**, which is a different question from the paragraph above and not evidence for or against it. What was observed, what is documented, what is not, and the practical rule: [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md) ("A different question"). The `scope_as_received` echo-back in the acceptance gate is what catches it whichever way the substitution actually runs.

## Exploration dimensions

Cover the relevant subset of these dimensions. Not all apply to every task. Use judgment about which matter for the current scope.

### 1. Codebase reading

Read the actual code before forming opinions about it.

- **Targeted files**. Read files directly relevant to the task. Use Glob by pattern, Grep by content
- **Adjacent code**. Read code that calls, is called by, or is structurally similar to the target. Understand the neighborhood, not just the target
- **Existing patterns**. Before proposing a new pattern, search for how the same concern is handled elsewhere in the repo. Reuse > reinvent (unless the existing pattern is an anti-pattern or well outside modern best practices and not documented as a pragmatic decision)
- **Convention files**. The project's always-loaded instructions (root `CLAUDE.md` and the files it imports) are already in context, in a dispatched run too, so do not re-read them. Read the path-scoped rule files under `.claude/rules/` and any nested `AGENTS.md` covering the target area for conventions that constrain the solution space: those reach a context only when a file they cover is read, which an exploration may never do for the area a rule governs
- **Reference source as spec**, when the task points at an existing implementation to match (a vendored library, another module, even another language), READ that source as the authoritative spec

### 2. Git history

Code has context only git reveals, who changed it, when, why, and what else changed alongside it.

- `git log --oneline -20 <path>`. Recent change frequency and commit style
- `git log --oneline --all --since="2 weeks ago"`. Recent repo-wide activity
- `git diff HEAD~5 -- <path>`. What changed recently in the target area
- `git blame <file>`, when specific lines were last touched and by whom
- **Missing files**, when `git status` or history references files that don't exist on disk, they may be intentionally deleted, so do not open git archaeology on them unprompted. Inline, ask first. **Dispatched, you cannot ask**. Record the file as an `open_questions` entry for the parent to surface and move on; asking is not optional here, so proceeding anyway would silently violate the rule that protects a deliberate deletion

### 3. Project structure

Understand how the pieces fit together before moving any of them.

- **Directory layout**, if the project documents its repository structure, verify the doc matches reality; otherwise map the tree yourself
- **Project references / imports**. Map the dependency graph by grepping the ecosystem's import/reference token across its build-config files (per-ecosystem tokens: `${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/ecosystem-discovery.md`. Compose `/toolchain:check`'s covered-ecosystem set when the `toolchain` plugin is installed, retaining fallback ecosystems the seam does not cover; otherwise the reference's fallback table)
- **Solution / workspace membership**. Check the repo's solution or workspace file at the root for what's included
- **Layer boundaries**. Respect any dependency-direction rules the project declares
- **Planned direction**. Cross-reference findings with any stated direction in the project's own `CLAUDE.md` or docs. Assess how changes must fit the repo's current state AND planned direction

### 4. Test discovery

Tests are executable documentation. They reveal intended behavior, edge cases, and existing coverage.

- **Find test projects**. Glob the per-ecosystem test patterns in `${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/ecosystem-discovery.md` (`test-globs` / `test-content-grep` are explore-owned even when composing the toolchain seam)
- **Co-located tests**. Check whether unit tests live next to their source (sibling test project, `__tests__/`, adjacent `_test.go`) or in a separate tree
- **Cross-cutting tests**, a repo-root `tests/` for architecture, dependency, or naming-rule tests that span multiple libraries
- **Test patterns**. Read existing tests (start with 2-3, scale to the number of distinct patterns in play) to understand naming conventions, assertion style, and fixture patterns before writing new ones
- **Coverage gaps**. Identify areas with no test coverage that the current task touches

### 5. Configuration and build state

Build configuration constrains what's possible. Understand it before fighting it.

- **Build configs**. Read the ecosystem's build / package / config files per `${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/ecosystem-discovery.md` (explore-owned `build-configs` even when composing the toolchain seam; resolved `project-discovery` / `anchor` locate roots)
- **Analyzer / lint config**. `.editorconfig` for shared severity levels; ecosystem-specific analyzer/linter files
- **Package versions**. Check the ecosystem's manifest (lockfile + central-version-management file if applicable)
- **CI/CD**. `.github/workflows/` (or the project's CI equivalent) for what's validated on every PR

### 6. Environment and machine state

When the task involves tooling, MCP servers, or infrastructure:

- **Installed versions**. Probe per `${CLAUDE_PLUGIN_ROOT}/skills/explore/reference/ecosystem-discovery.md` (explore-owned `runtime-version-cmd` even when composing the toolchain seam; `install-hint` is install prose, not a version probe)
- **MCP server status**. Test with a read-only call before depending on it
- **Worktree state**. `git worktree list`, current branch, uncommitted changes
- **Local config**. Project-local settings for env vars and tokens (don't read secrets, just verify presence)

## Exploration modes

The resolved scope shapes the exploration focus. Read from `$ARGUMENTS` inline, and from the dispatch prompt under dispatch, which is the only place a dispatched run gets it:

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

> Surfacing the USER's unknown-unknowns before they work in unfamiliar territory, a better-prompt deliverable, not the `EXPLORE.md` artifact, is the sibling [`/discovery:blindspot`](${CLAUDE_PLUGIN_ROOT}/skills/blindspot/SKILL.md) skill.

## Output format

Present exploration findings as:

1. **Summary**. 2-3 sentence overview of what was found
2. **Current state**. Key facts about the explored area (structure, patterns, dependencies). When the explored module has a domain-vocabulary or glossary file, frame findings using the module's domain vocabulary
3. **Existing patterns**. How similar concerns are handled elsewhere in the repo
4. **Test coverage**. What's tested, what's not, what test patterns are used
5. **Constraints**. Analyzers, conventions, layer rules, or CI gates that constrain the solution
6. **Planned direction alignment**. How findings relate to any direction the project documents
7. **Open questions**. Anything that needs clarification before proceeding, each with a one-line recommended default + escape hatch. **Inline, surface these to the USER. Dispatched, return them as `open_questions` in the payload and the parent surfaces them**. `AskUserQuestion` is filtered out of every non-fork subagent, so the payload is how they reach a human at all; the dated record is [`${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/parent-contract.md), "Harness facts the dispatch design rests on". Either way, silent downstream resolution of a surfaced open question is an anti-pattern; the hand-off changes, the rule does not

If invoked standalone, present findings directly. If invoked as part of a larger workflow, findings feed into subsequent research and planning steps.
