---
name: devils-advocate
description: "Stress-test plans and proposals via systematic adversarial review — assumption extraction, evidence check, failure scenarios, operational gotchas — before implementation begins. Use for 'devil's advocate', 'stress test', 'poke holes', 'what could go wrong', new dependencies, infrastructure/CI/build changes, or any architecture decision with cross-module blast radius; not for code correctness bugs or pre-PR verification."
argument-hint: "[plan text or file path] — works from conversation context if no argument given"
user-invocable: true
disable-model-invocation: false
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Recent commits: !`git log --oneline -5 2>/dev/null || echo "no commits"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Plans fail for predictable reasons: unchecked assumptions, undiscovered bugs in dependencies, missing extensibility, no drift detection, no graceful degradation. This skill systematically finds these problems BEFORE implementation begins.

Not a rubber stamp. Find real issues that would cause rework, not generic warnings. Every finding must be backed by evidence — a specific bug number, doc reference, code path, or logical argument. "This might break" without evidence is not a finding.

## When to Use

**Proactively (autonomous invocation):**

- Before exiting plan mode on plans involving infrastructure, hooks, CI/CD, build config, or cross-cutting changes
- Before presenting architecture decisions that affect multiple projects
- Before proposing new conventions or enforcement mechanisms
- When a plan has 3+ implementation steps and touches mechanisms with undocumented behavior

**On request (user invocation):**

- `/planning:devils-advocate` — review the plan currently being discussed in conversation
- `/planning:devils-advocate <file-path>` — review a plan from a specific file
- `/planning:devils-advocate <inline text>` — review the provided text directly

## Input Resolution

1. If `$ARGUMENTS` contains a file path (ends in `.md`, `.txt`, or `.json`), read that file
2. If `$ARGUMENTS` contains inline text, use that as the plan
3. If `$ARGUMENTS` is empty, work from the current conversation context — identify the most recent plan, proposal, or design being discussed

## Analysis Process

Run up to 3 rounds. Stop early if a round produces no new critical or high findings.

### Round 1: Assumption Identification

Extract every assumption in the plan — explicit and implicit. Present as a table:

| # | Assumption | Explicit? | Category | Risk if wrong |
|---|-----------|-----------|----------|---------------|
| 1 | `transcript_path` is in all hook stdin | Yes | API contract | Hooks can't track state |
| 2 | Temp files survive session duration | Implicit | Platform | State lost mid-session |

**Categories**: API contract, platform behavior, performance, security, extensibility, dependency stability, cross-platform, convention compliance

### Round 2: Evidence Check

For each assumption, verify against evidence. This is the research-heavy round.

**Research depth — match to risk:**

- **High risk**: deep multi-source research — official docs, issue trackers, and web search (use the strongest research capability available: `/discovery:research` if installed, a research MCP server, or WebSearch/WebFetch)
- **Medium risk**: a targeted search or single authoritative doc fetch
- **Low risk**: codebase grep/read (no external research needed)

Check for:

- **Known bugs** affecting the plan's mechanisms (search the relevant issue trackers)
- **Undocumented behavior** that the plan relies on
- **Version-specific changes** that may have broken assumptions since training cutoff
- **Cross-platform issues** (Windows/Git Bash, macOS, Linux)
- **Conflicts with the consuming project's conventions** (check its `CLAUDE.md` and project rules)

Present findings:

| # | Assumption | Verified? | Evidence | Impact |
|---|-----------|-----------|----------|--------|
| 1 | `transcript_path` in stdin | YES | Official docs confirm base field | None — assumption holds |
| 2 | `if` field fires under skip-perms | NO | silently no-ops (known issue) | CRITICAL — use explicit guards |

### Round 3: Failure Scenarios and Mitigations

For each unverified or partially verified assumption, propose:

1. **Failure scenario**: What specifically breaks and how
2. **Blast radius**: What else is affected
3. **Mitigation**: How to design around it
4. **Graceful degradation**: What happens if the mitigation itself fails

Also check for concerns the plan doesn't address:

- **Extensibility**: What happens when new tools/languages/ecosystems are added?
- **Drift detection**: How will we know when this goes stale?
- **Configuration**: Are there hardcoded values that should be externalizable?
- **Testability**: How do we verify this works? Smoke tests? Integration tests?
- **Maintenance**: Who updates this when the ecosystem changes?
- **Encapsulation**: Is this in the right place? Could it be better organized?

### Round 4: Operational Gotchas / Failure-Mode Pitfalls

Rounds 1-3 are assumption-driven. Round 4 sweeps for OPERATIONAL traps the assumption-driven rounds miss — runtime failure modes, edge-case semantics, multi-source interactions, silent fallbacks, divergent contexts.

For each category, ask: *"What's the worst-case scenario? Does the plan handle it or admit it as a known limitation?"*

| Category | Probe questions |
|---|---|
| **Edge-case semantics** | Empty input → no-op or "set to empty"? Missing file → fallback or error? Partial state → graceful or corrupt? Default-of-default when nothing's defined? |
| **Multi-source interactions** | Composition order? Diamond inheritance (A→B and A→C, then merge)? Conflicting providers? Layer-skip semantics when one layer fully replaces? |
| **Silent failure modes** | Parse fail → silent fallback to default? Invalid input → coerced or rejected? Errors swallowed? Hooks silently no-op on platform mismatch? |
| **Divergent contexts** | CI vs local? Cloud (gitignored files invisible) vs interactive? Windows/Git Bash vs Unix? Per-user vs per-machine state? Worktree vs main? |
| **Mutable shared state** | Cache invalidation triggers? Race conditions on concurrent sessions? Mid-edit reload behavior? File-locking semantics? |
| **Lifecycle / migration** | Rename mechanism? Removal-deprecation pass? Stale references after partial upgrade? What happens if old + new coexist? |
| **Bypass / circumvent** | Can someone read past the contract? Skip the merger? Ignore the manifest? What if the contract isn't honored — silent miscompute or visible error? |
| **Path / resource resolution** | Relative paths interpreted where? Glob ambiguity? Plugin-cache boundary? Worktree shared state? Cross-platform path-separator handling? |
| **Schema drift** | Type changes between versions/layers? Contract changes? Version mismatches across producer/consumer? Type-coercion vs error policy? |
| **Ordering / sequencing** | Multiple valid orderings — which wins? Documented? Reproducible across runs? Stable under concurrent input? |

Findings use the same severity / failure-scenario / mitigation / residual-risk format as Round 3.

**When to run Round 4:** plans involving multi-layer composition (config layering, plugin extension points, hook chains, override mechanisms), or any plan whose blast radius spans multiple contexts (local + CI + cloud). Skip Round 4 for single-context single-mechanism plans where Round 3 already covers the failure surface.

## Output Format

### Risk Summary

| Severity | Count | Action |
|----------|-------|--------|
| CRITICAL | N | Must fix before proceeding |
| HIGH | N | Should fix; plan is fragile without |
| MEDIUM | N | Consider fixing; acceptable risk if documented |
| LOW | N | Note for future; no action needed now |

### Findings (by severity)

For each finding:

**[SEVERITY] Finding title**

- **Assumption**: What was assumed
- **Evidence**: What was found (with source — bug number, doc URL, code path)
- **Failure scenario**: What breaks
- **Mitigation**: How to fix
- **Residual risk**: What remains after mitigation

### Revised Plan Recommendations

If critical or high findings exist, present specific plan modifications:

- What to change and why
- What to add (new steps, new checks, new graceful degradation)
- What to remove (mechanisms that don't work)

### Suggested Next Steps

Based on findings, suggest relevant follow-up actions:

- Targeted research rounds (`/discovery:research` if installed, or the strongest research capability available) if critical assumptions remain unverified
- Filing deferred research or monitoring items in the project's work-item tracker (`/work-items:work-items` if installed)

## What This Skill Does NOT Do

- **Does not block execution** — it advises, the user decides
- **Does not replace code review** — it reviews plans, not code (use your code-review tooling for code)
- **Does not do exhaustive security analysis** — it finds design-level risks, not vulnerability scanning (use dedicated security tools for that)
- **Does not generate generic warnings** — every finding must have specific evidence. "This might break" without a bug number, doc reference, or logical argument is not acceptable

## Workflow position

Runs as the stress-test step between `/architect`'s plan formulation and user approval: ... → `/architect` → **stress-test (this skill)** → targeted research iteration if needed → user approval → execute.

For plans that don't warrant a full stress-test (single-file edits, simple config changes with well-understood behavior), prior research validation is sufficient. Use judgment — the trigger is complexity and blast radius, not every plan.
