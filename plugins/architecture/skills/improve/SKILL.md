---
name: improve
description: "Scan an existing codebase for module-level friction and architecture improvement opportunities. Explores for shallow modules (interface nearly as complex as implementation), seam leaks, and locality gaps; presents candidates as a self-contained HTML report; runs an interview loop on the selected candidate, with a Design-It-Twice branch that fans out parallel subagents to design the interface several radically different ways; hands off an agreed candidate shape for planning. Use when: 'improve architecture', 'find deepening opportunities', 'shallow modules', 'architecture improvement', 'Ousterhout deepening', 'design it twice', 'compare alternative interfaces', 'make code more testable', 'make code more AI-navigable', 'find refactoring opportunities', 'what should we improve', 'architecture scan', 'codebase friction', 'module seams', 'locality'. Skip when: applying mechanical code-level tidyings (this operates at module level), reviewing a diff before merge, enforcing architecture rules on a change, or root-cause debugging a specific failure."
argument-hint: "[action] (e.g., deepening)"
user-invocable: true
disable-model-invocation: false
shell: bash
metadata:
  workflow-stage: plan
  summary: Scan the codebase for shallow modules and friction, then design the chosen fix several ways
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Recent commits: !`git log --oneline -10 2>/dev/null || echo "no commits"`
Working tree status: !`git status --porcelain 2>/dev/null | head -10 || echo "clean"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Improvement is distinct from review and planning. Review evaluates a DIFF against criteria (reactive). Planning designs NEW work (forward-looking). This skill scans EXISTING code for friction and proposes candidates for improvement (proactive).

The scan-present-pick process generalizes across improvement **lenses**. Each lens (action) brings its own analysis method and vocabulary via an `actions/<lens>.md` playbook plus a `research/<lens>/` reference set, loaded only when that lens runs. The first lens, `deepening`, implements Ousterhout's deep-module concept — finding shallow modules (interface nearly as complex as implementation) and proposing how to deepen them. The aim is **testability and AI/agent-navigability (AX)**: a deep module's small interface lets a reader — human or agent — grasp its purpose without traversing the whole import graph.

This finds existing friction — it does not plan new work, apply mechanical code-level tidyings, enforce rules on a diff, or review changes before a PR. Those are separate concerns handled by planning, tidying, rule-enforcement, and review tools respectively (see "Composition").

## Actions

| Argument | Action | What it does |
|----------|--------|-------------|
| *(empty)* | Defaults to `deepening` | Runs the deepening lens |
| `deepening` | **Deepening (Ousterhout)** | Shallow→deep module scan → HTML report → interview loop (with a Design-It-Twice branch for parallel interface exploration) → hand off an agreed candidate for planning. Full process: `actions/deepening.md` |

One lens per invocation — lenses don't chain implicitly. Read the action's playbook for its full process.

### Adding a lens

A new improvement lens (e.g. `coupling`, `testability`, dependency-direction review) is a pure ADD — never edit an existing lens's contract to add one (open for extension, closed for modification):

- `actions/<lens>.md` — the lens playbook (phases, gates, output shape)
- `research/<lens>/` — reference for that lens, loaded only when its action runs (per-action progressive disclosure)
- one row in the Actions table above

## What this skill does NOT do

- **Does not plan implementation** — produces candidates + agreed shape; a planning step plans the work
- **Does not enforce rules** — a rule-enforcement reviewer does that reactively on a diff
- **Does not apply mechanical tidyings** — code-level tidyings (rename, extract, inline) are a separate, smaller-grained concern
- **Does not review a diff** — pre-merge review tools do that
- **Does not write code** — discovery and design skill only
- **Does not brainstorm a rough problem** — this skill hunts architecture friction on its own lenses; open-ended "how could we approach X" divergence is a brainstorming concern

## Composition

Graceful degradation — where a named step below is not available in the consuming project, inline the equivalent work in this session instead of blocking on it.

| When | Then | How |
|------|------|-----|
| A debugging pass finds an architectural root cause | Run this skill's deepening lens | Structured deepening review of the affected module |
| A candidate shape is agreed | Hand off to a planning skill if the project has one; else summarize the agreed shape for planning | Consumes the `agreed-shape` entry from the candidate artifact (see `actions/deepening.md`) |
| During the interview loop | Maintain resolved project vocabulary | Invoke `/domain-driven-design:curate-language` when available in the current session; otherwise update an existing consumer-declared glossary in its own shape |
| Post-improvement | Review the implemented changes with the project's review tool | Standard diff review |

## Gotchas

Observed failure history — patterns that have actually bitten. Add here when a new one surfaces.

- **The durable candidate artifact is a per-project memory-tier file, never `${CLAUDE_PLUGIN_DATA}`.** That token does not substitute in skill markdown content (it is a hook/monitor/MCP path substitution only), and even resolved it points at a plugin-global dir that collides candidates across projects. The artifact resolves through the marketplace topic-docs convention (the plugin's topic-docs [binding](../../reference/topic-docs.md)) — memory tier, default `.work/<topic-slug>/`. A `${CLAUDE_PROJECT_DIR}/.claude/...` path is also wrong: `.claude/` generated output is reserved for observability, and an unignored artifact there leaks scan output into git.
- **Scan-agent claims are shipped only after Phase 1.5 reproduction.** Explore agents have a demonstrated error rate: a real run reported a service "registered but never composed — a bug in the seam" that one grep disproved (it *is* consumed, via a different consumer, with tests). Any candidate headed for a `Strong` badge and any runtime-bug / dead-code claim is reproduced against the actual code before it reaches the user-facing report — the report lends every claim its authority, so an unreproduced overstatement is cheap to make and expensive to reputation.
