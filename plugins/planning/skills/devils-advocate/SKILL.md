---
name: devils-advocate
description: "Stress-test plans and proposals via systematic adversarial review — assumption extraction, evidence check, failure scenarios, operational gotchas — before implementation begins. Use for 'devil's advocate', 'stress test', 'poke holes', 'what could go wrong', new dependencies, infrastructure/CI/build changes, or any architecture decision with cross-module blast radius. An `incumbent` mode turns the same adversarial lens on the status quo — 'is there a better way now', 'should we still use X', 'reconsider the current approach', 'is the incumbent still the right choice' — surveying alternatives before a plan commits to keeping an existing tool or approach. Not for code correctness bugs or pre-PR verification."
argument-hint: "[incumbent [target]] or [plan text or file path] — an optional leading deep/shallow sets research depth; works from conversation context if no argument given"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Recent commits: !`git log --oneline -5 2>/dev/null || echo "no commits"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Plans fail for predictable reasons: unchecked assumptions, undiscovered bugs in dependencies, missing extensibility, no drift detection, no graceful degradation. This skill systematically finds these problems BEFORE implementation begins.

Not a rubber stamp. Find real issues that would cause rework, not generic warnings. Every finding must be backed by evidence — a specific bug number, doc reference, code path, or logical argument. "This might break" without evidence is not a finding.

The same discipline runs against the status quo. An incumbent tool, library, or approach already in place is a decision too, and "we already use it" is evidence of what is, never proof it still fits. The `incumbent` mode stress-tests that choice — naming the problem the incumbent actually solves, surveying alternatives, and asking whether a better fit exists now — before a plan commits to keeping or replacing it.

## Fresh-context requirement

This stress-test runs from a fresh pair of eyes, and dispatches to a fresh-context sub-agent in two cases:

- **Plan-review mode** — if the plan under review was produced in THIS context/session, the producing context shares the assumptions that created the plan's blind spots and drifts toward approving its own work; dispatch the stress-test to a fresh-context sub-agent. When you were invoked on an artifact this context did not author (a file, a plan from another session, a diff), you are already the fresh pair of eyes — proceed directly.
- **`incumbent` mode** — always dispatch. The incumbent lives in the current codebase, so any read of it you already hold is a digest; a first-hand exploration is what forms an independent view. The sub-agent runs `/discovery:explore` (if installed, else explores directly) on the incumbent itself (Alternatives Sweep, Step 1).

In both cases the dispatch prompt carries only WHAT to investigate — the plan artifact, or the incumbent's identity and where it lives — never your conclusions about it: "here is the target; go look yourself," not "here is what I found; confirm it." A sub-agent handed the parent's verdict inherits the parent's blind spot. Where the verdict is high-stakes and correlated blind spots are the risk, prefer a cross-vendor advisor for that fresh pair of eyes **when one is installed** — e.g. the OpenAI Codex plugin, when its documented surface can take this artifact, invoked per its own docs — with the fresh-context same-vendor sub-agent as the stated fallback, never a route to a command that may not resolve.

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
- `/planning:devils-advocate incumbent <target>` — stress-test the incumbent tool/approach against alternatives (target empty ⇒ take it from conversation context)
- `/planning:devils-advocate deep incumbent <target>` — same, forcing the heaviest research tier; the depth token (`deep`/`shallow`) is recognized only as the leading token, so `incumbent deep <target>` would fold "deep" into the target text

## Input Resolution

Parse `$ARGUMENTS` in this order:

1. **Depth token (optional).** If the first token is `deep` or `shallow`, consume it as the research-depth override (see "Research depth" below) and continue with the rest.
2. **Mode.** If the next token is `incumbent`, enter **`incumbent` mode** (incumbent-target); the remainder identifies the incumbent — a tool, library, approach, or module — or is empty to take the incumbent from the current conversation. The keyword selects the mode only as this leading token; a plan that merely contains the word elsewhere is not a mode switch.
3. **Plan-review mode (default).** Otherwise: if the remainder is a file path (ends in `.md`, `.txt`, or `.json`), read that file; if it is inline text, use it as the plan; if empty, work from the current conversation context — the most recent plan, proposal, or design being discussed.

To review an inline plan whose text legitimately *begins* with `incumbent`, `deep`, or `shallow`, pass it as a file path so the leading word is not consumed as a mode or depth token.

### Research depth

Both modes default to **risk-scaled** research (Round 2's high/medium/low scale). A leading `deep` token forces the heaviest tier — route load-bearing evaluations to `/discovery:research-deep` if installed; `shallow` restricts to codebase read/grep with no external research. Depth is a per-invocation choice, not a stored setting.

## Analysis Process

**Mode branch.** In plan-review mode, run Rounds 1–4 below. In `incumbent` mode, run the **Alternatives Sweep** instead (it reuses Round 2's evidence discipline and Round 3's mitigation / residual-risk format); Rounds 1–4 do not apply.

Run the rounds below (up to 4). Stop early if a round produces no new critical or high findings — except Round 4, which runs whenever its multi-layer / multi-context trigger matches, regardless of how quiet Rounds 1-3 were.

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

**Incumbency-only support fails this check.** An assumption whose *only* backing is that the status quo already relies on the thing — "we already use X", with no requirement, benchmark, or doc behind the original choice — is unverified by definition (per Purpose: incumbency is evidence of what is, never proof it still fits). It flows to a Round 3 finding whose **Mitigation names the follow-up**: `/planning:devils-advocate incumbent <target>` — the Alternatives Sweep on that incumbent. Suggest it; never auto-run it — scope stays one mode per invocation. An assumption *also* backed by a requirement, benchmark, or doc is verified on that evidence and does not trigger this.

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

### Alternatives Sweep (`incumbent` mode)

Runs in place of Rounds 1–4 when `incumbent` mode is selected. It inherits the evidence mandate — every finding is backed by a specific bug number, doc reference, code path, or concrete logical argument, never training-data recall.

1. **Explore the incumbent first-hand.** Dispatch the fresh sub-agent (see Fresh-context requirement) to run `/discovery:explore` on the incumbent — what it is, where it is used, what it is coupled to, and any recorded reason it was chosen. The sub-agent forms its own read; it receives the incumbent's identity, never a parent conclusion about it.
2. **Name the actual problem.** State what the incumbent solves — the real requirements, present and plausible-future — before any alternative is on the table. Do not let the incumbent's shape define the problem.
3. **Survey the field.** Judge candidate alternatives against those requirements, walking the preference ladder — **native** (what the platform / language / framework already provides) > **official / authoritative** > **vetted third-party** (well-maintained, known, safe, secure) — where an earlier rung wins when it covers the requirements. Price each dependency's coupling: abandonment, a pricing pivot, a license change, security posture, exit cost. The full selection discipline lives in `/re-anchor:pick-for-the-problem` (apply it if installed); this baseline is enough to run the sweep without it. The seam between the two: that corrector is the light in-session nudge when selection drift surfaces mid-conversation; this sweep is the formal, dispatched, verdict-producing review to run before a plan commits to the incumbent.
4. **"Is there a better way now?" — evidence, not memory.** The research-heavy step; scale to risk (Round 2) or the depth token. Route load-bearing evaluations to `/discovery:research` (or `/discovery:research-deep`) if installed — a tool's maintenance, security, licensing, and native-alternative landscape drift constantly since the training cutoff. Look especially for what changed since the incumbent was chosen: a new native capability, a shifted dependency, a since-published better-fit option.
5. **Verdict per candidate.** One of:
   - **KEEP** — re-derived from the problem and still the best fit; the duty is to re-derive, not to switch for switching's sake. An incumbent that audits clean is a clean finding — say so.
   - **MIGRATE** — a better-fit alternative exists; state the coupling price and the migration cost, not just the upside.
   - **RESEARCH** — the evaluation is load-bearing and unverified; route it (step 4), never a verdict from recall.

   Findings use the same severity / failure-scenario / mitigation / residual-risk format as Round 3.

**Scope guard.** This is pre-implementation decision support — should the plan adopt or keep X versus an alternative — not a post-hoc audit of a running system's health or correctness.

## Output Format

**In `incumbent` mode**, the per-candidate **KEEP / MIGRATE / RESEARCH verdict** is the headline. The Risk Summary and finding bullets below still apply to the risks the sweep surfaces, with two field re-readings: **Assumption** becomes the claim under test (e.g. "the incumbent still fits" or "alternative X is better-maintained"), and **Failure scenario** becomes the cost of the wrong call (keeping a worse-fit incumbent, or paying an unpriced migration).

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

In `incumbent` mode, this is the KEEP / MIGRATE / RESEARCH verdict with its coupling price and, for a MIGRATE, the migration cost — not just the upside.

### Suggested Next Steps

Based on findings, suggest relevant follow-up actions:

- Verifying the changes end-to-end (`/verification:confirm` if installed) if code changes were involved
- Targeted research rounds (`/discovery:research` if installed, or the strongest research capability available) if critical assumptions remain unverified
- Running the Alternatives Sweep on any incumbent a Round 2 finding flagged as supported only by incumbency — the finding's Mitigation already names the invocation
- Filing deferred research or monitoring items in the project's work-item tracker (`/work-items:track` if installed)

## What This Skill Does NOT Do

- **Does not block execution** — it advises, the user decides
- **Does not replace code review** — it reviews plans, not code (use your code-review tooling for code)
- **Does not do exhaustive security analysis** — it finds design-level risks, not vulnerability scanning (use dedicated security tools for that)
- **Does not generate generic warnings** — every finding must have specific evidence. "This might break" without a bug number, doc reference, or logical argument is not acceptable
- **Does not audit a running system's health** — `incumbent` mode is a pre-implementation keep-or-replace decision against alternatives, not a runtime performance / correctness audit of production

## Workflow position

Runs as the stress-test step between `/planning:plan`'s plan formulation and user approval: ... → `/planning:plan` → **stress-test (this skill)** → targeted research iteration if needed → user approval → execute.

For plans that don't warrant a full stress-test (single-file edits, simple config changes with well-understood behavior), prior research validation is sufficient. Use judgment — the trigger is complexity and blast radius, not every plan.
