---
description: "Scan an existing codebase for module-level friction and architecture improvement opportunities — shallow modules, seam leaks, locality gaps — present candidates as an HTML report, interview on the selected candidate with a Design-It-Twice branch that designs the interface several radically different ways in parallel, and hand off the agreed shape for planning. Use when: 'improve architecture', 'find deepening opportunities', 'shallow modules', 'architecture improvement', 'Ousterhout deepening', 'design it twice', 'compare alternative interfaces', 'make code more testable', 'make code more AI-navigable', 'find refactoring opportunities', 'architecture scan', 'codebase friction', 'module seams', 'locality'. Skip when: a cross-dimension or evidence-driven improvement ask — a general 'what should we improve', 'highest-impact improvement', or 'find improvements' across code, product, process, or ops — routes to /improvement:find (this skill is the single-lens architecture-depth pass); also skip for mechanical code-level tidyings, reviewing a diff before merge, enforcing architecture rules on a change, or root-cause debugging a specific failure."
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
Recent commits: !`git log --oneline -20 2>/dev/null || echo "no commits"`
Working tree status (empty = clean): !`{ git status --porcelain 2>/dev/null || echo "(git status unavailable)"; } | head -10`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Improvement is distinct from review and planning. Review evaluates a DIFF against criteria (reactive). Planning designs NEW work (forward-looking). This skill scans EXISTING code for friction and proposes candidates for improvement (proactive).

The scan-present-pick process generalizes across improvement **lenses**. Each lens (action) brings its own analysis method and vocabulary via an `actions/<lens>.md` playbook plus a `research/<lens>/` reference set, loaded only when that lens runs. The first lens, `deepening`, implements Ousterhout's deep-module concept: finding shallow modules (interface nearly as complex as implementation) and proposing how to deepen them. The aim is **testability and AI/agent-navigability (AX)**: a deep module's small interface lets a reader, human or agent, grasp its purpose without traversing the whole import graph.

This finds existing friction. It does not plan new work, apply mechanical code-level tidyings, enforce rules on a diff, or review changes before a PR. Those are separate concerns handled by planning, tidying, rule-enforcement, and review tools respectively (see "Composition").

## Actions

| Argument | Action | What it does |
|----------|--------|-------------|
| *(empty)* | Defaults to `deepening` | Runs the deepening lens |
| `deepening` | **Deepening (Ousterhout)** | Shallow→deep module scan → HTML report → interview loop (with a Design-It-Twice branch for parallel interface exploration) → hand off an agreed candidate for planning. Full process: `actions/deepening.md` |

One lens per invocation. Lenses don't chain implicitly. Read the action's playbook for its full process.

### Adding a lens

A new improvement lens (e.g. `coupling`, `testability`, dependency-direction review) is a pure ADD. Never edit an existing lens's contract to add one (open for extension, closed for modification):

- `actions/<lens>.md`. The lens playbook (phases, gates, output shape)
- `research/<lens>/`. Reference for that lens, loaded only when its action runs (per-action progressive disclosure)
- one row in the Actions table above, plus one row per new reference file in the reference index below

## Reference index. Load on demand

| File | Load when |
|------|-----------|
| [research/deepening/scan-briefing.md](research/deepening/scan-briefing.md) | Before briefing the Phase 1 scan subagents. It is the canonical prompt (vocabulary primer, friction checklist, dependency categories, the two badge-acceptance heuristics, per-candidate return schema), so scan quality does not vary run-to-run |
| [research/deepening/vocabulary.md](research/deepening/vocabulary.md) | Applying the deletion test, or naming anything in a candidate, report, or interview turn. The terms are used exactly, not paraphrased |
| [research/deepening/dependencies.md](research/deepening/dependencies.md) | Classifying a candidate's dependencies, where the category chooses the testing strategy |
| [research/deepening/html-report.md](research/deepening/html-report.md) | Writing the HTML report: scaffold, diagram patterns, and the escaping and no-remote-runtime rules it must hold to |
| [research/deepening/interface-design.md](research/deepening/interface-design.md) | Entering the Design-It-Twice branch, or a single proposed shape is not converging in the interview loop |

## What this skill does NOT do

- **Does not plan implementation.** Produces candidates + agreed shape; a planning step plans the work
- **Does not enforce rules.** A rule-enforcement reviewer does that reactively on a diff
- **Does not apply mechanical tidyings.** Code-level tidyings (rename, extract, inline) are a separate, smaller-grained concern
- **Does not review a diff.** Pre-merge review tools do that
- **Does not write code.** Discovery and design skill only
- **Does not brainstorm a rough problem.** This skill hunts architecture friction on its own lenses; open-ended "how could we approach X" divergence is a brainstorming concern

## Composition

Graceful degradation: where a named step below is not available in the consuming project, inline the equivalent work in this session instead of blocking on it.

| When | Then | How |
|------|------|-----|
| A debugging pass finds an architectural root cause | Run this skill's deepening lens | Structured deepening review of the affected module |
| A candidate shape is agreed | Hand off to a planning skill if the project has one; else summarize the agreed shape for planning | Consumes the `agreed-shape` entry from the candidate artifact (see `actions/deepening.md`) |
| During the interview loop | Maintain resolved project vocabulary | Invoke `/domain-driven-design:curate-language` via the Skill tool when available in the current session; otherwise update an existing consumer-declared glossary in its own shape |
| Post-improvement | Review the implemented changes with the project's review tool | Standard diff review |

## Gotchas

Observed failure history: patterns that have actually bitten. Add here when a new one surfaces.

- **The durable candidate artifact is a per-project memory-tier file, never `${CLAUDE_PLUGIN_DATA}`.** Even resolved it points at a plugin-global dir with no project dimension that collides candidates across projects, and uninstalling from the last remaining scope deletes the directory. The documented use is deps/caches/generated code, not per-project artifacts. The artifact resolves through the marketplace topic-docs convention (the plugin's topic-docs [binding](../../reference/topic-docs.md)): memory tier, default `.work/<topic-slug>/`. A `${CLAUDE_PROJECT_DIR}/.claude/...` path is also wrong: `.claude/` generated output is reserved for observability, and an unignored artifact there leaks scan output into git.
- **Scan-agent claims are shipped only after Phase 1.5 reproduction.** Explore agents have a demonstrated error rate: a real run reported a service "registered but never composed — a bug in the seam" that one grep disproved (it *is* consumed, via a different consumer, with tests). Any candidate headed for a `Strong` badge and any runtime-bug / dead-code claim is reproduced against the actual code before it reaches the user-facing report. The report lends every claim its authority, so an unreproduced overstatement is cheap to make and expensive to reputation.
