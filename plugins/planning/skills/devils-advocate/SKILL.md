---
description: "Stress-test a plan or proposal adversarially before implementation: assumptions, evidence, failure scenarios, operational gotchas. Use when: 'devil's advocate', 'stress test', 'poke holes', 'what could go wrong', or before new dependencies, CI/build changes, or cross-module architecture. `incumbent` mode attacks the status quo: 'is there a better way now', 'should we still use X'. Not for code bugs or pre-PR verification."
argument-hint: "[deep|shallow] [incumbent [target]|<plan text or file path>]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: plan
  summary: Stress-test a plan or the incumbent approach adversarially
---

**Arguments.** `[deep|shallow] [incumbent [target]|<plan text or file path>]`. An optional leading
deep/shallow sets research depth; with no argument, work from conversation context.

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined:

- Current branch, `git branch --show-current`
- Recent commits, `git log --oneline -5`

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
body Bash calls, not pre-compute lines: a worktree-isolated session refuses a compound command that
contains git, and the pre-compute block runs as one. Record: the worktree skill's
[reference/gather-block.md](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/source-control/skills/worktree/reference/gather-block.md),
"The pre-compute block runs as one shell invocation".

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Find, before implementation, the problems that would cause rework: unchecked assumptions, bugs in
dependencies, missing extensibility, no drift detection, no graceful degradation. Not a rubber
stamp and no generic warnings: every finding is backed by evidence (a specific bug number, doc
reference, code path, or logical argument). "This might break" without evidence is not a finding.

`incumbent` mode applies the same discipline to the status quo. "We already use it" is evidence of
what is, never proof it still fits: name the problem the incumbent actually solves, survey
alternatives, and ask whether a better fit exists now, before a plan commits to keeping or
replacing it.

## Fresh-context requirement

Dispatch the stress-test to a fresh-context sub-agent in two cases:

- **Plan-review mode**, when the plan under review was produced in THIS context/session: the
  producing context shares the plan's blind spots and drifts toward approving its own work. When
  invoked on an artifact this context did not author (a file, a plan from another session, a
  diff), you are already the fresh pair of eyes. Proceed directly.
- **`incumbent` mode**, always: any read of the incumbent you already hold is a digest. The
  sub-agent invokes `/discovery:explore` via the Skill tool (if enabled, else explores directly)
  on the incumbent itself (Alternatives Sweep, Step 1).

The dispatch prompt carries only WHAT to investigate (the plan artifact, or the incumbent's identity
and location), never your conclusions: "here is the target; go look yourself," not "here is what I
found; confirm it." Where the verdict is high-stakes and correlated blind spots are the risk, prefer
a cross-vendor advisor **when one is enabled and set up** (for example the OpenAI Codex plugin, when
its documented surface can take this artifact, invoked per its own docs), with the fresh-context
same-vendor sub-agent as the stated fallback, never a route to a command that may not resolve (per
`docs/plugin-philosophy.md` "Fresh-eyes checkpoints" in the marketplace repository).

## When to Use

**Proactively (autonomous invocation):**

- Before exiting plan mode on plans involving infrastructure, hooks, CI/CD, build config, or
  cross-cutting changes
- Before presenting architecture decisions that affect multiple projects
- Before proposing new conventions or enforcement mechanisms
- When a plan has 3+ implementation steps and touches mechanisms with undocumented behavior

Skip single-file edits and simple config changes with well-understood behavior, where prior
research validation suffices. The trigger is complexity and blast radius, not every plan.

**On request (user invocation):**

- `/planning:devils-advocate`. Review the plan currently being discussed
- `/planning:devils-advocate <file-path>`. Review a plan from a file
- `/planning:devils-advocate <inline text>`. Review the provided text
- `/planning:devils-advocate incumbent <target>`. Stress-test the incumbent tool/approach against
  alternatives (target empty ⇒ take it from conversation context)
- `/planning:devils-advocate deep incumbent <target>`. Same, forcing the heaviest research tier;
  the depth token is recognized only as the leading token, so `incumbent deep <target>` folds
  "deep" into the target text

## Input Resolution

Parse `$ARGUMENTS` in this order:

1. **Depth token (optional).** If the first token is `deep` or `shallow`, consume it as the
   research-depth override (see "Research depth") and continue with the rest.
2. **Mode.** If the next token is `incumbent`, enter **`incumbent` mode**; the remainder identifies
   the incumbent (a tool, library, approach, or module), or is empty to take it from the
   conversation. Only this leading token selects the mode; the word elsewhere in a plan does not.
3. **Plan-review mode (default).** Otherwise: a remainder that is a file path (ends in `.md`,
   `.txt`, or `.json`) is read as the plan; inline text is the plan; empty means the most recent
   plan, proposal, or design in the conversation.

To review an inline plan whose text legitimately *begins* with `incumbent`, `deep`, or `shallow`,
pass it as a file path so the leading word is not consumed as a token.

**Interview answers (optional input).** When the caller supplies an interview ledger
(`<memory_dir>/<topic-slug>/interview-checklist.md`) or a Brief, read its `answered` register rows
and locked decisions before Round 1. A mitigation that would replace one is still a valid finding,
but it names the answer it displaces (the `Supersedes` bullet under "Findings"): the user made that
call and the plan may not change it silently.

### Research depth

Both modes default to **risk-scaled** research (Round 2's scale). A leading `deep` forces the
heaviest tier: route load-bearing evaluations to `/discovery:research` with its `deep` token,
invoked via the Skill tool, if enabled. `shallow` restricts to codebase read/grep with no external
research. Depth is per invocation, not a stored setting.

## Analysis Process

**Mode branch.** Plan-review mode runs Rounds 1–4. `incumbent` mode runs the **Alternatives Sweep**
instead (it reuses Round 2's evidence discipline and Round 3's mitigation / residual-risk format).

Stop early when a round produces no new critical or high findings, except Round 4, which runs
whenever its trigger matches regardless of how quiet Rounds 1-3 were.

### Round 1: Assumption Identification

Extract every assumption in the plan, explicit and implicit, as a table:

| # | Assumption | Explicit? | Category | Risk if wrong |
|---|-----------|-----------|----------|---------------|
| 1 | `transcript_path` is in all hook stdin | Yes | API contract | Hooks can't track state |
| 2 | Temp files survive session duration | Implicit | Platform | State lost mid-session |

**Categories**: API contract, platform behavior, performance, security, extensibility, dependency
stability, cross-platform, convention compliance

In plan-review mode, also check that the plan solves the Brief's `### Problem` and flag a goal that
drifts from it ([`${CLAUDE_PLUGIN_ROOT}/context/problem-framing.md`](../../context/problem-framing.md)).

### Round 2: Evidence Check

Verify each assumption against evidence; mark one you could not confirm as unconfirmed and say where
you looked. Match research depth to risk:

- **High risk**: deep multi-source research: official docs, issue trackers, and web search, with
  the strongest capability available (`/discovery:research` via the Skill tool if enabled, a
  research MCP server, or WebSearch/WebFetch)
- **Medium risk**: a targeted search or single authoritative doc fetch
- **Low risk**: codebase grep/read

Check for:

- **Known bugs** affecting the plan's mechanisms (search the relevant issue trackers)
- **Undocumented behavior** the plan relies on
- **Version-specific changes** that may have broken assumptions since training cutoff
- **Cross-platform issues** (Windows/Git Bash, macOS, Linux)
- **Conflicts with the consuming project's conventions**: `CLAUDE.md` is already in context; also
  read every rule file under `.claude/rules/`, path-scoped and unscoped alike, since neither
  reliably reaches a plan review's context on its own

| # | Assumption | Verified? | Evidence | Impact |
|---|-----------|-----------|----------|--------|
| 1 | `transcript_path` in stdin | YES | Official docs confirm base field | None. Assumption holds |
| 2 | `if` field fires under skip-perms | NO | silently no-ops (known issue) | CRITICAL. Use explicit guards |

**Incumbency-only support fails this check.** An assumption whose *only* backing is that the status
quo already relies on it ("we already use X", no requirement, benchmark, or doc behind the original
choice) is unverified. It flows to a Round 3 finding whose **Mitigation names the follow-up**:
`/planning:devils-advocate incumbent <target>`. Suggest it; never auto-run it (one mode per
invocation). An assumption also backed by a requirement, benchmark, or doc is verified on that
evidence.

### Round 3: Failure Scenarios and Mitigations

For each unverified or partially verified assumption:

1. **Failure scenario**: what specifically breaks and how
2. **Blast radius**: what else is affected
3. **Mitigation**: how to design around it
4. **Graceful degradation**: what happens if the mitigation itself fails

Also check concerns the plan doesn't address:

- **Extensibility**: what happens when new tools/languages/ecosystems are added?
- **Drift detection**: how will we know when this goes stale?
- **Configuration**: hardcoded values that should be externalizable?
- **Testability**: how do we verify this works? Smoke tests? Integration tests?
- **Maintenance**: who updates this when the ecosystem changes?
- **Encapsulation**: is this in the right place?

### Round 4: Operational Gotchas / Failure-Mode Pitfalls

Sweep for operational traps the assumption-driven rounds miss. For each category, ask: *"What's the
worst-case scenario? Does the plan handle it or admit it as a known limitation?"*

| Category | Probe questions |
|---|---|
| **Edge-case semantics** | Empty input → no-op or "set to empty"? Missing file → fallback or error? Partial state → graceful or corrupt? Default-of-default when nothing's defined? |
| **Multi-source interactions** | Composition order? Diamond inheritance (A→B and A→C, then merge)? Conflicting providers? Layer-skip semantics when one layer fully replaces? |
| **Silent failure modes** | Parse fail → silent fallback to default? Invalid input → coerced or rejected? Errors swallowed? Hooks silently no-op on platform mismatch? |
| **Divergent contexts** | CI vs local? Cloud (gitignored files invisible) vs interactive? Windows/Git Bash vs Unix? Per-user vs per-machine state? Worktree vs main? |
| **Mutable shared state** | Cache invalidation triggers? Race conditions on concurrent sessions? Mid-edit reload behavior? File-locking semantics? |
| **Lifecycle / migration** | Rename mechanism? Removal-deprecation pass? Stale references after partial upgrade? What happens if old + new coexist? |
| **Bypass / circumvent** | Can someone read past the contract? Skip the merger? Ignore the manifest? What if the contract isn't honored. Silent miscompute or visible error? |
| **Path / resource resolution** | Relative paths interpreted where? Glob ambiguity? Plugin-cache boundary? Worktree shared state? Cross-platform path-separator handling? |
| **Schema drift** | Type changes between versions/layers? Contract changes? Version mismatches across producer/consumer? Type-coercion vs error policy? |
| **Ordering / sequencing** | Multiple valid orderings. Which wins? Documented? Reproducible across runs? Stable under concurrent input? |
| **Re-execution** | Started again straight after a clean finish, or while a previous start is still going: same result, or doubled work (two rows, two charges, two messages)? Stopped between any two of its writes: does the next start pick up, or trip over what was left? Mitigation: open every run with a reconciliation step that reads what already exists and acts only on the difference. Examples: upsert on a natural key instead of a blind insert; write to a temp path, then rename; a per-item done-marker the next run checks; build the to-do list from the destination's current contents, not a saved cursor. |

Findings use Round 3's severity / failure-scenario / mitigation / residual-risk format.

**When to run Round 4:** plans involving multi-layer composition (config layering, plugin extension
points, hook chains, override mechanisms), or whose blast radius spans multiple contexts (local +
CI + cloud). Skip it for single-context single-mechanism plans Round 3 already covers, except the
Re-execution row: run that on any plan with a step that writes state and can run again (a scheduled
job, a retry, a resumed run).

### Alternatives Sweep (`incumbent` mode)

Every finding is backed by a specific bug number, doc reference, code path, or concrete logical
argument, never training-data recall.

1. **Explore the incumbent first-hand.** The fresh sub-agent (see Fresh-context requirement)
   invokes `/discovery:explore` via the Skill tool on the incumbent: what it is, where it is used,
   what it is coupled to, and any recorded reason it was chosen. It receives the incumbent's
   identity, never a parent conclusion about it.
2. **Name the actual problem.** State what the incumbent solves, the real requirements, present and
   plausible-future, before any alternative is on the table. Do not let the incumbent's shape
   define the problem.
3. **Survey the field.** Judge alternatives against those requirements on the preference ladder:
   **native** (what the platform / language / framework provides) > **official / authoritative** >
   **vetted third-party** (well-maintained, known, safe, secure); an earlier rung wins when it
   covers the requirements. Price each dependency's coupling: abandonment, a pricing pivot, a
   license change, security posture, exit cost. The full selection discipline lives in
   `/discipline:pick-for-the-problem` (apply it if enabled); this baseline is enough to run the
   sweep without it. The seam between the two: that corrector is the light in-session nudge when
   selection drift surfaces mid-conversation; this sweep is the formal, dispatched,
   verdict-producing review to run before a plan commits to the incumbent.
4. **"Is there a better way now?" Evidence, not memory.** Scale research to risk (Round 2) or the
   depth token; route load-bearing evaluations to `/discovery:research` (with its `deep` token for
   the heaviest tier), invoked via the Skill tool, if enabled. Look especially for what changed
   since the incumbent was chosen: a new native capability, a shifted dependency, a since-published
   better-fit option.
5. **Verdict per candidate.** One of:
   - **KEEP**. Re-derived from the problem and still the best fit; never switch for switching's
     sake. An incumbent that audits clean is a clean finding. Say so.
   - **MIGRATE**. A better-fit alternative exists; state the coupling price and the migration cost,
     not just the upside.
   - **RESEARCH**. The evaluation is load-bearing and unverified; route it (step 4), never a
     verdict from recall.

   Findings use Round 3's severity / failure-scenario / mitigation / residual-risk format.

**Scope guard.** Pre-implementation decision support (should the plan adopt or keep X versus an
alternative), not a post-hoc audit of a running system's health or correctness.

## Output Format

**In `incumbent` mode**, the per-candidate **KEEP / MIGRATE / RESEARCH verdict** is the headline.
The Risk Summary and finding bullets still apply to the risks the sweep surfaces, with
**Assumption** read as the claim under test (e.g. "the incumbent still fits" or "alternative X is better-maintained") and **Failure
scenario** as the cost of the wrong call (keeping a worse-fit incumbent, or paying an unpriced
migration).

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
- **Evidence**: What was found (with source. Bug number, doc URL, code path)
- **Failure scenario**: What breaks
- **Mitigation**: How to fix
- **Residual risk**: What remains after mitigation
- **Supersedes**: interview Q<N> (<displaced answer>) (only when the mitigation replaces a user answer)
- **New external effect**: <remote write, irreversible action, or externally visible artifact> (only when the mitigation adds one)

### Revised Plan Recommendations

If critical or high findings exist, present specific plan modifications:

- What to change and why
- What to add (new steps, new checks, new graceful degradation)
- What to remove (mechanisms that don't work)

In `incumbent` mode, this is the KEEP / MIGRATE / RESEARCH verdict with its coupling price and, for
a MIGRATE, the migration cost.

### Suggested Next Steps

Suggest the follow-ups the findings call for:

- Verifying the changes end-to-end (`/verification:confirm` if enabled) if code changes were
  involved
- Targeted research (`/discovery:research` if enabled, or the strongest research capability
  available) if critical assumptions remain unverified
- The Alternatives Sweep on any incumbent a Round 2 finding flagged as supported only by
  incumbency (the finding's Mitigation names the invocation)
- Filing deferred research or monitoring items in the project's work-item tracker
  (`/work-items:track` if enabled)

## What This Skill Does NOT Do

- **Does not block execution**. It advises, the user decides
- **Does not replace code review**. It reviews plans, not code (use your code-review tooling for
  code)
- **Does not do exhaustive security analysis**. Design-level risks, not vulnerability scanning
  (use dedicated security tools for that)
- **Does not generate generic warnings** (see Purpose)
- **Does not audit a running system's health**. `incumbent` mode is a pre-implementation
  keep-or-replace decision, not a runtime performance / correctness audit

## Next

/planning:plan takes the verified findings back into the plan before the user approves it.

## Workflow position

Runs between `/planning:plan`'s plan formulation and user approval: ... → `/planning:plan` →
**stress-test (this skill)** → targeted research iteration if needed → user approval → execute.
