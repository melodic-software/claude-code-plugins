---
description: "Produce structured implementation plans with goal, approach, test strategy, blast-radius assessment, parallelism analysis, and a user approval gate before any code is written. Persisting PLAN.md for fresh-session handoff. Use when: 'plan this', 'architect this', 'how should we implement', 'implementation plan', 'write a plan for this', 'what's the approach here', 'review this plan' (audits an existing plan's completeness), or proactively before executing without a formalized plan."
argument-hint: "[task description, 'review', or 'close-out']"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: plan
  summary: Produce a structured implementation plan with an approval gate
---

**Arguments.** `[task description, 'review', or 'close-out']`. e.g., /planning:plan add caching to query handlers, /planning:plan review, /planning:plan close-out

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined into a single
invocation:

- Current branch, `git branch --show-current`
- Recent commits, `git log --oneline -5`
- Working tree status (empty = clean), `git status --porcelain | head -10`

The pipe is the bound and belongs in the command. A read-time cap ("read only the first 10 entries")
bounds nothing: the Bash tool returns the command's complete output into context before there is
anything to decide about.

Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as
separate body Bash calls rather than pre-compute lines: the harness runs a skill's whole pre-compute
block as one shell invocation, and a worktree-isolated session refuses a compound command that
contains git. The dated record for that composition claim is the worktree skill's
[reference/gather-block.md](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/source-control/skills/worktree/reference/gather-block.md),
"The pre-compute block runs as one shell invocation".

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Plans fail when they skip rationale, ignore blast radius, or rush past approval gates. This skill structures the planning step so that every implementation starts with a clear design, with evidence, test strategy, and user sign-off, before a single line of code is written.

This is **not** Claude Code's built-in plan mode (`shift+tab`). That is a *permission mode*: read-only exploration. This skill is a *planning discipline*: the intellectual work of designing an approach, assessing risks, and getting approval. The two complement each other: use plan mode for safe exploration during planning, and this skill for the structured process around it.

This skill takes the outputs of the earlier stages, exploration (local understanding), research (external evidence), and `/planning:design` (types, contracts, module boundaries, package topology), and produces a plan the user approves before execution begins.

**Philosophy**: a 2-minute plan prevents a 20-minute rework cycle. The depth of planning should match the blast radius. A one-file fix gets a brief plan; a cross-cutting architecture change gets a full plan with stress-testing and research-iterate loops.

## Emit checklist

For multi-step planning sessions (almost always: steps 1-5 of this skill), copy `templates/checklist.md` into the topic's memory slice as `<memory_dir>/<topic-slug>/plan-checklist.md` (default `.work/`). Tick each `- [ ]` as the corresponding step completes. Step 3 (Plan stress-test via fresh-context sub-agent) and Step 5 (Present for approval) are non-negotiable ticks. Stress-test before presenting, always.

**Skip when:** mid-flight `review` replan only. Append a dated scope-change note and revise the PLAN phases instead; do not spawn a second checklist file.

For **non-trivial / multi-layer** plans, Step 2 walks its design-default checklist **against the plan**, confirming the plan reflects the design artifact's resolved threads rather than re-deriving the axes inline. Configurability, extension points, observability, and testability are design threads owned by `/planning:design`'s "Design defaults"; type-collaboration shape is its type modeling. Audit that the plan carries their resolutions, don't re-open them here. Magic-literal hygiene stays plan's own review check against the consuming project's review conventions when it declares them.

## Action Router

Parse `$ARGUMENTS` to determine the action:

| Argument | Action | Use case |
|----------|--------|----------|
| *(empty)* | **Smart default** | Detect context: if a plan exists in conversation, offer to finalize/review; if exploration and research are done, start planning; otherwise suggest prerequisites |
| `<task description>` | **Full planning** | Run the complete planning process for the described task |
| `review` | **Plan review** | Critique an existing plan for completeness, feasibility, and alignment with the project's conventions |
| `close-out` | **Close-out** | Run the PR-time close-out procedure (below) for an already-approved plan: publish PLAN.md to the PR, graduate durable outcomes through the knowledge-vault seam, prune the contract slice |

## Planning Process

### Gates

These hold after a compaction re-attach. Later steps say how to carry them out.

**Verification.** Claim: after auto-compaction Claude Code re-attaches each skill's most recent invocation keeping its first 5,000 tokens, within a shared 25,000-token budget. Basis: https://code.claude.com/docs/en/skills (auto-compaction paragraph); `tests/reattach-slice.test.sh` stands in for the 5,000 tokens with the first 20,000 bytes. As-of: 2026-09-29. Recheck when that paragraph changes either figure, or when the page stops describing a per-skill re-attach.

- **Reviewer.** Before assessing blast radius or presenting ANY plan, dispatch a fresh-context plan-reviewer sub-agent. The producing thread does not self-attack the plan inline.
- **Hard-to-reverse decisions escalate EARLY** regardless of confidence. Below-bar judgment calls go to an interview round before the plan locks.
- **Agent teams.** Route a phase to an agent team only when the parallel-safe workers must message each other and agent teams are enabled; otherwise use sub-agent workers or sequential. Teammates are not worktree-isolated, so disjoint file ownership is mandatory.

### Step 4.7: Outcome gate (before Step 5. Verify the PLAN, not a recap)

Before presenting at Step 5, persist the composed plan as a **draft** to `<contract_dir>/<topic-slug>/PLAN.md` (default `docs/topics/`; under `contract_tier: local` it joins the memory slice. The final-persist step below updates the same file after approval feedback), then check the artifact against binary criteria read off it. Not a holistic "is the plan good?" recap, which the model that just wrote the plan will rubber-stamp. Any FAIL → fix the PLAN before presenting.

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-plan-outcome.sh" <PLAN.md>` and require exit 0. It decides the mechanical criteria off the file, one `criterion=<name> status=<pass|fail>` line each:

- **Every phase has ≥1 `Sanity Check`**, counted per phase section; a phase with no verifiable check is unshippable.
- **Every phase carries a valid status tag**. Each `### Phase N:` ends in `[TODO]`, `[DOING]`, or `[DONE]`; no untagged phase.
- **Every unilateral decision has a table row**. When the plan carries an `[EXEC-SHAPE]` / `[FALLBACK]` tag from Step 4.6, the "Decisions made (gate-passed)" table (`| Decision | What it changes in the plan | ...`) is persisted in PLAN.md with at least one row.
- **Blast radius assessed**. A Blast-radius line naming LOW, MEDIUM, HIGH, or CRITICAL exists (from Step 3b), not omitted.
- **Paths are portable**. No drive-letter path and no `/Users/<name>` or `/home/<name>` path, since a committed PLAN.md is read on other machines; a deliberate example carries `<!-- path-example -->` on its line.

The rest are judgment checked by reading, or have their own script:

- **Every brief scope-item maps to a phase**. Walk the Brief's scope list against the phases; no scope-item silently dropped, no in-scope phase missing.
- **Each tag has its own row**. Every tagged decision appears in that table with its what-it-changes column filled, not left only in the plan body; below-bar decisions were interviewed, not decided. The script checks only that the table has rows.
- **Displaced answers are listed at Step 5**. When an interview ledger exists, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-open-questions.sh" --ledger <ledger>`. It passes when the verdict reports `open=0` and `superseded=N` (exit 1 is expected when N > 0) and every id on the ledger's `| superseded-by-plan |` rows (the verdict prints only the count) appears in the Step 5 "Displaced answers and new external effects" block.

This is the cheap binary self-check on the artifact; it does NOT replace the human approval at Step 5. The user is the terminal gate (deterministic check → human). It catches a satisficed or incomplete plan before the user has to.

**The gate does not vanish when no human is present.** On an unattended run (a routine, a dispatched worker, any session with nobody to answer), approval proceeds only under a standing mandate that covers this plan, and its basis is recorded in PLAN.md's `Approval:` line: the mandate, who granted it and where, and the review surface that stands in for the human (for example the PR). With no such mandate, stop here and report the plan as unapproved. Listed changes stay uncleared either way ("Plan changes after the Brief", its "Unattended run" bullet). The default run above does not look for the `Approval:` line, which exists only after approval; the final persist step checks it with `--approval-only`.

### Step 5: Present for Approval

Present the final plan to the user. The plan is a proposal, not a commitment. The user approves, modifies, or rejects it before execution begins.

Unattended approval is the Gates rule under Planning Process, above.

**Include in the presentation:**

1. The structured plan (from Step 2, updated by Steps 3-4 if applicable)
2. Blast-radius assessment (from Step 3b)
3. Stress-test summary (from Step 4, if run). Or "Skipped: blast radius LOW, no triggers matched"
4. **Execution shape** (from Step 4.5). Parallelism shape AND per-phase routing table. Skipped for single-phase plans
5. **Displaced answers and new external effects** (from "Plan changes after the Brief"). One row per change: `Q<N>` or `none`, what the user said, what the plan now proposes, the new external effect, and the source (`reviewer fix`, `research update`, or `stress-test finding`). Omit the block when empty. The approval request names every row as needing its own reply
6. **Decisions made (gate-passed)** (from Step 4.6). TABLE per [context/tag-decisions.md](context/tag-decisions.md) "Presentation contract": `Decision | What it changes in the plan | Basis (evidence) | Source`, one row per gate-passed `[EXEC-SHAPE]` / `[FALLBACK]` tag, written for a cold reader (no session shorthand). Below-bar decisions never appear here. They were interviewed before the plan locked. An empty section ("no unilateral decisions. Every PLAN item traces to brief") is also valid output
7. **Explicit approval request**: "Approve this plan to proceed to execution, or provide feedback to revise. Anything tagged `[EXEC-SHAPE]` or `[FALLBACK]` above is /planning:plan's discretion. Flag any you want changed."
8. **Highest-leverage replies**: close with 2-4 pre-drafted one-line revision replies, one per flagged close call or gate-passed decision, each a copyable sentence that flips exactly that decision (e.g. "Switch phase 2 to the queue-based alternative"). The user's cheapest possible reaction is pasting one back; a presentation whose flagged decisions have no pre-drafted flip line makes the user compose the revision themselves

**Presentation order. Tweak-likelihood first.** Order the presentation by what the user is most likely to change on review: data-model/schema choices, type interfaces and public contracts, and user-facing surfaces LEAD (flag close calls with their alternatives); mechanical refactoring and low-judgment work sits at the bottom. Presentation order only. Phase EXECUTION order stays integration-first per Step 2. Optionally offer a self-contained HTML plan view (decisions-first layout, flagged choices with toggleable alternatives), rendered to the topic-docs **ephemeral tier**, never the contract slice beside `PLAN.md`, which stays the tracked record. Placement and rules: [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md).

If 2–4 named alternatives surfaced during the stress-test, present them side by side via `AskUserQuestion` when the plugin's `use_ask_user_question` user config (`${user_config.use_ask_user_question}`) is on. Numbered inline prose otherwise. For open-ended approval (single proposal, no alternatives) use prose.

**After approval. Branch-name check:**

Before handing off to implementation, verify the branch name matches the approved scope. Scope is now locked. The branch name should reflect the work.

| Current branch | Action |
|----------------|--------|
| `main` or `master` | STOP. Cannot implement on the default branch. Suggest `git checkout -b <type>/<topic-slug>` derived from the plan topic + conventional prefix |
| Auto-generated or placeholder name | Derive the name from the plan: `<type>/<topic-slug>` (type from the plan's nature. `feat/`, `fix/`, `refactor/`, `chore/`, etc.). Suggest the rename; let the user execute unless the environment is isolated (worktree or remote session), where renaming directly is safe |
| Matches a conventional prefix (`feat/`, `fix/`, etc.) | OK. No action needed |

Derive the conventional type from plan content: new capability → `feat/`, bug fix → `fix/`, restructuring → `refactor/`, tooling/maintenance → `chore/`, docs-only → `docs/`, tests-only → `test/`, build config → `build/`, performance → `perf/`.

**After approval:** the plan feeds into implementation. Suggest the consuming environment's implementation workflow (an `/implementation:implement`-style skill if it ships one, otherwise structured inline execution reading PLAN.md). If implementation diverges from the plan, chain back to `/planning:plan review` to re-plan rather than pushing through a broken approach.

Step 5, the approval gate, is placed with the gates above so a compaction re-attach keeps it. The approval gate is the point.

### Step 1: Prerequisite Check

Prefer the simplest plan that works and keep each step's changes surgical.

Before planning, verify the knowledge base is ready:

- **Is the effort coherent enough to plan?**. If the work is too big to hold at once AND still too foggy to phrase as sharp decisions (missing questions you can't yet state, not just unanswered ones), `/planning:plan` is premature. A plan needs a coherent target. Guide the user to `/planning:wayfind` first (it charts the fog as a decision map and works it down until a destination coheres); recommend, never auto-switch. Skip when the effort is already scoped and the open items are answerable questions
- **Is product intent clear?**. For product-driven feature work (new user-facing surface, business-driven change, cross-team initiative), check that the topic's contract slice holds `PRD.md` (`<contract_dir>/<topic-slug>/PRD.md`, default `docs/topics/`; the memory slice under `contract_tier: local`) OR that problem/users/success-metrics are already crisp in conversation. If fuzzy, suggest running `/planning:prd` first. Skip this check for engineering-internal work (refactors, infra, hooks, conventions, bug fixes). `/planning:prd` does not apply
- **Has exploration been done?**. Check if the conversation contains exploration findings for the relevant area. If not, suggest running the exploration capability first (`/discovery:explore` if installed). Don't plan in the dark
- **Has research been done?**. Check if external research has been completed for technical claims the plan will rely on. If not, suggest running the research capability first (`/discovery:research` if installed). Plans built on assumptions instead of evidence lead to rework
- **Has `/planning:design` been done? (blocking gate)**. Classify design significance before planning:

| Tier | Signals | Requirement |
|------|---------|-------------|
| **A. Design-significant** | New types/contracts, new module or library, package topology change, cross-module integration, data model change, multi-tenant posture | **Blocking:** full or light `/planning:design` + its handoff gate (`design-threads.md` all RESOLVED / directional / TAGGED-DEFERRED) |
| **B. Light design** | 2–5 files, one new type, localized contract tweak | **Blocking:** minimal `type-inventory.md` OR `design/design-resolution.md` documenting early-exit with type sketch |
| **C. No design** | Single-file bugfix, config/doc/markdown, rename, hook text, pure test addition | **Blocking:** `design/design-resolution.md` with `outcome: early-exit` + reason (gate always evaluated) |

Check the topic's contract slice `<contract_dir>/<topic-slug>/design/` (default `docs/topics/`; the memory slice under `contract_tier: local`) for design artifacts OR `design-resolution.md` at that path. If Tier A/B requirements are unmet, **stop**. Offer `/planning:design` or document the early-exit artifact. The user may override via `AskUserQuestion` only when they explicitly accept skipping design exploration. `/planning:plan` consumes design artifacts. Do not re-derive design inline when design-significant.

- **Is the scope clear?**. If the task is ambiguous, ask clarifying questions before planning. A plan for "improve performance" is useless; a plan for "add a cache to the GetOrderById query handler" is actionable. Ask every question whose prerequisites are settled as one numbered round, each with a recommendation. A question that depends on another still open waits for the round after its prerequisite resolves; render the round via `AskUserQuestion` only when the plugin's `use_ask_user_question` user config (`${user_config.use_ask_user_question}`) is on and the round is ≤4 independent questions. Inline prose otherwise
- **Open Decisions surfaced BEFORE plan body**. Scan the resume prompt + conversation context + Brief for unresolved decisions (scope cuts, technique choices, ordering, exclusions) that the downstream plan body would otherwise lock inline. Surface every decision whose prerequisites are settled as a numbered "Open Decisions" block with research-backed recommendations + trade-offs per decision. A decision whose option set depends on another still open waits for the round after its prerequisite resolves; render the block via `AskUserQuestion` only when the plugin's `use_ask_user_question` user config (`${user_config.use_ask_user_question}`) is on and it holds ≤4 independent decisions. Single-prompt inline prose otherwise. Resolving once up front is cheaper than iterating during Step 5 approval

If prerequisites are missing, state what's needed and offer to run the prerequisite skill. Don't silently skip this step. Note that the `/planning:prd` check is **additive**, not blocking. Proceed if the user has product intent locked elsewhere or if the work is engineering-internal.

### Step 2: Formulate the Plan

#### Ground in consumer standards (first formulation input)

Before formulating, resolve the consumer's standards and load what this task touches. Plans are built to the criteria they will be reviewed against:

- **Resolve the index** by jumping to the "Resolution ladder" section of the plugin's contract binding [`${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md). The ladder (including the absent-index inference, offer-to-persist, and ask-once behavior) lives there and is not restated in this skill. Zero unprompted writes, ever.
- **Match** the task's surfaces (ecosystems touched, cross-cutting concerns) against the index rows' `Applies when` clues.
- **Pull selectively**. Only matched files, and within a matched file only the sections relevant to this task. Never re-pull ambient content (auto-loaded `CLAUDE.md`, fired `.claude/rules` directives). Post-compaction context and a new task both count as NOT ambient. Re-resolve per task; a second task in the same session grounds its own surfaces.
- **Depth rides the plan-scale table below**. A trivial plan takes no standards fetch beyond ambient context; larger scales ground the surfaces they touch. There is no grounding flag; scale governs cost.
- **Name provenance** when a personal-layer rule (a `*.local.md` overlay or the user-global layer) materially shapes the plan.
- **Broken index row** → surface it and offer the fix (Boy Scout). Never silent. **Always compare** the index's `standards-contract` frontmatter to the binding's own version when resolving; on any mismatch, degrade per the binding's tolerant-reader rule AND report the skew in the produced plan (older: best-effort + "index at vX, contract at vY. Re-run setup"; newer: best-effort + "update the plugin", no migration offer).
- The produced plan **cites the standards sections loaded** for the surfaces it touches, the template's "Standards grounding" element, or states why grounding was skipped (scale tier).

Produce a structured plan using the template in [context/plan-template.md](context/plan-template.md). The template covers:

- **Goal**: what we're trying to achieve and why
- **Approach**: the specific steps, in order
- **Test strategy**: how we'll verify the changes work. For which test type each kind of change needs (unit / integration / e2e / architecture / analyzer), `/testing:plan`'s file-type classification table is the SSOT **when the `testing` plugin is installed**; **invoke `/tdd:principles` via the Skill tool (if installed)** when formulating this section for authoritative guidance on what to test, which testing style fits, and when to mock; otherwise apply standard test-design judgment. TDD is the default approach. The test strategy should specify Red-Green-Refactor unless genuinely impractical. **Name the test boundaries**. The public interfaces the tests will drive, and for each whether it already exists or is being introduced (prefer driving an existing interface over introducing one for testability alone). Naming them is what lets Step 5's approval settle them, so implementation writes no test against a boundary the plan never named; on an unattended run, a boundary chosen during implementation that this section did not name is a deviation, logged for PR-time review (`DEVIATIONS.md` beside `PLAN.md` in the contract slice) rather than silently taken
- **Files affected**: what gets created, modified, or deleted
- **Alternatives considered**: what was rejected and why, plus a one-line switch condition per
  alternative: the observable fact that, if it turned up, would make this the better choice.
  A rejection with no switch condition is not revisable; the condition is what lets a reviewer
  (or a later phase) flip the decision without re-deriving the analysis
- **Risks and mitigations**: what could go wrong

Scale the plan to the task:

| Task scale | Plan depth |
|-----------|-----------|
| Trivial (1 file, well-understood) | 3-5 bullet points |
| Small (2-5 files, clear scope) | Brief plan. Goal, steps, test strategy |
| Medium (5-15 files, some unknowns) | Full plan with alternatives and risks |
| Large (cross-cutting, architectural) | Full plan + stress-test + research-iterate |

Per-scale calibration examples live in [context/plan-template.md](context/plan-template.md) "Choosing the Right Scale".

**Tracker-write phases:** when any phase ends in creating a work item (e.g. `gh issue create`), the plan body MUST follow the shape in [context/plan-template.md](context/plan-template.md) "Phase-entry checks for tracker writes". Search-before-create as the first work item, explicit pivot path for the match case, search outcome captured in the phase Sanity Check.

**Pre-flight consumer check**. When a phase migrates a contract (frontmatter schema, JSON schema, public API surface, env-var shape, file format, exported function signature), list "Identify consumers" as the FIRST work item: `Grep` + `Glob` for scripts/hooks/workflows/sibling components parsing the contract surface; document parse paths. Migration work items follow. Without pre-flight, migrations break consumers silently. Full pattern in [context/plan-template.md](context/plan-template.md) "Pre-flight consumer check".

**Sub-topic promotion check**. When a phase grows beyond ANY of (>5 distinct work items / >300 LOC delta / own exploration or research need / 2+ sub-phases of its own / independent commit boundary), recommend promoting it to its own topic directory with its own PLAN.md. Sub-topics keep the parent PLAN.md scannable and give the promoted work its own clean-context boundary. Full criteria in [context/plan-template.md](context/plan-template.md) "Sub-Topic Promotion Trigger".

**Phase merge floor**. The inverse bound: a phase of one file and a few lines with no verification need of its own merges into the adjacent phase it serves. Every phase pays a full dispatch, sanity-check, commit and plan-mark cycle, which a one-line phase does not earn. The threshold is judgment (the nearest anchor is Step 4.5's ~100 LOC parallelism floor); keep a small phase separate when it is its own commit boundary or needs its own Sanity Check.

**File inventory for large-scope plans**. When a plan or phase touches ≥10 files, emit a checkbox inventory table per phase (file, action, rationale). Checkboxes enforce verification discipline. The agent ticks each file as processed; the reviewer sees completeness at a glance. Include KEEP rows for files audited and deliberately left unchanged. Full format in [context/plan-template.md](context/plan-template.md) "File Inventory".

**Sanity-check verifiable-criterion enforcement**. Every phase ends with at least one `**Sanity Check:**` bullet. Criteria MUST be mechanically verifiable (a specific grep, file Read assertion, build exit code, test exit code, or runtime probe). Never vague (~~"documented appropriately"~~, ~~"behaves as expected"~~, ~~"all cases covered"~~). Rewrite vague criteria as exact commands a fresh session can execute without inferential judgment. Full format guide in [context/plan-template.md](context/plan-template.md) "Sanity-Check Format". Phase-scoped sanity checks are also what backs implementation's every-step-lands-green expectation: each phase can be verified green at its own boundary rather than only at the end.

**Build-technique selection**. BEFORE ordering phases, pick the de-risking technique by the task's *uncertainty type*, not by habit. A design or viability unknown (*might abandon*) resolves **upstream**. `/planning:design` for design-significant questions, a throwaway `/prototype:pressure-test` spike (if installed) or research for raw feasibility. And plan **consumes that outcome** rather than re-deriving it inline. Plan's own call is the *kept* slice: a tracer bullet / walking skeleton when you are committed to ship and the risk is integration. When an upstream feasibility spike and ship-commitment both hold, sequence the kept tracer-bullet slice after the spike's outcome lands. Trivial / pure-horizontal work skips all techniques.

**Integration-first phase ordering**. Once the technique is the kept branch (tracer bullet / walking skeleton), for multi-layer features sequence the FIRST phase as the integration slice and make its `**Sanity Check:**` an end-to-end runtime probe. Skip for pure-horizontal work (migration, lint, doc pass).

**Measurable-goal baseline capture**. When the brief states a measurable goal (perf / latency / throughput / allocation / complexity / coverage keywords), capture a baseline **by default** BEFORE the change: invoke `/verification:measure performance baseline` (perf) or `/verification:measure metrics baseline` (code metrics) via the Skill tool if installed. The measurement mechanism is SSOT there; this skill routes, never reimplements. Or measure the pre-change state manually. Store the raw capture under `<memory_dir>/<topic-slug>/baselines/` (default `.work/`; the memory slice. Baselines are machine-bound and never committed), then record the distilled baseline value + target in PLAN.md. After the change, re-measure and compare through the same route (its `compare` phase reads the stored baseline, or re-measure manually) and record the comparison in PLAN.md as distilled values only. PLAN never cites the memory-slice capture path (it is invisible outside the writing checkout and the pointer would dangle; topic-docs pointer discipline). Never claim an improvement without a baseline.

### Step 3: Plan Stress-Test

Apply the reviewer rule under Planning Process before blast radius or presentation. The producing main thread MUST NOT self-attack the plan inline. Fresh-context verifiers outperform self-critique; the model that just wrote the plan rubber-stamps it. Where the plan is high-stakes and correlated blind spots are the risk, prefer a cross-vendor advisor **when one is installed and set up**. E.g. the OpenAI Codex plugin, when its documented surface can take this artifact, invoked per its own docs. With the fresh-context plan-reviewer sub-agent as the stated fallback, never a route to a command that may not resolve (per `docs/plugin-philosophy.md` "Fresh-eyes checkpoints" in the marketplace repository).

1. Gather the plan draft + design artifacts (or `design-resolution.md`) + the Brief
2. **Surface the cost.** Tell the user a fresh-context plan review runs now, whatever they answer:
   one bounded sub-agent (default `effort: medium`, capped turns). One sentence is enough.
3. Dispatch the plugin's **`plan-reviewer`** agent (`agents/plan-reviewer.md`) with the prompt from
   [context/plan-reviewer.md](context/plan-reviewer.md). Do not substitute a generic read-only
   sub-agent: the agent definition carries bounded `effort` and `maxTurns` that session effort cannot
   lower per invocation (the verification record in `agents/plan-reviewer.md`).
   When the reviewer stops at its `maxTurns` limit its output may be marked partial, and older
   clients do not mark it. A complete report ends with its `### Summary` counts, or is the literal
   `No plan gaps found.` for a clean pass; treat any other return without that section as
   incomplete whether or not a marker is present: resume it (or re-dispatch with a narrowed brief); never treat a partial table as a clean pass.
4. **Verify reviewer findings** against the actual code/files before applying fixes. Sub-agent findings are synthesis, not ground truth
5. Fix every confirmed gap in the plan BEFORE proceeding. Do not present a plan with known gaps. A fix that displaces a user answer or adds an external effect follows "Plan changes after the Brief" below

Trivial single-file plans (3–5 bullets, no new types): the reviewer brief may be shortened to structural-integrity checks only; still dispatch fresh context, never inline self-critique.

### Step 3b: Assess Blast Radius

Every plan gets a blast-radius check. Read the criteria in [context/stress-test-triggers.md](context/stress-test-triggers.md) and assess whether this plan warrants a full formal stress-test via `/planning:devils-advocate`.

Present the assessment:

```
Blast radius: [LOW / MEDIUM / HIGH / CRITICAL]
Stress-test needed: [Yes — invoking /planning:devils-advocate / No — plan-reviewer sub-agent + research validation is sufficient]
Reason: <1-2 sentences>
```

If LOW and no triggers match: skip Step 4 (Formal Stress-Test) only. Continue at Step 4.5 (execution shape), then Steps 4.6-4.7 before presenting.
If MEDIUM or higher, or any trigger matches: proceed to Step 4 (Formal Stress-Test), then continue through Steps 4.5-4.7.

### Step 4: Formal Stress-Test and Research-Iterate (conditional)

This step runs only when the blast-radius assessment triggers it. Note: Step 3 (plan stress-test sub-agent) already ran. This is the deeper, formal version.

1. **Surface the cost.** Tell the user a formal `/planning:devils-advocate` run is starting in fresh
   context (another serial sub-agent, typically higher turn budget than Step 3) before dispatching.
2. **Dispatch `/planning:devils-advocate` via the Skill tool to a fresh-context sub-agent**. Keep the brief short: findings table, not a narrative. Hand it the plan (plus the Brief, the interview ledger `<memory_dir>/<topic-slug>/interview-checklist.md` when one exists, and any design artifacts), not your rationale for it. The producing main thread MUST NOT run the stress-test inline, for the same reason Step 3 dispatches: the context that wrote the plan carries the assumptions that produced its blind spots and converges on approval rather than detection. The stress-test skill runs its own multi-round process (assumption identification, evidence check, failure scenarios, operational gotchas) in that clean context; the main thread then verifies its findings against the actual code/files before acting on them. Sub-agent findings are synthesis, not ground truth

   **Audit judgment (untested):** at MEDIUM or higher blast radius, Step 3 and Step 4 may dispatch against
   the same plan draft in one message when Step 4's criteria read off the draft rather than Step 3's
   findings. Document when used; default remains serial.

3. **Evaluate findings**. If `/planning:devils-advocate` produces CRITICAL or HIGH findings:
   - Run targeted research to resolve the specific issues surfaced (invoke `/discovery:research` via the Skill tool if installed, or the strongest research capability available)
   - Update the plan based on new evidence. An adopted mitigation or update that displaces a user answer or adds an external effect follows "Plan changes after the Brief" below
   - Re-assess: does the updated plan survive scrutiny?

4. **Iterate if needed**. Repeat the Plan-Stress-Research cycle until the plan achieves HIGH confidence on all claims. See [context/research-iterate.md](context/research-iterate.md) for the loop protocol

5. **Escalation guard**. If 3 iterations haven't resolved the issues, present the remaining risks to the user explicitly. Don't loop indefinitely. The user may accept known risks or redirect the approach entirely

### Plan changes after the Brief

Applies to every change made after the Brief locked: Step 3 reviewer fixes, Step 4 research updates, and adopted `/planning:devils-advocate` mitigations. A change that (a) displaces an answer the user gave in the interview, or (b) adds a remote write, an irreversible action, or an externally visible artifact, is never folded into the plan silently:

- **Kind (a), ledger exists**: set that register row to `superseded-by-plan`, resolution `plan proposes: <new>; was: <old>`. A Brief-only interview has no register; list the change at Step 5 only.
- **Both kinds**: list the change at Step 5 in the "Displaced answers and new external effects" block.
- **Clearing a listed change**: every row of that block, superseded or not, needs an explicit reply to that row; a blanket "approve" clears none of them. For a superseded row, reconfirm sets `answered` with `proposal:: <new>; was:: <old>; answer:: accepted: <new>`, each value escaped as the exporter escapes it (a literal `;`, `\` or `|`; the grammar is in `surface/exporters.py`); reject restores the original answer and the plan drops the change.
- **Unattended run**: leave every listed change uncleared (superseded rows stay `superseded-by-plan`), report each as **USER-RESERVED**, and report the plan as unapproved.

### Step 4.5: Execution-Shape Analysis (parallelism. Default ON for multi-phase plans)

After the phase plan is locked but before Step 5 approval, compute the execution shape: which phases can run in parallel and which surface each phase runs on. **Default ON** for any plan with ≥2 phases; emits a one-line "fully sequential. Phase X gates phase Y" note when no parallelism opportunity exists. Skip entirely for single-phase plans or trivial fixes. Skipped = all-main-session execution, stated in one line.

The analysis steps, the file-overlap matrix, and the composition risks: [context/plan-template.md](context/plan-template.md) "Execution-shape analysis".

### Step 4.6: Tag unilateral decisions

Before Step 5 approval, walk the PLAN body + Handoff section and classify every decision NOT explicit in the brief: `[EXEC-SHAPE]` (your discretion within briefed scope) or `[FALLBACK]` (an invented contingency the brief didn't anticipate, for the user to confirm or override); briefed decisions get no tag. **Then apply the confidence gate**: DECIDE only when the basis is evidence captured this session (a codebase pattern read, a research finding, or a directly-on-point project convention) with no surviving reasonable alternative; everything below the bar, judgment calls, sizing guesses, either-would-work placements, routes to an interview round BEFORE the plan locks; hard-to-reverse decisions escalate early, per the Gates rule under Planning Process. Full gate, taxonomy, and presentation contract: [context/tag-decisions.md](context/tag-decisions.md). Surface every gate-passed decision at Step 5 in the "Decisions made (gate-passed)" TABLE (Decision | What it changes in the plan | Basis | Source) so the user can override before implementation. An adopted mitigation is classified per [context/tag-decisions.md](context/tag-decisions.md) "Adopted mitigation".

The outcome-gate criteria are under Planning Process, above. Apply them before presenting.

The approval presentation (Step 5) is with the gates at the start of Planning Process, so a compaction re-attach keeps it.

## Plan Mode Integration

Claude Code's built-in plan mode provides read-only enforcement. Claude reads files and runs diagnostic commands but doesn't edit source code. This is useful during the planning process:

- **During formulation (Steps 1-2):** plan mode ensures you're exploring safely while designing the approach. If you're already in plan mode when this skill triggers, stay in it
- **During stress-test (Step 4):** plan mode is appropriate. You're analyzing, not implementing
- **After approval (Step 5):** exit plan mode to begin execution. The user's approval is the gate

The skill does not automatically enter plan mode. The user controls permission modes. But if you're about to plan a complex change and are NOT in plan mode, suggest it: "Consider entering plan mode (`shift+tab`) for safe exploration while we design this."

Plan mode is also a natural moment for a **scoping confirm**. If you're entering plan mode for safe exploration during planning, treat it as a license to ask 1–4 questions that settle what this plan covers, as one numbered round before proposing it. The round renders via `AskUserQuestion` only when the plugin's `use_ask_user_question` user config (`${user_config.use_ask_user_question}`) is on and the questions are independent. Inline prose otherwise.

**Substantive rounds do not belong in plan mode.** A question that resolves *what we are building*, real tradeoffs, contested requirements, anything whose answer changes the plan's shape, routes to `/planning:interview` via the Skill tool, run with **plan mode off**, for two reasons. Mechanically, that skill's ask-time open-question register is a disk write, and plan mode's read-only enforcement blocks it, so questions get asked with nothing on disk holding them. Doctrinally, plan mode primes the run toward producing the plan when the job is still reaching shared understanding. Plan mode's round confirms scope; it is not a substitute for the interview. **Getting there is the user's move, not yours**. Symmetric to entering plan mode above: you do not toggle permission modes, so when plan mode is active and a substantive round comes due, say why and ask the user to exit it (`shift+tab`), then invoke the interview once they have. Do not invoke it from inside plan mode on the assumption the register write will survive. It will not.

## Boundary, the built-in `/plan` command

The command and this skill share a name, so "plan this" can mean either.

- **`/plan` (built-in command)**: `/plan [description]` enters plan mode, the read-only permission
  mode Plan Mode Integration above describes, optionally starting on the description; `/plan open`
  views the session plan. It is reserved for the person to run; the model does not invoke it.
- **This skill (marketplace plugin).** The planning discipline: stress-test, blast radius, an
  approval gate, and a persisted PLAN.md a cleared session can execute.

**Routing.** Where Plan Mode Integration says to suggest plan mode, offer it to the person: you
can run `/plan` (or press `shift+tab`) alongside this skill. Prefer this skill for the plan
itself. An unattended run records the offer in its output instead of asking.

**Mutation gate.** This skill writes PLAN.md and its checklist; `/plan` changes the permission
mode. This skill never toggles the mode on the person's behalf.

**Availability is never assumed.** This section states what to do when the person can run `/plan`,
never that it is present. The four-part records live in
[reference/native-plan.md](reference/native-plan.md).

## Boundary, the built-in `Plan` agent

Both produce an implementation plan, so "plan this" can also route to the subagent.

- **`Plan` (built-in subagent)**: a research agent that returns a step-by-step approach to its
  caller, skips CLAUDE.md, and runs no approval gate. It mutates nothing: it cannot write files. It
  is reached through the Agent tool's `subagent_type`.
- **This skill (marketplace plugin)**: the plan the person approves: stress-test, blast radius,
  decision gates, and a persisted PLAN.md.

**Routing.** When the built-in `Plan` agent resolves in this session, dispatch it for a throwaway
approach sketch or read-only context-gathering whose result feeds other work; use this skill when
the plan needs the person's approval or must outlive the session. This skill may dispatch `Plan`
to gather context, but the plan it presents is its own.

**Mutation gate.** `Plan` writes nothing. This skill writes PLAN.md and its checklist.

The four-part records live in [reference/native-plan-agent.md](reference/native-plan-agent.md).

## Plan Review Mode

Read [context/review-mode.md](context/review-mode.md) when invoked with `review`. It holds the review procedure and how it differs from `/planning:devils-advocate`.

## Final step: persist the approved plan for handoff

After the user approves the plan in Step 5, update the draft `<contract_dir>/<topic-slug>/PLAN.md` (default `docs/topics/`; persisted at Step 4.7) with any approval-round changes and its `Approval:` line (who approved and when, or the unattended basis Step 5 names), and write each `superseded-by-plan` row's result to the ledger once the user has replied to that row (reconfirmed or restored, per "Plan changes after the Brief"). The plan is not approved while any listed change lacks its reply: when an interview ledger exists, rerun `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-open-questions.sh" --ledger <ledger>` before handing off and require exit 0 (no `open` or `superseded-by-plan` row left); with or without a ledger, a listed change still lacking its reply means asking for it and not handing off. After writing the `Approval:` line, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-plan-outcome.sh" --approval-only <PLAN.md>` and require exit 0 before handoff; on an unattended run a failure means reporting the plan as unapproved. The script checks only that the line exists and its value is neither empty, the template placeholder, nor TBD; whether the recorded mandate is adequate stays a judgment. Derive `<topic-slug>` from the task or branch name (kebab-case, ≤40 chars; shared with `/planning:prd`, `/planning:interview`, `/planning:design`); roots, tier, and precedence resolve per the topic-docs binding [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md). PLAN.md is a contract document: under `contract_tier: branch` (the default), commit it on the task branch as it locks, so worktrees, clones, and reviewers see it, and let each implementation phase's plan updates ride the same commit as that phase's source changes; under `contract_tier: local` it lives in the self-ignored memory slice and is never staged. The PR-description paste is its only publication surface. It is the **living source of truth** for the stage. A fresh cleared session must be able to execute the plan reading only this file (plus the exploration/research artifacts in the topic's memory slice `<memory_dir>/<topic-slug>/`, default `.work/`).

**PLAN.md anatomy.** PLAN holds Brief + Plan; per-phase status lives in the phase tags (`[TODO]` /
`[DOING]` / `[DONE]`), never in a separate status block. Copy the skeleton from
[`templates/plan-md-anatomy.md`](templates/plan-md-anatomy.md) when writing the file at this step,
and read it again when a phase tag changes: it owns the section order, the tag grammar, and what
each section must contain for a cleared session to execute the plan from this file alone.

PLAN.md is a multi-turn shared artifact: re-read it from disk before every write. Another turn or agent may have modified it. Prefer appending or refining sections over wholesale rewrites.

Write the plan even for small changes. A cleared session or a fresh agent has only this file to work from.

**Close-out (PR time).** The contract slice is branch-lived; `/planning:plan` owns describing its close-out. Read [context/close-out.md](context/close-out.md) when invoked with `close-out`. It holds the four-step procedure, the ADR admission test, and the spec-container ship ritual.

**Mid-flight pivots:** when scope changes after approval, append a dated scope-change note to the affected PLAN.md section capturing the rationale, and strikethrough+link the obsolete content. Carry the pivot rationale in the commit message as well. The contract is branch-tracked, so git log is the history. Do not silently rewrite history.

**After writing, recommend:** clear context and begin implementation. The implementing session reads PLAN.md for the execution roadmap.

## What This Skill Does NOT Do

- **Does not replace `/planning:devils-advocate`**. That skill does adversarial stress-testing. This skill orchestrates when to invoke it based on blast radius
- **Does not replace research**. Research gathers external evidence. This skill uses research findings as input and may trigger additional research in Step 4 (research-iterate loop)
- **Does not replace built-in plan mode**. Plan mode is a permission mode. This skill is a planning discipline. They complement each other
- **Does not write code**. It produces a plan. Execution is a separate stage
- **Does not block execution**. It advises and gates on user approval. The user can always override
- **Does not make decisions**. It structures the decision for the user. The user approves or rejects

## Next

/implementation:implement executes the approved plan.

## Gotchas

- **The Step 3 reviewer brief is the lever, not the step.** If the user finds a gap in 5 seconds that the fresh-context reviewer missed, tighten the reviewer brief rather than adding an inline self-critique
- **Don't skip the prerequisite check.** Plans built without exploration miss existing patterns. Plans without research repeat mistakes others have solved. The prerequisite check is 30 seconds; the rework is 30 minutes
- **Scale the plan to the task.** A 50-line plan for a typo fix is over-engineering. A 3-bullet plan for a cross-cutting refactor is under-engineering. Match depth to blast radius
- **Don't confuse this skill with built-in plan mode.** Plan mode is a read-only permission mode. `/planning:plan` is a planning discipline. If a user types "plan this", they want the discipline, not the permission mode
- **Research-iterate has a ceiling.** 3 iterations max before escalating to the user. Infinite loops waste context on diminishing returns. If 3 rounds can't resolve it, the approach may need to change, not just the evidence
- **The plan is a proposal.** Never start executing without user approval. The approval gate is the point. It's where human judgment enters the loop
- **Step 4.5 (Execution shape) is default ON for ≥2-phase plans.** Skip explicitly only for single-phase plans or trivial fixes. Skipped = all-main-session execution, stated in one line
- **Open Decisions resolved BEFORE the plan body is authored.** Surfacing them mid-plan-body forces re-iteration during Step 5. The Step 1 prereq check enforces this. Scan the resume prompt + conversation + Brief for unresolved choices; a numbered Open Decisions round resolves cheaply
- **Sanity Check criteria are mechanically verifiable.** A future cleared session running the phase's sanity check needs an executable command (grep, Read assertion, build/test exit). Vague criteria invite inferential drift. Rewrite as the exact command a reviewer would run
