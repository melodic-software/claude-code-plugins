---
name: plan
description: "Produce structured implementation plans with goal, approach, test strategy, blast-radius assessment, parallelism analysis, and a user approval gate before any code is written — persisting PLAN.md for fresh-session handoff. Use for 'plan this', 'architect this', 'how should we implement', 'implementation plan', proactively before executing without a formalized plan, or 'review this plan' to audit an existing plan's completeness."
argument-hint: "[task description, 'review', or 'close-out'] (e.g., /planning:plan add caching to query handlers, /planning:plan review, /planning:plan close-out)"
user-invocable: true
disable-model-invocation: false
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Recent commits: !`git log --oneline -5 2>/dev/null || echo "no commits"`
Working tree status: !`git status --porcelain 2>/dev/null | head -10 || echo "clean"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Plans fail when they skip rationale, ignore blast radius, or rush past approval gates. This skill structures the planning step so that every implementation starts with a clear design — with evidence, test strategy, and user sign-off — before a single line of code is written.

This is **not** Claude Code's built-in plan mode (`shift+tab`). That is a *permission mode* — read-only exploration. This skill is a *planning discipline* — the intellectual work of designing an approach, assessing risks, and getting approval. The two complement each other: use plan mode for safe exploration during planning, and this skill for the structured process around it.

This skill takes the outputs of the earlier stages — exploration (local understanding), research (external evidence), `/design` (types, contracts, module boundaries, package topology) — and produces a plan the user approves before execution begins.

**Philosophy**: a 2-minute plan prevents a 20-minute rework cycle. The depth of planning should match the blast radius — a one-file fix gets a brief plan; a cross-cutting architecture change gets a full plan with stress-testing and research-iterate loops.

## Emit checklist

For multi-step planning sessions (almost always — Steps 1-5 of this skill), copy `templates/checklist.md` into the topic's memory slice as `<memory_dir>/<topic-slug>/plan-checklist.md` (default `.work/`). Tick each `- [ ]` as the corresponding step completes. Step 3 (Plan stress-test via fresh-context sub-agent) and Step 5 (Present for approval) are non-negotiable ticks — stress-test before presenting, always.

**Skip when:** mid-flight `review` replan only — append a dated scope-change note and revise the PLAN phases instead; do not spawn a second checklist file.

For **non-trivial / multi-layer** plans, also walk the design-default axes during Step 2 — configurability, extension points, observability, testability, magic-literal hygiene, type-collaboration shape — against the consuming project's own review conventions when it declares them.

## Action Router

Parse `$ARGUMENTS` to determine the action:

| Argument | Action | Use case |
|----------|--------|----------|
| *(empty)* | **Smart default** | Detect context: if a plan exists in conversation, offer to finalize/review; if exploration and research are done, start planning; otherwise suggest prerequisites |
| `<task description>` | **Full planning** | Run the complete planning process for the described task |
| `review` | **Plan review** | Critique an existing plan for completeness, feasibility, and alignment with the project's conventions |
| `close-out` | **Close-out** | Run the PR-time close-out procedure (below) for an already-approved plan: publish PLAN.md to the PR, graduate durable outcomes through the knowledge-vault seam, prune the contract slice |

## Planning Process

### Step 1: Prerequisite Check

Before the prerequisite checklist runs, apply a pre-planning discipline checklist. If the `andrej-karpathy-skills` plugin is installed, invoke `/andrej-karpathy-skills:karpathy-guidelines` to prime four behavioral rules — think-before-code, simplicity-first, surgical-changes, goal-driven-execution. If the plugin is absent, fall back gracefully: the consuming project's own rules plus this skill's Step 2 plan-formulation and Step 3 plan stress-test discipline cover the same ground — proceed without prompting.

Before planning, verify the knowledge base is ready:

- **Is the effort coherent enough to plan?** — If the work is too big to hold at once AND still too foggy to phrase as sharp decisions (missing questions you can't yet state, not just unanswered ones), `/planning:plan` is premature — a plan needs a coherent target. Guide the user to `/planning:wayfind` first (it charts the fog as a decision map and works it down until a destination coheres); recommend, never auto-switch. Skip when the effort is already scoped and the open items are answerable questions
- **Is product intent clear?** — For product-driven feature work (new user-facing surface, business-driven change, cross-team initiative), check that the topic's contract slice holds `PRD.md` (`<contract_dir>/<topic-slug>/PRD.md`, default `docs/topics/`; the memory slice under `contract_tier: local`) OR that problem/users/success-metrics are already crisp in conversation. If fuzzy, suggest running `/prd` first. Skip this check for engineering-internal work (refactors, infra, hooks, conventions, bug fixes) — `/prd` does not apply
- **Has exploration been done?** — Check if the conversation contains exploration findings for the relevant area. If not, suggest running the exploration capability first (`/discovery:explore` if installed). Don't plan in the dark
- **Has research been done?** — Check if external research has been completed for technical claims the plan will rely on. If not, suggest running the research capability first (`/discovery:research` if installed). Plans built on assumptions instead of evidence lead to rework
- **Has `/design` been done? (blocking gate)** — Classify design significance before planning:

| Tier | Signals | Requirement |
|------|---------|-------------|
| **A — design-significant** | New types/contracts, new module or library, package topology change, cross-module integration, data model change, multi-tenant posture | **Blocking:** full or light `/design` + its handoff gate (`design-threads.md` all RESOLVED / directional / TAGGED-DEFERRED) |
| **B — light design** | 2–5 files, one new type, localized contract tweak | **Blocking:** minimal `type-inventory.md` OR `design/design-resolution.md` documenting early-exit with type sketch |
| **C — no design** | Single-file bugfix, config/doc/markdown, rename, hook text, pure test addition | **Blocking:** `design/design-resolution.md` with `outcome: early-exit` + reason (gate always evaluated) |

Check the topic's contract slice `<contract_dir>/<topic-slug>/design/` (default `docs/topics/`; the memory slice under `contract_tier: local`) for design artifacts OR `design-resolution.md` at that path. If Tier A/B requirements are unmet, **stop** — offer `/design` or document the early-exit artifact. The user may override via `AskUserQuestion` only when they explicitly accept skipping design exploration. `/planning:plan` consumes design artifacts — do not re-derive design inline when design-significant.

- **Is the scope clear?** — If the task is ambiguous, ask clarifying questions before planning. A plan for "improve performance" is useless; a plan for "add a cache to the GetOrderById query handler" is actionable. When 2–4 discrete options exist (e.g. cache scope, eviction policy, key derivation), use `AskUserQuestion`; for open-ended ambiguity use prose, one question at a time
- **Open Decisions surfaced BEFORE plan body** — scan the resume prompt + conversation context + Brief for unresolved decisions (scope cuts, technique choices, ordering, exclusions) that the downstream plan body would otherwise lock inline. Surface them as a numbered "Open Decisions" block with research-backed recommendations + trade-offs per decision; resolve via `AskUserQuestion` (≤4 decisions) or single-prompt prose (≥5). Resolving once up front is cheaper than iterating during Step 5 approval

If prerequisites are missing, state what's needed and offer to run the prerequisite skill. Don't silently skip this step. Note that the `/prd` check is **additive**, not blocking — proceed if the user has product intent locked elsewhere or if the work is engineering-internal.

### Step 2: Formulate the Plan

#### Ground in consumer standards (first formulation input)

Before formulating, resolve the consumer's standards and load what this task touches — plans are built to the criteria they will be reviewed against:

- **Resolve the index** by jumping to the "Resolution ladder" section of the plugin's contract binding [`${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md) — the ladder (including the absent-index inference, offer-to-persist, and ask-once behavior) lives there and is not restated in this skill. Zero unprompted writes, ever.
- **Match** the task's surfaces (ecosystems touched, cross-cutting concerns) against the index rows' `Applies when` clues.
- **Pull selectively** — only matched files, and within a matched file only the sections relevant to this task. Never re-pull ambient content (auto-loaded `CLAUDE.md`, fired `.claude/rules` directives). Post-compaction context and a new task both count as NOT ambient — re-resolve per task; a second task in the same session grounds its own surfaces.
- **Depth rides the plan-scale table below** — a trivial plan takes no standards fetch beyond ambient context; larger scales ground the surfaces they touch. There is no grounding flag; scale governs cost.
- **Name provenance** when a personal-layer rule (a `*.local.md` overlay or the user-global layer) materially shapes the plan.
- **Broken index row** → surface it and offer the fix (Boy Scout) — never silent. **Always compare** the index's `standards-contract` frontmatter to the binding's own version when resolving; on any mismatch, degrade per the binding's tolerant-reader rule AND report the skew in the produced plan (older: best-effort + "index at vX, contract at vY — re-run setup"; newer: best-effort + "update the plugin", no migration offer).
- The produced plan **cites the standards sections loaded** for the surfaces it touches — the template's "Standards grounding" element — or states why grounding was skipped (scale tier).

Produce a structured plan using the template in [context/plan-template.md](context/plan-template.md). The template covers:

- **Goal**: what we're trying to achieve and why
- **Approach**: the specific steps, in order
- **Test strategy**: how we'll verify the changes work — **invoke `/tdd:principles` (if installed)** when formulating this section for authoritative guidance on what to test, which testing style fits, and when to mock; otherwise apply standard test-design judgment. TDD is the default approach — the test strategy should specify Red-Green-Refactor unless genuinely impractical
- **Files affected**: what gets created, modified, or deleted
- **Alternatives considered**: what was rejected and why
- **Risks and mitigations**: what could go wrong

Scale the plan to the task:

| Task scale | Plan depth |
|-----------|-----------|
| Trivial (1 file, well-understood) | 3-5 bullet points |
| Small (2-5 files, clear scope) | Brief plan — goal, steps, test strategy |
| Medium (5-15 files, some unknowns) | Full plan with alternatives and risks |
| Large (cross-cutting, architectural) | Full plan + stress-test + research-iterate |

Per-scale calibration examples live in [context/plan-template.md](context/plan-template.md) "Choosing the Right Scale".

**Tracker-write phases:** when any phase ends in creating a work item (e.g. `gh issue create`), the plan body MUST follow the shape in [context/plan-template.md](context/plan-template.md) "Phase-entry checks for tracker writes" — search-before-create as the first work item, explicit pivot path for the match case, search outcome captured in the phase Sanity Check.

**Pre-flight consumer check** — when a phase migrates a contract (frontmatter schema, JSON schema, public API surface, env-var shape, file format, exported function signature), list "Identify consumers" as the FIRST work item: `Grep` + `Glob` for scripts/hooks/workflows/sibling components parsing the contract surface; document parse paths. Migration work items follow. Without pre-flight, migrations break consumers silently. Full pattern in [context/plan-template.md](context/plan-template.md) "Pre-flight consumer check".

**Sub-topic promotion check** — when a phase grows beyond ANY of (>5 distinct work items / >300 LOC delta / own exploration or research need / 2+ sub-phases of its own / independent commit boundary), recommend promoting it to its own topic directory with its own PLAN.md. Sub-topics keep the parent PLAN.md scannable and give the promoted work its own clean-context boundary. Full criteria in [context/plan-template.md](context/plan-template.md) "Sub-Topic Promotion Trigger".

**File inventory for large-scope plans** — when a plan or phase touches ≥10 files, emit a checkbox inventory table per phase (file, action, rationale). Checkboxes enforce verification discipline — the agent ticks each file as processed; the reviewer sees completeness at a glance. Include KEEP rows for files audited and deliberately left unchanged. Full format in [context/plan-template.md](context/plan-template.md) "File Inventory".

**Sanity-check verifiable-criterion enforcement** — every phase ends with at least one `**Sanity Check:**` bullet. Criteria MUST be mechanically verifiable (a specific grep, file Read assertion, build exit code, test exit code, or runtime probe) — never vague (~~"documented appropriately"~~, ~~"behaves as expected"~~, ~~"all cases covered"~~). Rewrite vague criteria as exact commands a fresh session can execute without inferential judgement. Full format guide in [context/plan-template.md](context/plan-template.md) "Sanity-Check Format".

**Build-technique selection** — BEFORE ordering phases, pick the de-risking technique by the task's *uncertainty type*: a throwaway spike / prototype / PoC when the unknown is feasibility, design, or viability (*might abandon*); a kept tracer bullet / walking skeleton when you are committed to ship and the risk is integration. Choose by uncertainty, not habit; when BOTH a feasibility unknown and ship-commitment hold, spike first (throwaway — `/prototype:logic` if installed, or research) then tracer-bullet the kept slice. Trivial / pure-horizontal work skips all techniques.

**Integration-first phase ordering** — once the technique is the kept branch (tracer bullet / walking skeleton), for multi-layer features sequence the FIRST phase as the integration slice and make its `**Sanity Check:**` an end-to-end runtime probe. Skip for pure-horizontal work (migration, lint, doc pass).

**Measurable-goal baseline capture** — when the brief states a measurable goal (perf / latency / throughput / allocation / complexity / coverage keywords), capture a baseline **by default** BEFORE the change: route to `/verification:measure performance baseline` (perf) or `/verification:measure metrics baseline` (code metrics) if installed — the measurement mechanism is SSOT there; this skill routes, never reimplements — or measure the pre-change state manually. Store the raw capture under `<memory_dir>/<topic-slug>/baselines/` (default `.work/`; the memory slice — baselines are machine-bound and never committed), then record the distilled baseline value + target in PLAN.md. After the change, re-measure and compare through the same route (its `compare` phase reads the stored baseline, or re-measure manually) and record the comparison in PLAN.md as distilled values only — PLAN never cites the memory-slice capture path (it is invisible outside the writing checkout and the pointer would dangle; topic-docs pointer discipline). Never claim an improvement without a baseline.

### Step 3: Plan Stress-Test (MANDATORY — never skip)

**Before assessing blast radius or presenting ANY plan, dispatch a fresh-context plan-reviewer sub-agent.** The producing main thread MUST NOT self-attack the plan inline — fresh-context verifiers outperform self-critique; the model that just wrote the plan rubber-stamps it.

1. Gather the plan draft + design artifacts (or `design-resolution.md`) + the Brief
2. Dispatch a read-only general sub-agent with the prompt from [context/plan-reviewer.md](context/plan-reviewer.md)
3. **Verify reviewer findings** against the actual code/files before applying fixes — sub-agent findings are synthesis, not ground truth
4. Fix every confirmed gap in the plan BEFORE proceeding — do not present a plan with known gaps

Trivial single-file plans (3–5 bullets, no new types): the reviewer brief may be shortened to structural-integrity checks only; still dispatch fresh context, never inline self-critique.

### Step 3b: Assess Blast Radius

Every plan gets a blast-radius check. Read the criteria in [context/stress-test-triggers.md](context/stress-test-triggers.md) and assess whether this plan warrants a full formal stress-test via `/devils-advocate`.

Present the assessment:

```
Blast radius: [LOW / MEDIUM / HIGH / CRITICAL]
Stress-test needed: [Yes — invoking /devils-advocate / No — plan-reviewer sub-agent + research validation is sufficient]
Reason: <1-2 sentences>
```

If LOW and no triggers match: skip Step 4 (Formal Stress-Test) only — continue at Step 4.5 (execution shape), then Steps 4.6-4.7 before presenting.
If MEDIUM or higher, or any trigger matches: proceed to Step 4 (Formal Stress-Test), then continue through Steps 4.5-4.7.

### Step 4: Formal Stress-Test and Research-Iterate (conditional)

This step runs only when the blast-radius assessment triggers it. Note: Step 3 (plan stress-test sub-agent) already ran — this is the deeper, formal version.

1. **Dispatch `/devils-advocate` to a fresh-context sub-agent** — hand it the plan (plus the Brief and any design artifacts), not your rationale for it. The producing main thread MUST NOT run the stress-test inline, for the same reason Step 3 dispatches: the context that wrote the plan carries the assumptions that produced its blind spots and converges on approval rather than detection. The stress-test skill runs its own multi-round process (assumption identification, evidence check, failure scenarios, operational gotchas) in that clean context; the main thread then verifies its findings against the actual code/files before acting on them — sub-agent findings are synthesis, not ground truth

2. **Evaluate findings** — if `/devils-advocate` produces CRITICAL or HIGH findings:
   - Run targeted research to resolve the specific issues surfaced (`/discovery:research` if installed, or the strongest research capability available)
   - Update the plan based on new evidence
   - Re-assess: does the updated plan survive scrutiny?

3. **Iterate if needed** — repeat the Plan-Stress-Research cycle until the plan achieves HIGH confidence on all claims. See [context/research-iterate.md](context/research-iterate.md) for the loop protocol

4. **Escalation guard** — if 3 iterations haven't resolved the issues, present the remaining risks to the user explicitly. Don't loop indefinitely — the user may accept known risks or redirect the approach entirely

### Step 4.5: Execution-Shape Analysis (parallelism — default ON for multi-phase plans)

After the phase plan is locked but before Step 5 approval, compute the execution shape: which phases can run in parallel and which surface each phase runs on. **Default ON** for any plan with ≥2 phases; emits a one-line "fully sequential — phase X gates phase Y" note when no parallelism opportunity exists. Skip entirely for single-phase plans or trivial fixes — skipped = all-main-session execution, stated in one line.

**Analysis steps:**

1. **File-overlap matrix** — for each phase pair (i, j), check whether their ALLOWED file lists intersect. Zero overlap = parallel-safe candidate
2. **Dependency graph** — explicit (Phase A produces output Phase B consumes; Phase A's contract change is cited by Phase B's Sanity Check) + implicit (semantic-source-before-mechanical-execution; sweep-before-detector-activation)
3. **Identify Wave A (parallel-safe set)** — largest subset with zero file overlap AND no inter-phase dependencies
4. **Identify Wave B+ (sequential)** — phases blocked by Wave A outputs
5. **Recommend shape** — RECOMMEND parallel when ≥2 phases are parallel-safe AND the saving is material (roughly ≥100 LOC of independent work). Otherwise document sequential as the default. Sequential remains a valid choice even with opportunity present
6. **Author scope-fencing tables** — for each parallel agent: ALLOWED files (whitelist) + explicit FORBIDDEN (PLAN.md, other agents' territory) per [context/plan-template.md](context/plan-template.md) "Scope-fencing tables"
7. **Surface the cost** — parallel agents multiply token usage; state "N agents parallel vs sequential" so the user picks consciously
8. **Document sequential fallback** — an explicit path back to sequential ordering if parallel orchestration fails (scope-fence violation, concurrent-edit race, an agent reports it cannot complete)
9. **Assign per-phase execution surface** — give each phase a routing row (`Phase | Surface | Basis`): main-session for judgment-heavy or tightly-coupled work, sub-agent worker for mechanical or file-disjoint volume work, agent team for parallel-safe workers that must message each other — route to agent team only when the environment has agent teams enabled (an experimental, default-off surface); otherwise fall back to sub-agent workers or sequential

**Output:** an Execution-Shape Analysis subsection in the plan body (parallelism shape + per-phase routing table) + scope-fencing tables in "Handoff to implementation". The user approves the shape at Step 5.

**Composition risks:**

- Parallel orchestration depends on sub-agent compliance with scope-fence discipline. The sequential fallback path MUST be documented in PLAN.md "Handoff to implementation"
- PLAN.md edits stay main-session-only (status updates would race if agents edited PLAN); agents report back instead
- **Design for an agent team when the parallel-safe workers must message each other** (cross-layer feature, competing-hypothesis debugging) rather than just fan out and report back — that execution shape is an **agent team**, not independent fan-out sub-agents. The file-overlap matrix above IS the team-safety check: decompose by **context boundary / disjoint clean-interface file-set, never by lifecycle role** (a planner/implementer/tester of one feature shares too much context). Dependency-order the task list so blocked tasks auto-unblock; teammates are NOT worktree-isolated, so disjoint file ownership is mandatory, not optional. Agent teams are an experimental, default-off runtime surface — verify availability before routing a phase there, and keep the sub-agent fan-out or sequential path as the documented fallback
- The user's commit policy is unchanged — staging/commits happen per the consuming project's own rules, never silently by parallel agents

### Step 4.6: Tag unilateral decisions

Before Step 5 approval, walk the PLAN body + Handoff section and classify every decision NOT explicit in the brief: `[EXEC-SHAPE]` (your discretion within briefed scope) or `[FALLBACK — confirm or override]` (an invented contingency the brief didn't anticipate); briefed decisions get no tag. **Then apply the confidence gate**: DECIDE only when the basis is evidence captured this session (a codebase pattern read, a research finding, or a directly-on-point project convention) with no surviving reasonable alternative; everything below the bar — judgment calls, sizing guesses, either-would-work placements — routes to an interview round (one question at a time, recommendation + basis) BEFORE the plan locks; hard-to-reverse decisions escalate EARLY regardless of confidence. Full gate, taxonomy, and presentation contract: [context/tag-decisions.md](context/tag-decisions.md). Surface every gate-passed decision at Step 5 in the "Decisions made (gate-passed)" TABLE (Decision | What it changes in the plan | Basis) so the user can override before implementation.

### Step 4.7: Outcome gate (before Step 5 — verify the PLAN, not a recap)

Before presenting at Step 5, persist the composed plan as a **draft** to `<contract_dir>/<topic-slug>/PLAN.md` (default `docs/topics/`; under `contract_tier: local` it joins the memory slice — the final-persist step below updates the same file after approval feedback), then check the artifact against binary criteria read off it (grep / Read / count) — not a holistic "is the plan good?" recap, which the model that just wrote the plan will rubber-stamp. Any FAIL → fix the PLAN before presenting:

- **Every phase has ≥1 `Sanity Check`** — `grep -c "Sanity Check" PLAN.md` ≥ the phase count; a phase with no verifiable check is unshippable.
- **Every phase carries a valid status tag** — each `### Phase N:` ends in `[TODO]` (or another valid tag); no untagged phase.
- **Every brief scope-item maps to a phase** — walk the Brief's scope list against the phases; no scope-item silently dropped, no in-scope phase missing.
- **Every unilateral decision is surfaced** — each `[EXEC-SHAPE]` / `[FALLBACK]` tag from Step 4.6 appears in the "Decisions made (gate-passed)" table (with its what-it-changes column filled), not left only in the plan body; below-bar decisions were interviewed, not decided.
- **Blast radius assessed** — a Blast-radius line exists (from Step 3b), not omitted.

This is the cheap binary self-check on the artifact; it does NOT replace the human approval at Step 5 — the user is the terminal gate (deterministic check → human). It catches a satisficed or incomplete plan before the user has to.

### Step 5: Present for Approval

Present the final plan to the user. The plan is a proposal, not a commitment — the user approves, modifies, or rejects it before execution begins.

**Include in the presentation:**

1. The structured plan (from Step 2, updated by Steps 3-4 if applicable)
2. Blast-radius assessment (from Step 3b)
3. Stress-test summary (from Step 4, if run) — or "Skipped: blast radius LOW, no triggers matched"
4. **Execution shape** (from Step 4.5) — parallelism shape AND per-phase routing table. Skipped for single-phase plans
5. **Decisions made (gate-passed)** (from Step 4.6) — TABLE per [context/tag-decisions.md](context/tag-decisions.md) "Presentation contract": `Decision | What it changes in the plan | Basis (evidence)`, one row per gate-passed `[EXEC-SHAPE]` / `[FALLBACK]` tag, written for a cold reader (no session shorthand). Below-bar decisions never appear here — they were interviewed before the plan locked. An empty section ("no unilateral decisions — every PLAN item traces to brief") is also valid output
6. **Explicit approval request**: "Approve this plan to proceed to execution, or provide feedback to revise. Anything tagged `[EXEC-SHAPE]` or `[FALLBACK]` above is /planning:plan's discretion — flag any you want changed."

**Presentation order — tweak-likelihood first.** Order the presentation by what the user is most likely to change on review: data-model/schema choices, type interfaces and public contracts, and user-facing surfaces LEAD (flag close calls with their alternatives); mechanical refactoring and low-judgment work sits at the bottom. Presentation order only — phase EXECUTION order stays integration-first per Step 2. Optionally offer a self-contained HTML plan view (decisions-first layout, flagged choices with toggleable alternatives); PLAN.md stays the tracked record.

If 2–4 named alternatives surfaced during the stress-test, present them via `AskUserQuestion` — the side-by-side rendering helps the user pick faster than reading prose alternatives. For open-ended approval (single proposal, no alternatives) use prose.

**After approval — branch-name check:**

Before handing off to implementation, verify the branch name matches the approved scope. Scope is now locked — the branch name should reflect the work.

| Current branch | Action |
|----------------|--------|
| `main` or `master` | STOP — cannot implement on the default branch. Suggest `git checkout -b <type>/<topic-slug>` derived from the plan topic + conventional prefix |
| Auto-generated or placeholder name | Derive the name from the plan: `<type>/<topic-slug>` (type from the plan's nature — `feat/`, `fix/`, `refactor/`, `chore/`, etc.). Suggest the rename; let the user execute unless the environment is isolated (worktree or remote session), where renaming directly is safe |
| Matches a conventional prefix (`feat/`, `fix/`, etc.) | OK — no action needed |

Derive the conventional type from plan content: new capability → `feat/`, bug fix → `fix/`, restructuring → `refactor/`, tooling/maintenance → `chore/`, docs-only → `docs/`, tests-only → `test/`, build config → `build/`, performance → `perf/`.

**After approval:** the plan feeds into implementation. Suggest the consuming environment's implementation workflow (an `/implement`-style skill if it ships one, otherwise structured inline execution reading PLAN.md). If implementation diverges from the plan, chain back to `/planning:plan review` to re-plan rather than pushing through a broken approach.

## Plan Mode Integration

Claude Code's built-in plan mode provides read-only enforcement — Claude reads files and runs diagnostic commands but doesn't edit source code. This is useful during the planning process:

- **During formulation (Steps 1-2):** plan mode ensures you're exploring safely while designing the approach. If you're already in plan mode when this skill triggers, stay in it
- **During stress-test (Step 4):** plan mode is appropriate — you're analyzing, not implementing
- **After approval (Step 5):** exit plan mode to begin execution. The user's approval is the gate

The skill does not automatically enter plan mode — the user controls permission modes. But if you're about to plan a complex change and are NOT in plan mode, suggest it: "Consider entering plan mode (`shift+tab`) for safe exploration while we design this."

Plan mode is also the canonical surface for `AskUserQuestion`-driven clarifying questions — if you're entering plan mode for safe exploration during planning, treat it as a license to ask 1–4 clarifying questions before proposing the plan.

## Plan Review Mode

When invoked with `review`:

1. Identify the plan in the current conversation (most recent plan, proposal, or design)
2. Evaluate against the [plan template](context/plan-template.md) — is anything missing?
3. Check alignment with the consuming project's conventions (its `CLAUDE.md` and rules)
4. Assess whether the blast radius was properly evaluated
5. Present findings: what's strong, what's missing, what needs revision

This is complementary to `/devils-advocate` — review checks completeness and convention alignment; stress-test checks assumptions and failure modes.

## Final step: persist the approved plan for handoff

After the user approves the plan in Step 5, update the draft `<contract_dir>/<topic-slug>/PLAN.md` (default `docs/topics/`; persisted at Step 4.7) with any approval-round changes — derive `<topic-slug>` from the task or branch name (kebab-case, ≤40 chars; shared with `/prd`, `/interview`, `/design`); roots, tier, and precedence resolve per the topic-docs binding [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md). PLAN.md is a contract document: under `contract_tier: branch` (the default), commit it on the task branch as it locks, so worktrees, clones, and reviewers see it, and let each implementation phase's plan updates ride the same commit as that phase's source changes; under `contract_tier: local` it lives in the self-ignored memory slice and is never staged — the PR-description paste is its only publication surface. It is the **living source of truth** for the stage — a fresh cleared session must be able to execute the plan reading only this file (plus the exploration/research artifacts in the topic's memory slice `<memory_dir>/<topic-slug>/`, default `.work/`).

**PLAN.md anatomy.** PLAN holds Brief + Plan; per-phase status lives in the phase tags (`[TODO]` / `[DOING]` / `[DONE]`):

```markdown
## Brief
<from /interview if applicable — task restatement, scope boundaries, success criteria>

## Plan

### Phase 1: <name> [TODO]
<file-by-file changes, rationale, per-phase sanity-check criteria>

### Phase N: <name> [TODO]
<...>

## Blast radius
<LOW / MEDIUM / HIGH with reasoning>

## Stress-test summary
<Step 4 output, or "Skipped: blast radius LOW, no triggers matched">

## Execution shape
<Step 4.5 output — Wave A/B shape with ALLOWED/FORBIDDEN scope-fencing tables + cost note, OR "fully sequential — phase X gates phase Y" one-liner, PLUS the per-phase routing table (Phase | Surface | Basis). Skipped for single-phase plans>

## Open questions
<anything unresolved at approval time>

## Handoff to implementation

### User-approval gates
<actions implementation MUST surface for confirmation before executing: any [FALLBACK] tags, any scope-expansion proposals, any mid-flight pivots that change acceptance criteria. At each gate, ask or stop + flag. An empty section is valid — small tasks may have zero gates beyond the initial plan approval>

### Execution shape ([EXEC-SHAPE] tagged)
<orchestration choices /planning:plan made: parallel waves OR sequential, the per-phase routing table, agent rosters, ALLOWED/FORBIDDEN scope-fencing tables, sub-topic promotion, sanity-check criteria per phase>

### Mechanical work
<commit boundaries, verification checkpoints, sequential fallback path (when parallel recommended). Standard implementation boilerplate — rarely needs user-specific override>
```

Advance the phase tag (`[TODO]` → `[DOING]` → `[DONE]`) as implementation completes each phase — the tags are what a resuming session reads to know where to continue.

PLAN.md is a multi-turn shared artifact: re-read it from disk before every write — another turn or agent may have modified it — and prefer appending or refining sections over wholesale rewrites.

Write the plan even for small changes — future you or a fresh-session agent will thank you.

**Close-out (PR time).** The contract slice is branch-lived; `/planning:plan` owns describing its close-out — invoke with the `close-out` argument once the plan is approved:

1. Paste the approved PLAN.md into the PR description inside a `<details>` block — the review-surface publication (PR bodies cap near 64 KB; paste the contract, reference the rest).
2. Graduate durable outcomes through the knowledge-vault seam — resolve the concern file's `vault_backend`: `docs` (default) → a history-preserving `git mv` of the promoted doc into `docs/adr/` or `docs/specs/` (guard the command — create the target directory first); `gitbook` → report that writes are deferred and use the `docs` path without invoking GitBook API/MCP or Git Sync; any other enabled value → the backend the consuming repo documents, degrading to `docs` when its tools are absent (binding: [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md)). Actionable follow-ups go through the work-item tracker seam.

   **ADR admission test** — a decision earns an ADR only when ALL three hold: **hard to reverse** (changing course later carries real cost), **surprising without context** (a future reader of the code would wonder why it was done this way), and **the result of a real trade-off** (genuine alternatives existed and one was picked for specific reasons). Any one missing → no ADR: an easily reversed decision just gets reversed, an unsurprising one raises no questions, and a no-alternative decision has nothing worth recording. Keep each ADR minimal — a title plus a few sentences covering context, decision, and why; optional sections (status, considered options, consequences) only when they earn their place. Prefer writing the ADR the moment the decision crystallizes during planning over batching candidates at graduation — this step then just moves the already-written file.
3. Prune with pointer: a final commit before merge deletes the contract slice `<contract_dir>/<topic-slug>/` (default `docs/topics/`), leaving context pointers (the PR body, the promoted-doc and tracker locations) in its place.

Lifecycle detail and the redaction bar for committed evidence: [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md).

**Mid-flight pivots:** when scope changes after approval, append a dated scope-change note to the affected PLAN.md section capturing the rationale, and strikethrough+link the obsolete content. Carry the pivot rationale in the commit message as well — the contract is branch-tracked, so git log is the history. Do not silently rewrite history.

**After writing, recommend:** clear context and begin implementation — the implementing session reads PLAN.md for the execution roadmap.

## What This Skill Does NOT Do

- **Does not replace `/devils-advocate`** — that skill does adversarial stress-testing. This skill orchestrates when to invoke it based on blast radius
- **Does not replace research** — research gathers external evidence. This skill uses research findings as input and may trigger additional research in Step 4 (research-iterate loop)
- **Does not replace built-in plan mode** — plan mode is a permission mode. This skill is a planning discipline. They complement each other
- **Does not write code** — it produces a plan. Execution is a separate stage
- **Does not block execution** — it advises and gates on user approval. The user can always override
- **Does not make decisions** — it structures the decision for the user. The user approves or rejects

## Gotchas

- **NEVER skip Step 3 plan stress-test.** Dispatch the fresh-context plan-reviewer sub-agent every time — the producing planner must not self-critique inline. If the user finds a gap in 5 seconds that the reviewer missed, tighten the reviewer brief. MANDATORY regardless of blast radius
- **Don't skip the prerequisite check.** Plans built without exploration miss existing patterns. Plans without research repeat mistakes others have solved. The prerequisite check is 30 seconds; the rework is 30 minutes
- **Scale the plan to the task.** A 50-line plan for a typo fix is over-engineering. A 3-bullet plan for a cross-cutting refactor is under-engineering. Match depth to blast radius
- **Don't confuse this skill with built-in plan mode.** Plan mode is a read-only permission mode. `/planning:plan` is a planning discipline. If a user types "plan this", they want the discipline, not the permission mode
- **Research-iterate has a ceiling.** 3 iterations max before escalating to the user. Infinite loops waste context on diminishing returns. If 3 rounds can't resolve it, the approach may need to change, not just the evidence
- **The plan is a proposal.** Never start executing without user approval. The approval gate is the point — it's where human judgment enters the loop
- **Step 4.5 (Execution shape) is default ON for ≥2-phase plans.** Skip explicitly only for single-phase plans or trivial fixes — skipped = all-main-session execution, stated in one line
- **Open Decisions resolved BEFORE the plan body is authored.** Surfacing them mid-plan-body forces re-iteration during Step 5. The Step 1 prereq check enforces this — scan the resume prompt + conversation + Brief for unresolved choices; `AskUserQuestion` resolves cheaply
- **Sanity Check criteria are mechanically verifiable.** A future cleared session running the phase's sanity check needs an executable command (grep, Read assertion, build/test exit). Vague criteria invite inferential drift — rewrite as the exact command a reviewer would run
