---
description: "Produce structured implementation plans with goal, approach, test strategy, blast radius, parallelism, and a user approval gate before any code is written, persisted as PLAN.md for fresh-session handoff. Use when: 'plan this', 'architect this', 'how should we implement', 'implementation plan', 'write a plan for this', 'what's the approach here', 'review this plan' (audits an existing plan's completeness), or proactively before executing without a formalized plan."
argument-hint: "[task description, 'review', or 'close-out']"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: plan
  summary: Produce a structured implementation plan with an approval gate
allowed-tools: ["Workflow(planning:plan-panel)"]
---

**Arguments.** `[task description, 'review', or 'close-out']`. e.g., /planning:plan add caching to query handlers, /planning:plan review, /planning:plan close-out

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined:

- Current branch, `git branch --show-current`
- Recent commits, `git log --oneline -5`
- Working tree status (empty = clean), `git status --porcelain | head -10`

Keep the pipe in the command: a read-time cap bounds nothing, since the Bash tool returns the full output first. Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as body Bash calls, not pre-compute lines: the pre-compute block runs as one shell invocation, and a worktree-isolated session refuses a compound command that contains git. Dated record: the worktree skill's [reference/gather-block.md](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/source-control/skills/worktree/reference/gather-block.md), "The pre-compute block runs as one shell invocation".

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Every implementation starts with a clear design, evidence, a test strategy, and user sign-off before any code is written. This is **not** Claude Code's built-in plan mode (`shift+tab`), which is a read-only *permission mode*; this skill is the *planning discipline* around it. It consumes exploration, research, and `/planning:design` (types, contracts, module boundaries, package topology) and produces a plan the user approves before execution. A 2-minute plan prevents a 20-minute rework cycle. Match planning depth to blast radius: a one-file fix gets a brief plan; a cross-cutting architecture change gets a full plan with stress-testing and research-iterate loops.

**Skip the plan when one sentence covers the change.** First try to write the whole diff as one sentence. The test passes when no design question is open and that sentence describes every edit. How this skill was reached decides what happens next:

- **Invoked proactively** (nobody asked for a plan): say the change fits one sentence, give the sentence, and skip the plan. No checklist, no plan-reviewer, no PLAN.md draft.
- **Invoked on an explicit request** (`/planning:plan`, "plan this"): say the change fits one sentence, give the sentence, and ask whether to plan it anyway. Write a plan only after a yes; then the Trivial row of the Step 2 scale table applies. A run with nobody to ask records the sentence and skips the plan.

## Emit checklist

For multi-step planning (almost always steps 1-5), copy `templates/checklist.md` to `<memory_dir>/<topic-slug>/plan-checklist.md` (default `.work/`) and tick each `- [ ]` as its step completes. Step 3 (fresh-context plan stress-test) and Step 5 (present for approval) are non-negotiable ticks. Stress-test before presenting, always.

**Skip when:** the one-sentence skip (Purpose) applied, so no plan is written. On a mid-flight `review` replan, append a dated scope-change note and revise the PLAN phases instead; do not spawn a second checklist file.

For **non-trivial / multi-layer** plans, Step 2 walks its design-default checklist **against the plan**: confirm the plan carries the resolved threads in PLAN.md's `## Design` section (and the design artifacts behind it) rather than re-deriving the axes. Configurability, extension points, observability, and testability are design threads owned by `/planning:design`'s "Design defaults"; type-collaboration shape is its type modeling. The principle and lifecycle-and-reversibility threads `/planning:design-handoff` requires are audited the same way: resolved, directional or tagged-deferred (at quality bar `prototype`, named as deferred); a missing one routes back through `/planning:design-handoff`, except under an early-exit `design-resolution.md`, which carries neither. Audit that the plan carries their resolutions, don't re-open them. When a phase is tagged for a phase-boundary review, confirm the Brief carries a `Quality bar:` line: that review rates at it ([context/plan-template.md](context/plan-template.md) "Phase Review tags"). Magic-literal hygiene stays plan's own review check against the consuming project's review conventions when it declares them.

## Action Router

Parse `$ARGUMENTS` to determine the action:

| Argument | Action | Use case |
|----------|--------|----------|
| *(empty)* | **Smart default** | If a plan exists in conversation, offer to finalize/review; if exploration and research are done, start planning; otherwise suggest prerequisites |
| `<task description>` | **Full planning** | Run the complete planning process for the described task |
| `review` | **Plan review** | Critique an existing plan for completeness, feasibility, and alignment with the project's conventions |
| `close-out` | **Close-out** | Run the PR-time close-out (below) for an approved plan: publish PLAN.md to the PR body and the linked issue, record durable decisions as an ADR, file follow-ups to the tracker |

## Planning Process

### Gates

These hold after a compaction re-attach. Later steps say how to carry them out.

**Verification.** Claim: after auto-compaction Claude Code re-attaches each skill's most recent invocation keeping its first 5,000 tokens, within a shared 25,000-token budget. Basis: https://code.claude.com/docs/en/skills (auto-compaction paragraph); `tests/reattach-slice.test.sh` stands in for the 5,000 tokens with the first 20,000 bytes. As-of: 2026-09-29. Recheck when that paragraph changes either figure, or when the page stops describing a per-skill re-attach.

- **Reviewer.** Before assessing blast radius, dispatch a fresh-context plan-reviewer sub-agent for any plan you present. The producing thread does not self-attack the plan inline. A change skipped under the one-sentence rule (Purpose) has no plan to review.
- **Hard-to-reverse decisions escalate EARLY** regardless of confidence. Below-bar judgment calls go to an interview round before the plan locks.
- **Agent teams.** Route a phase to an agent team only when the parallel-safe workers must message each other and agent teams are enabled; otherwise use sub-agent workers or sequential. Teammates are not worktree-isolated, so disjoint file ownership is mandatory.

### Step 4.7: Outcome gate (before Step 5. Verify the PLAN, not a recap)

Before presenting at Step 5, persist the composed plan as a **draft** to `<memory_dir>/<topic-slug>/PLAN.md` (default `.work/`; the final-persist step updates the same file after approval and applies `plan_store`; the draft is never published), then check the artifact against binary criteria read off it, not a holistic "is the plan good?" recap. Any FAIL → fix the PLAN before presenting.

Run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-plan-outcome.sh" <PLAN.md>` and require exit 0. It prints one `criterion=<name> status=<pass|fail>` line per mechanical criterion:

- **Every phase has ≥1 `Sanity Check`**, counted per phase section.
- **Every phase carries a valid status tag**. Each `### Phase N:` ends in `[TODO]`, `[DOING]`, or `[DONE]`.
- **Every unilateral decision has a table row**. When the plan carries an `[EXEC-SHAPE]` / `[FALLBACK]` tag from Step 4.6, the "Decisions made (gate-passed)" table (`| Decision | What it changes in the plan | ...`) is in PLAN.md with at least one row. A tag may carry an id (`[EXEC-SHAPE D4]`) that its row starts its first column with; the script fails a tag id with no row and a row id no tag cites, and prints `mapped=<n>` (see [context/tag-decisions.md](context/tag-decisions.md) "Presentation contract").
- **Blast radius assessed**. A Blast-radius line naming LOW, MEDIUM, HIGH, or CRITICAL exists (from Step 3b).
- **Planned breakage is well formed**. Each `**Planned breakage:**` line (the optional per-phase line in [context/plan-template.md](context/plan-template.md)) sits in a phase section, names a kind of `build`, `tests` or `lint`, a later `### Phase` heading to stay red until, and the failing paths or test filter: the `planned-breakage` criterion. A plan with no such line passes.
- **Paths are portable**. No drive-letter path and no `/Users/<name>` or `/home/<name>` path, since a published PLAN.md is read on other machines; a deliberate example carries `<!-- path-example -->` on its line.

Checked by reading, or by their own script:

- **Every brief acceptance criterion maps to a phase, and no phase does Out-of-scope work**. Walk the Brief's Acceptance criteria and Out-of-scope sections: each criterion lands in at least one phase, and no phase does work the Brief lists as Out-of-scope.
- **Each tag has its own row**. Every tagged decision appears in that table with its what-it-changes column filled; below-bar decisions were interviewed, not decided. The script maps only tags that carry an id; a bare tag passes with a `warning=bare-tag` line, so map those by reading.
- **Displaced answers are listed at Step 5**. When an interview ledger exists, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-open-questions.sh" --ledger <ledger>`. It passes when the verdict reports `open=0` and `superseded=N` (exit 1 is expected when N > 0) and every id on the ledger's `| superseded-by-plan |` rows (the verdict prints only the count) appears in the Step 5 "Displaced answers and new external effects" block.

This self-check does NOT replace the human approval at Step 5; the user is the terminal gate.

**The gate does not vanish when no human is present.** On an unattended run (a routine, a dispatched worker, any session with nobody to answer), approval proceeds only under a standing mandate that covers this plan, recorded in PLAN.md's `Approval:` line: the mandate, who granted it and where, and the review surface that stands in for the human (for example the PR). With no such mandate, stop here and report the plan as unapproved. Listed changes stay uncleared either way ("Plan changes after the Brief", its "Unattended run" bullet). The default run above does not look for the `Approval:` line; the final persist step checks it with `--approval-only`.

### Step 5: Present for Approval

The plan is a proposal, not a commitment. The user approves, modifies, or rejects it before execution begins. Unattended approval follows the Gates rule above.

**Include in the presentation:**

1. The structured plan (Step 2, updated by Steps 3-4 if applicable)
2. Blast-radius assessment (Step 3b)
3. Stress-test summary (Step 4, if run), or "Skipped: blast radius LOW, no triggers matched"
4. **Execution shape** (Step 4.5): the four-dimension table, parallelism shape AND per-phase routing table, with each `multi-shape` phase's attempt constraints and selection rule. Skipped for single-phase plans
5. **Displaced answers and new external effects** ("Plan changes after the Brief"). One row per change: `Q<N>` or `none`, what the user said, what the plan now proposes, the new external effect, and the source (`reviewer fix`, `research update`, or `stress-test finding`). Omit the block when empty. The approval request names every row as needing its own reply
6. **Decisions made (gate-passed)** (Step 4.6). TABLE per [context/tag-decisions.md](context/tag-decisions.md) "Presentation contract": `Decision | What it changes in the plan | Basis (evidence) | Source`, one row per gate-passed `[EXEC-SHAPE]` / `[FALLBACK]` tag, written for a cold reader (no session shorthand). Below-bar decisions never appear here. An empty section ("no unilateral decisions. Every PLAN item traces to brief") is valid
7. **Explicit approval request**: "Approve this plan to proceed to execution, or provide feedback to revise. Anything tagged `[EXEC-SHAPE]` or `[FALLBACK]` above is /planning:plan's discretion. Flag any you want changed."
8. **Highest-leverage replies**: close with 2-4 pre-drafted one-line revision replies, one per flagged close call or gate-passed decision, each a copyable sentence that flips exactly that decision (e.g. "Switch phase 2 to the queue-based alternative"). The user's cheapest possible reaction is pasting one back; a presentation whose flagged decisions have no pre-drafted flip line makes the user compose the revision themselves

**Presentation order: tweak-likelihood first.** Lead with what the user is most likely to change: data-model/schema choices, type interfaces and public contracts, and user-facing surfaces (flag close calls with their alternatives); mechanical, low-judgment work goes last. Phase EXECUTION order stays as `phase_order` set it in Step 2. After the presentation, offer an interactive plan view (phases, dependencies, acceptance criteria, a reply that names the phases to change, sent to this session through `session-bridge` when connected). `PLAN.md` stays the record. Build it only with `${CLAUDE_PLUGIN_ROOT}/scripts/build-view.mjs`, never hand-written; the publish destination comes from the `medium` cascade key. Procedure and data shape: [`${CLAUDE_PLUGIN_ROOT}/reference/rendered-view.md`](${CLAUDE_PLUGIN_ROOT}/reference/rendered-view.md).

If 2–4 named alternatives surfaced during the stress-test, present them side by side via `AskUserQuestion` when the plugin's `use_ask_user_question` user config (`${user_config.use_ask_user_question}`; unexpanded or empty means off) is on, numbered inline prose otherwise. For open-ended approval (single proposal, no alternatives) use prose.

**After approval. Branch-name check:** verify the branch name matches the approved scope before handing off.

| Current branch | Action |
|----------------|--------|
| `main` or `master` | STOP. Cannot implement on the default branch. Suggest `git checkout -b <type>/<topic-slug>` derived from the plan topic + conventional prefix |
| Auto-generated or placeholder name | Derive the name from the plan: `<type>/<topic-slug>` (`feat/`, `fix/`, `refactor/`, `chore/`, etc.). Suggest the rename; let the user execute unless the environment is isolated (worktree or remote session), where renaming directly is safe |
| Matches a conventional prefix (`feat/`, `fix/`, etc.) | OK. No action needed |

Derive the type from plan content: new capability → `feat/`, bug fix → `fix/`, restructuring → `refactor/`, tooling/maintenance → `chore/`, docs-only → `docs/`, tests-only → `test/`, build config → `build/`, performance → `perf/`.

**After approval:** suggest the consuming environment's implementation workflow (an `/implementation:implement`-style skill if it ships one, otherwise structured inline execution reading PLAN.md). If implementation diverges from the plan, chain back to `/planning:plan review` to re-plan rather than pushing through a broken approach.

Step 5, the approval gate, is placed with the gates above so a compaction re-attach keeps it. The approval gate is the point.

### Step 1: Prerequisite Check

Prefer the simplest plan that works and keep each step's changes surgical. Before planning, verify:

- **Is the effort coherent enough to plan?** If the work is too big to hold at once AND still too foggy to phrase as sharp decisions (questions you can't yet state, not just unanswered ones), `/planning:plan` is premature. Guide the user to `/planning:wayfind` when an interview of the effort already outgrew one session, else to `/planning:interview` first; recommend, never auto-switch. Skip when the effort is scoped and the open items are answerable questions
- **Is product intent clear?** For product-driven feature work (new user-facing surface, business-driven change, cross-team initiative), check that `<memory_dir>/<topic-slug>/PRD.md` (default `.work/`) exists OR that problem/users/success-metrics are crisp in conversation. If fuzzy, suggest `/planning:prd` first. Skip for engineering-internal work (refactors, infra, hooks, conventions, bug fixes)
- **Has exploration been done?** If the conversation holds no exploration findings for the area, suggest the exploration capability first (`/discovery:explore` if enabled)
- **Has research been done?** If technical claims the plan relies on lack external research, suggest the research capability first (`/discovery:research` if enabled)
- **Has `/planning:design` been done? (blocking gate)**. Classify design significance:

| Tier | Signals | Requirement |
|------|---------|-------------|
| **A. Design-significant** | New types/contracts, new module or library, package topology change, cross-module integration, data model change, multi-tenant posture | **Blocking:** full or light `/planning:design` + its handoff gate (`design-threads.md` all RESOLVED / directional / TAGGED-DEFERRED) |
| **B. Light design** | 2–5 files, one new type, localized contract tweak | **Blocking:** `design/design-resolution.md` with `outcome: early-exit`, `tier: B`, and its type sketch (a `type-inventory.md` alone is not the gate artifact) |
| **C. No design** | Single-file bugfix, config/doc/markdown, rename, hook text, pure test addition | **Blocking:** `design/design-resolution.md` with `outcome: early-exit` + reason (gate always evaluated) |

Check `<memory_dir>/<topic-slug>/design/` (default `.work/`) for design artifacts OR `design-resolution.md`. If Tier A/B requirements are unmet, **stop**. Offer `/planning:design` or document the early-exit artifact; when you document it here, also write PLAN.md's one-line `## Design` record naming the early exit and its reason, plus, for Tier B, a `### Contracts` subsection quoting the type sketch. The user may override via `AskUserQuestion` only when they explicitly accept skipping design exploration. Do not re-derive design inline when design-significant.

- **Is the scope clear?** If the task is ambiguous ("improve performance" rather than "add a cache to the GetOrderById query handler"), ask clarifying questions before planning. Ask every question whose prerequisites are settled as one numbered round, each with a recommendation; a question that depends on another still open waits for the round after its prerequisite resolves. Render the round via `AskUserQuestion` only when the plugin's `use_ask_user_question` user config is on and the round is independent questions that fit one `AskUserQuestion` call (the per-call question limit: <https://code.claude.com/docs/en/agent-sdk/user-input#limitations>, as of 2026-10-11; recheck when that section changes the per-call question limit). Inline prose otherwise
- **Open Decisions surfaced BEFORE plan body**. Scan the resume prompt, conversation, and Brief for unresolved decisions (scope cuts, technique choices, ordering, exclusions) the plan body would otherwise lock inline. Surface every decision whose prerequisites are settled as a numbered "Open Decisions" block with research-backed recommendations + trade-offs per decision. A decision whose option set depends on another still open waits for the round after its prerequisite resolves; render via `AskUserQuestion` under the same conditions as above (the per-call question limit linked above). Single-prompt inline prose otherwise

If prerequisites are missing, state what's needed and offer to run the prerequisite skill; don't silently skip this step. The `/planning:prd` check is **additive**, not blocking: proceed if product intent is locked elsewhere or the work is engineering-internal.

### Step 2: Formulate the Plan

#### Ground in consumer standards (first formulation input)

Before formulating, resolve the consumer's standards and load what this task touches:

- **Resolve the index** via the "Resolution ladder" section of the plugin's contract binding [`${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md`](${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md). The ladder (absent-index inference, offer-to-persist, ask-once) lives there, not here. Zero unprompted writes, ever.
- **Match** the task's surfaces (ecosystems touched, cross-cutting concerns) against the index rows' `Applies when` clues.
- **Pull selectively**: only matched files, and within them only the sections this task needs. Never re-pull ambient content (auto-loaded `CLAUDE.md`, fired `.claude/rules` directives). Post-compaction context and a new task both count as NOT ambient. Re-resolve per task.
- **Depth rides the plan-scale table below**. A trivial plan takes no standards fetch beyond ambient context; larger scales ground the surfaces they touch. There is no grounding flag.
- **Name provenance** when a personal-layer rule (a `*.local.md` overlay or the user-global layer) materially shapes the plan.
- **Broken index row** → surface it and offer the fix. Never silent. **Always compare** the index's `standards-contract` frontmatter to the binding's own version; on any mismatch, degrade per the binding's tolerant-reader rule AND report the skew in the plan (older: best-effort + "index at vX, contract at vY. Re-run setup"; newer: best-effort + "update the plugin", no migration offer).
- The plan **cites the standards sections loaded** for the surfaces it touches (the template's "Standards grounding" element), or states why grounding was skipped (scale tier).

**Multi-angle panel (opt-in).** For a hard or wide plan, when the user asks for it or `/multi-agent:assess` returns `workflow`, formulate through the `planning:plan-panel` workflow instead of one draft, behind a Workflow availability gate with this single-plan flow as the fallback. Read [context/plan-panel.md](context/plan-panel.md) before launching. Its synthesized plan still goes through Step 3 onward and the Step 5 approval gate.

Produce a structured plan using [context/plan-template.md](context/plan-template.md):

- **Goal**: what we're trying to achieve and why
- **Approach**: the specific steps, in order
- **Test strategy**: how we'll verify the changes work. When the `testing` plugin is enabled, `/testing:plan`'s file-type classification table decides which test type each kind of change needs (unit / integration / e2e / architecture / analyzer); **invoke `/tdd:principles` via the Skill tool (if enabled)** for what to test, which style fits, and when to mock; otherwise apply standard test-design judgment. TDD (Red-Green-Refactor) is the default unless genuinely impractical. **Name the test boundaries**: the public interfaces the tests will drive, and for each whether it exists or is being introduced (prefer an existing interface over one introduced for testability alone). Step 5's approval settles them, so implementation writes no test against a boundary the plan never named; on an unattended run, a boundary chosen during implementation that this section did not name is a deviation, logged for PR-time review (`DEVIATIONS.md` beside `PLAN.md` in the memory slice), never silently taken
- **Files affected**: what gets created, modified, or deleted
- **Alternatives considered**: what was rejected and why, plus a one-line switch condition per alternative: the observable fact that would make it the better choice, so a reviewer or later phase can flip the decision without re-deriving the analysis
- **Risks and mitigations**: what could go wrong

Scale the plan to the task:

| Task scale | Plan depth |
|-----------|-----------|
| Trivial (1 file, well-understood) | 3-5 bullet points, when the one-sentence skip (Purpose) did not apply |
| Small (2-5 files, clear scope) | Brief plan. Goal, steps, test strategy |
| Medium (5-15 files, some unknowns) | Full plan with alternatives and risks |
| Large (cross-cutting, architectural) | Full plan + stress-test + research-iterate |

Per-scale examples: [context/plan-template.md](context/plan-template.md) "Choosing the Right Scale".

**Tracker-write phases:** when any phase ends in creating a work item (e.g. `/work-items:track add`), the plan body MUST follow [context/plan-template.md](context/plan-template.md) "Phase-entry checks for tracker writes": search-before-create as the first work item, an explicit pivot path for the match case, and the search outcome captured in the phase Sanity Check.

**Pre-flight consumer check**. When a phase migrates a contract (frontmatter schema, JSON schema, public API surface, env-var shape, file format, exported function signature), list "Identify consumers" as its FIRST work item: `Grep` + `Glob` for scripts/hooks/workflows/sibling components parsing the contract surface; document parse paths. Migration work items follow. Full pattern: [context/plan-template.md](context/plan-template.md) "Pre-flight consumer check".

**Sub-topic promotion check**. When a phase grows beyond ANY of (>5 distinct work items / >300 LOC delta / own exploration or research need / 2+ sub-phases of its own / independent commit boundary), recommend promoting it to its own topic directory with its own PLAN.md. Criteria: [context/plan-template.md](context/plan-template.md) "Sub-Topic Promotion Trigger".

**Phase merge floor**. A phase of one file and a few lines with no verification need of its own merges into the adjacent phase it serves. Every phase pays a full dispatch, sanity-check, commit and plan-mark cycle, which a one-line phase does not earn. The threshold is judgment (nearest anchor: Step 4.5's ~100 LOC parallelism floor); keep a small phase separate when it is its own commit boundary or needs its own Sanity Check.

**File inventory for large-scope plans**. When a plan or phase touches ≥10 files, emit a checkbox inventory table per phase (file, action, rationale), ticked as each file is processed. Include KEEP rows for files audited and deliberately left unchanged. Format: [context/plan-template.md](context/plan-template.md) "File Inventory".

**Sanity-check verifiable-criterion enforcement**. Every phase ends with at least one `**Sanity Check:**` bullet that is mechanically verifiable (a specific grep, file Read assertion, build exit code, test exit code, or runtime probe). Never vague (~~"documented appropriately"~~, ~~"behaves as expected"~~, ~~"all cases covered"~~): rewrite as exact commands a fresh session can execute without inferential judgment, so each phase can be verified green at its own boundary rather than only at the end; this is what backs implementation's every-step-lands-green expectation. Format: [context/plan-template.md](context/plan-template.md) "Sanity-Check Format".

**Build-technique selection**. BEFORE ordering phases, pick the de-risking technique by the task's *uncertainty type*, not by habit. A design or viability unknown (*might abandon*) resolves **upstream**: `/planning:design` for design-significant questions, a throwaway `/prototype:pressure-test` spike (if enabled) or research for raw feasibility; the plan **consumes that outcome** rather than re-deriving it. Plan's own call is the *kept* slice: a tracer bullet / walking skeleton when committed to ship and the risk is integration. When an upstream feasibility spike and ship-commitment both hold, sequence the kept tracer-bullet slice after the spike's outcome lands. Trivial / pure-horizontal work skips all techniques.

**Design section audit**. When PLAN.md carries a `## Design` section (written by `/planning:design-handoff`), keep it as written and audit every phase against it: a phase that builds part of the design names the subsection it implements (module layout, contracts, variation verdicts), and no phase departs from a recorded contract, boundary, or verdict. A needed departure routes back to `/planning:design`. **Every external integration has a verdict**: list each external system a phase touches and check `### Variation verdicts` names it with abstract now, contain now, or leave inline ([`${CLAUDE_PLUGIN_ROOT}/reference/variation-points.md`](${CLAUDE_PLUGIN_ROOT}/reference/variation-points.md)); one without a verdict, or left inline, routes back to `/planning:design`, and so does a phase that puts a provider's name into domain code, storage, or a public contract under a contain verdict. Design-significant work (Step 1, Tier A or B) with no `## Design` section goes back through `/planning:design-handoff`, which writes it from the tier's gate artifact: `design-threads.md` for Tier A, `design-resolution.md` for Tier B.

**Phase order (`phase_order`)**. After build-technique selection, order the phases by the `phase_order` setting. Resolve it lowest layer first: the default `composed`; the plugin's `phase_order` user config (`${user_config.phase_order}`); then the `phase_order` key of the repository's `docs/conventions/planning.yaml`, which wins when set. Read that file only when the working directory's git root is neither `$HOME` nor an ancestor of it; otherwise skip the repository layer and say so. A literal unexpanded `${user_config.phase_order}` means the user layer is unset. A value outside `composed`, `subtraction-first` and `riskiest-first` is named with its file (or user config), key and value, and that layer is dropped: a valid higher layer still wins, with none the key is `composed`, and a lower layer's value never replaces it. Report one line naming the value and its layer, e.g. `phase_order: riskiest-first (docs/conventions/planning.yaml)`. Keys and layers: [`${CLAUDE_PLUGIN_ROOT}/reference/config.md`](${CLAUDE_PLUGIN_ROOT}/reference/config.md).

- `composed`: (1) remove the dead code the change touches; a bug fix skips this step and keeps its diff to the fix. (2) The integration slice: when the kept technique is a tracer bullet or walking skeleton on multi-layer work, it is the first building phase and its `**Sanity Check:**` is an end-to-end runtime probe. (3) The riskiest remaining unknown. (4) Scaffold. (5) The remaining features.
- `subtraction-first`: dead-code removal, then scaffold, then features, with no integration or risk step pulled forward.
- `riskiest-first`: the step whose failure would invalidate the most downstream work goes first, then the rest in dependency order.

For the removal step, invoke `/code-tidying:audit-dead-code` through the Skill tool, scoped to the paths the change touches, when it is among the available skills; otherwise list the candidates from the plan's own reads (unreferenced functions, files or exports in the touched paths, each with the search that found no caller). Removal stays its own phase. Dependencies still win: a phase that needs another's output follows it under every value. Pure-horizontal work (migration, lint, doc pass) has no integration slice to place.

**Stub phase (`scaffold_stubs`)**. Resolve `scaffold_stubs` with the same layers, root rule and report line as `phase_order`: the default `false`, then `${user_config.scaffold_stubs}`, then the `scaffold_stubs` key of `docs/conventions/planning.yaml`. Only the bare booleans `true` and `false` are valid; a quoted `"true"`, `yes` or any other value is named with its file (or user config), key and value, and that layer is dropped: a valid higher layer still wins, otherwise `false`, never a lower layer's value. With `true`, add one phase that commits the stub files: right after `phase_order`'s dead-code removal step, or first when the plan has none (`riskiest-first`, or a bug fix under `composed`). Take the files and signatures from the design's `## Stub scaffold` section when `/planning:design` wrote one; otherwise derive them from the interfaces the plan introduces. Each stub body is the language's ordinary not-implemented form. When the stubs leave the build, the tests or the lint red (an existing test now reaches a stub that throws, a linter flags the unused parameters), the stub phase carries a `**Planned breakage:**` line naming the stub paths and the later phase that makes them pass ([context/plan-template.md](context/plan-template.md) "Planned breakage"). With `false`, add no stub phase.

**Redesign work items (`integration_posture`)**. This key belongs to the implementation plugin, whose user config this skill cannot read, so read only the repository layer: the `integration_posture` key of the consumer's `docs/conventions/implementation.yaml`, under the same root rule as `phase_order` (git root neither `$HOME` nor an ancestor of it; otherwise skip the file and say so). A missing file or key reads as `by-kind`. A value outside `by-kind`, `day-one` and `minimal` is named with its file, key and value and dropped, so the key reads as `by-kind`. Report one line naming the value and its source, e.g. `integration_posture: day-one (docs/conventions/implementation.yaml)`. Apply it by the change's kind: under `by-kind` a feature takes a day-one redesign and a fix or config change stays minimal; `day-one` gives the redesign to features, fixes and config changes alike; `minimal` gives none of them a redesign; a refactor keeps the plan's scope with behavior unchanged under every value. A day-one redesign reshapes the code the change lands in so the result reads as though the new behavior had been in the original design (moving, renaming, merging or splitting existing parts rather than adding a branch beside them). When the kind takes it, write that reshaping as explicit work items in the phases that touch the code, each naming the files and the restructuring, so `/implementation:implement` executes it as plan work rather than deciding its own scope. Under `minimal`, or for a kind that stays minimal, write no reshaping beyond what the change needs.

**Measurable-goal baseline capture**. When the brief states a measurable goal (perf / latency / throughput / allocation / complexity / coverage keywords), capture a baseline **by default** BEFORE the change: invoke `/verification:measure performance baseline` (perf) or `/verification:measure metrics baseline` (code metrics) via the Skill tool if enabled, or measure the pre-change state manually; this skill routes, never reimplements. Store the raw capture under `<memory_dir>/<topic-slug>/baselines/` (default `.work/`; machine-bound, never committed), then record the distilled baseline value + target in PLAN.md. After the change, re-measure and compare through the same route (its `compare` phase reads the stored baseline, or re-measure manually) and record the comparison in PLAN.md as distilled values only. PLAN never cites the memory-slice capture path, which would dangle outside the writing checkout. Never claim an improvement without a baseline.

### Step 3: Plan Stress-Test

Apply the reviewer rule under Planning Process before blast radius or presentation. The producing main thread MUST NOT self-attack the plan inline: the model that just wrote the plan rubber-stamps it. Where the plan is high-stakes and correlated blind spots are the risk, prefer a cross-vendor advisor **when one is enabled and set up** (e.g. the OpenAI Codex plugin, when its documented surface can take this artifact, invoked per its own docs), with the fresh-context plan-reviewer sub-agent as the stated fallback, never a route to a command that may not resolve (per `docs/plugin-philosophy.md` "Fresh-eyes checkpoints" in the marketplace repository).

1. Gather the plan draft + design artifacts (or `design-resolution.md`) + the Brief
2. **Surface the cost.** Tell the user, in one sentence, that a fresh-context plan review runs now whatever they answer: one bounded sub-agent (default `effort: medium`, capped turns).
3. Dispatch the plugin's **`plan-reviewer`** agent (`agents/plan-reviewer.md`) with the prompt from [context/plan-reviewer.md](context/plan-reviewer.md). Do not substitute a generic read-only sub-agent, and pass no `effort` on the call: the agent definition carries the reviewer's bounded `effort` and `maxTurns` (the effort record in `agents/plan-reviewer.md`). A complete report ends with its `### Summary` counts, or is the literal `No plan gaps found.` for a clean pass; treat any other return as incomplete whether or not a partial marker is present (older clients do not mark a `maxTurns` stop): resume it (or re-dispatch with a narrowed brief); never treat a partial table as a clean pass.
4. **Verify reviewer findings** against the actual code/files before applying fixes. Sub-agent findings are synthesis, not ground truth
5. Fix every confirmed gap BEFORE proceeding; never present a plan with known gaps. A fix that displaces a user answer or adds an external effect follows "Plan changes after the Brief" below

Trivial single-file plans (3–5 bullets, no new types): the reviewer brief may be shortened to structural-integrity checks only; still dispatch fresh context, never inline self-critique.

### Step 3b: Assess Blast Radius

Every plan gets a blast-radius check. Read [context/stress-test-triggers.md](context/stress-test-triggers.md) and assess whether this plan warrants a formal stress-test via `/planning:devils-advocate`.

Present the assessment:

```
Blast radius: [LOW / MEDIUM / HIGH / CRITICAL]
Stress-test needed: [Yes — invoking /planning:devils-advocate / No — plan-reviewer sub-agent + research validation is sufficient]
Reason: <1-2 sentences>
```

If LOW and no triggers match: skip Step 4 (Formal Stress-Test) only. Continue at Step 4.5, then Steps 4.6-4.7 before presenting. If MEDIUM or higher, or any trigger matches: proceed to Step 4, then Steps 4.5-4.7.

### Step 4: Formal Stress-Test and Research-Iterate (conditional)

Runs only when the blast-radius assessment triggers it; the deeper, formal version of Step 3.

1. **Surface the cost.** Tell the user a formal `/planning:devils-advocate` run is starting in fresh context (another serial sub-agent, typically higher turn budget than Step 3) before dispatching.
2. **Dispatch `/planning:devils-advocate` via the Skill tool to a fresh-context sub-agent**. Keep the brief short: findings table, not a narrative. Hand it the plan (plus the Brief, the interview ledger `<memory_dir>/<topic-slug>/interview-checklist.md` when one exists, and any design artifacts), not your rationale for it. The producing main thread MUST NOT run the stress-test inline, for the same reason as Step 3. Verify its findings against the actual code/files before acting on them; sub-agent findings are synthesis, not ground truth

   **Audit judgment (untested):** at MEDIUM or higher blast radius, Step 3 and Step 4 may dispatch against the same plan draft in one message when Step 4's criteria read off the draft rather than Step 3's findings. Document when used; default remains serial.

3. **Evaluate findings**. If `/planning:devils-advocate` produces CRITICAL or HIGH findings:
   - Run targeted research on the specific issues (invoke `/discovery:research` via the Skill tool if enabled, or the strongest research capability available)
   - Update the plan based on new evidence. An adopted mitigation or update that displaces a user answer or adds an external effect follows "Plan changes after the Brief" below
   - Re-assess: does the updated plan survive scrutiny?

4. **Iterate if needed**. Repeat the Plan-Stress-Research cycle until the plan achieves HIGH confidence on all claims. Loop protocol: [context/research-iterate.md](context/research-iterate.md)

5. **Escalation guard**. If 3 iterations haven't resolved the issues, present the remaining risks to the user explicitly. The user may accept known risks or redirect the approach entirely

### Plan changes after the Brief

Applies to every change made after the Brief locked: Step 3 reviewer fixes, Step 4 research updates, and adopted `/planning:devils-advocate` mitigations. A change that (a) displaces an answer the user gave in the interview, or (b) adds a remote write, an irreversible action, or an externally visible artifact, is never folded into the plan silently:

- **Kind (a), ledger exists**: set that register row to `superseded-by-plan`, resolution `plan proposes: <new>; was: <old>`. A Brief-only interview has no register; list the change at Step 5 only.
- **Both kinds**: list the change at Step 5 in the "Displaced answers and new external effects" block.
- **Clearing a listed change**: every row of that block, superseded or not, needs an explicit reply to that row; a blanket "approve" clears none of them. For a superseded row, reconfirm sets `answered` with `proposal:: <new>; was:: <old>; answer:: accepted: <new>`, each value escaped as the exporter escapes it (a literal `;`, `\` or `|`; the grammar is in `surface/exporters.py`); reject restores the original answer and the plan drops the change.
- **Unattended run**: leave every listed change uncleared (superseded rows stay `superseded-by-plan`), report each as **USER-RESERVED**, and report the plan as unapproved.

### Step 4.5: Execution-Shape Analysis (parallelism. Default ON for multi-phase plans)

After the phase plan is locked but before Step 5 approval, compute the execution shape: which phases can run in parallel and which surface each phase runs on. **Default ON** for any plan with ≥2 phases; emit a one-line "fully sequential. Phase X gates phase Y" note when no parallelism opportunity exists. Skip for single-phase plans or trivial fixes, stating in one line that execution is all main-session.

A multi-phase plan opens this analysis with the table below, its four rows in this order. Fill every row. A dimension with nothing to report gets `n/a: <reason>`; an empty cell or a removed row is incomplete.

| Dimension | What to write | Example `n/a` |
|---|---|---|
| **Gates** | The work the other phases wait on (a schema migration, a new interface), and the phases blocked behind it. | `n/a: every phase can start from the base branch` |
| **Shared state** | Each file, table or config key that two phases would both write. Split shared state before serializing: hand each phase its own file, key range or module, and make two phases wait on each other only for a rule that has to hold across both writes. | `n/a: no file appears in two phases` |
| **Disjoint streams** | Groups of phases that change separate modules, packages or processes, and so can run at the same time. | `n/a: every phase edits the invoicing module` |
| **Worker count** | The smallest number of workers that keeps every stream safe. A count of one names the reason, for example that every phase edits the same migration script. | Never `n/a`: the count is at least one. |

The analysis steps, the file-overlap matrix, and the composition risks: [context/plan-template.md](context/plan-template.md) "Execution-shape analysis". Each routing row also carries a `Model` (`sonnet`, `opus` or `frontier`) that decides which implementer agent dispatch uses; eligibility rules are in that file's "Per-phase routing table".

Each routing row also carries an `Attempts` cell. Mark a phase `multi-shape` when this step finds more than one plausible shape the design left open for it; leave it blank otherwise (one attempt). A marked phase's body lists one stated constraint per attempt and the selection rule (`first pass`, `rank all`, or `best-of` with its criteria), both written now, before any dispatch. The mark reads no setting: whether a marked phase gets several attempts is decided at dispatch. Format: that file's "Per-phase routing table".

### Step 4.6: Tag unilateral decisions

Before Step 5, walk the PLAN body + Handoff section and classify every decision NOT explicit in the brief: `[EXEC-SHAPE]` (your discretion within briefed scope) or `[FALLBACK]` (an invented contingency the brief didn't anticipate, for the user to confirm or override); briefed decisions get no tag. **Then apply the confidence gate**: DECIDE only when the basis is evidence captured this session (a codebase pattern read, a research finding, or a directly-on-point project convention) with no surviving reasonable alternative; everything below the bar (judgment calls, sizing guesses, either-would-work placements) routes to an interview round BEFORE the plan locks; hard-to-reverse decisions escalate early, per the Gates rule. Full gate, taxonomy, and presentation contract: [context/tag-decisions.md](context/tag-decisions.md). Surface every gate-passed decision at Step 5 in the "Decisions made (gate-passed)" TABLE (Decision | What it changes in the plan | Basis | Source). An adopted mitigation is classified per [context/tag-decisions.md](context/tag-decisions.md) "Adopted mitigation".

Then apply the Step 4.7 outcome-gate criteria (under Planning Process, above) and present per Step 5. The approval presentation (Step 5) is with the gates at the start of Planning Process, so a compaction re-attach keeps it.

## Plan Mode Integration

Built-in plan mode enforces read-only work during planning:

- **During formulation (Steps 1-2):** if already in plan mode when this skill triggers, stay in it
- **During stress-test (Step 4):** plan mode is appropriate
- **After approval (Step 5):** exit plan mode to begin execution. The user's approval is the gate

The skill does not enter plan mode itself; the user controls permission modes. Before planning a complex change outside plan mode, suggest it: "Consider entering plan mode (`shift+tab`) for safe exploration while we design this."

Entering plan mode licenses a **scoping confirm**: a short round of questions that settle what this plan covers, no more than one `AskUserQuestion` call holds (the per-call question limit: <https://code.claude.com/docs/en/agent-sdk/user-input#limitations>, as of 2026-10-11; recheck when that section changes the per-call question limit), as one numbered round before proposing it. The round renders via `AskUserQuestion` only when the plugin's `use_ask_user_question` user config is on and the questions are independent. Inline prose otherwise.

**Substantive rounds do not belong in plan mode.** A question that resolves *what we are building* (real tradeoffs, contested requirements, anything whose answer changes the plan's shape) routes to `/planning:interview` via the Skill tool, run with **plan mode off**: that skill's ask-time open-question register is a disk write that plan mode blocks, and plan mode primes the run toward producing the plan when the job is still reaching shared understanding. **Getting there is the user's move, not yours**: when plan mode is active and a substantive round comes due, say why and ask the user to exit it (`shift+tab`), then invoke the interview once they have. Do not invoke it from inside plan mode.

## Boundary, the built-in `/plan` command

The command and this skill share a name, so "plan this" can mean either.

- **`/plan` (built-in command)**: `/plan [description]` enters plan mode, optionally starting on the description; `/plan open` views the session plan. It is reserved for the person to run; the model does not invoke it.
- **This skill (marketplace plugin).** The planning discipline: stress-test, blast radius, an approval gate, and a persisted PLAN.md a cleared session can execute.

**Routing.** Where Plan Mode Integration says to suggest plan mode, offer it to the person: you can run `/plan` (or press `shift+tab`) alongside this skill. Prefer this skill for the plan itself. An unattended run records the offer in its output instead of asking.

**Mutation gate.** This skill writes PLAN.md and its checklist; `/plan` changes the permission mode. This skill never toggles the mode on the person's behalf.

**Availability is never assumed.** This section states what to do when the person can run `/plan`, never that it is present. The four-part records live in [reference/native-plan.md](reference/native-plan.md).

## Boundary, the built-in `Plan` agent

Both produce an implementation plan, so "plan this" can also route to the subagent.

- **`Plan` (built-in subagent)**: a research agent that returns a step-by-step approach to its caller, skips CLAUDE.md, and runs no approval gate. It cannot write files. It is reached through the Agent tool's `subagent_type`.
- **This skill (marketplace plugin)**: the plan the person approves: stress-test, blast radius, decision gates, and a persisted PLAN.md.

**Routing.** When the built-in `Plan` agent resolves in this session, dispatch it for a throwaway approach sketch or read-only context-gathering whose result feeds other work; use this skill when the plan needs the person's approval or must outlive the session. This skill may dispatch `Plan` to gather context, but the plan it presents is its own.

**Mutation gate.** `Plan` writes nothing. This skill writes PLAN.md and its checklist.

The four-part records live in [reference/native-plan-agent.md](reference/native-plan-agent.md).

## Plan Review Mode

Read [context/review-mode.md](context/review-mode.md) when invoked with `review`. It holds the review procedure and how it differs from `/planning:devils-advocate`.

## Final step: persist the approved plan for handoff

After the user approves in Step 5, update the draft `<memory_dir>/<topic-slug>/PLAN.md` (default `.work/`; persisted at Step 4.7) with any approval-round changes and its `Approval:` line (who approved and when, or the unattended basis Step 5 names), and write each `superseded-by-plan` row's result to the ledger once the user has replied to that row (reconfirmed or restored, per "Plan changes after the Brief"). The plan is not approved while any listed change lacks its reply: when an interview ledger exists, rerun `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-open-questions.sh" --ledger <ledger>` before handing off and require exit 0 (no `open` or `superseded-by-plan` row left); with or without a ledger, a listed change still lacking its reply means asking for it and not handing off. After writing the `Approval:` line, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-plan-outcome.sh" --approval-only <PLAN.md>` and require exit 0 before handoff; on an unattended run a failure means reporting the plan as unapproved. The script checks only that the line exists and its value is neither empty, the template placeholder, nor TBD; whether the recorded mandate is adequate stays a judgment.

Derive `<topic-slug>` from the task or branch name (kebab-case, ≤40 chars; shared with `/planning:prd`, `/planning:interview`, `/planning:design`); placement per the lifecycle artifact protocol [`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md). PLAN.md lives in the self-ignored memory slice and is never staged; paste it into the pull request body or the linked issue so reviewers see it, and refresh that paste when an implementation phase changes the plan. It is the **living source of truth** for the stage: a fresh cleared session in this checkout must be able to execute the plan reading only this file (plus the exploration and research artifacts in `<memory_dir>/<topic-slug>/`, default `.work/`). Its `## Design` section carries the design decisions, so neither that session nor a worker it dispatches needs the `design/` directory.

**Plan store.** After the `Approval:` check passes, resolve `plan_store`, lowest layer first: the default `local`; the plugin's `plan_store` user config (`${user_config.plan_store}`); then the `plan_store` key of the repository's `docs/conventions/planning.yaml`, which wins when set (schema: [`${CLAUDE_PLUGIN_ROOT}/schemas/planning.schema.json`](${CLAUDE_PLUGIN_ROOT}/schemas/planning.schema.json)). Read that key from the file in this checkout, under the same root rule as `phase_order` (Step 2); a missing file or key means the layer is unset. No `~/.claude` file, `.claude/` fallback or local overlay sets this key. A user config value of `local` is reported as the default, since the two cannot be told apart, and a literal unexpanded `${user_config.plan_store}` means the user config layer is unset, not invalid. A value other than `local` or `tracker` in either layer is named with its file (or user config), key and value, and that layer is dropped: a valid higher layer still wins, with none the key is `local`, and a lower layer's value never replaces it. Report one line naming the value and its layer, e.g. `plan_store: tracker (docs/conventions/planning.yaml)`.

- `local`: nothing more; PLAN.md stays in the memory slice.
- `tracker`: publish the approved plan to the work item this session claimed (through `/work-items:work` or `/work-items:track start`) by invoking `/work-items:track publish-plan <id> <PLAN.md>` through the Skill tool, when `/work-items:track` is among the available skills. That comment is the issue copy of the plan. With no claimed item, without that skill, or when `publish-plan` stops because the bound tracker cannot hold the comment, keep the plan local and say which applied. Only the approved plan is published; the Step 4.7 draft never is.

**PLAN.md anatomy.** PLAN holds Brief + Design + Plan; per-phase status lives in the phase tags (`[TODO]` / `[DOING]` / `[DONE]`), never in a separate status block. Copy the skeleton from [`templates/plan-md-anatomy.md`](templates/plan-md-anatomy.md) when writing the file at this step, and read it again when a phase tag changes: it owns the section order, the tag grammar, and what each section must contain for a cleared session to execute the plan from this file alone.

PLAN.md is a multi-turn shared artifact: re-read it from disk before every write, since another turn or agent may have modified it. Prefer appending or refining sections over wholesale rewrites.

Write the plan even for small changes; only the one-sentence skip (Purpose) writes none.

**Close-out (PR time).** Read [context/close-out.md](context/close-out.md) when invoked with `close-out`. It holds the three-step procedure, the ADR admission test, and the spec-container ship ritual.

**Mid-flight pivots:** when scope changes after approval, append a dated scope-change note to the affected PLAN.md section capturing the rationale, and strikethrough+link the obsolete content. PLAN.md is never committed, so these notes are its only history; refresh the pull request body or linked issue paste so the published copy carries them (under `plan_store: tracker`, rerun `publish-plan`, which edits its comment in place). Do not silently rewrite history.

**After writing, recommend:** clear context and begin implementation. The implementing session reads PLAN.md for the execution roadmap.

## What This Skill Does NOT Do

- **Does not replace `/planning:devils-advocate`**. It decides when to invoke it, based on blast radius
- **Does not replace research**. It uses research findings as input and may trigger more research in Step 4
- **Does not replace built-in plan mode**, a permission mode; the two complement each other
- **Does not write code**. Execution is a separate stage
- **Does not block execution or make decisions**. It structures the decision and gates on user approval; the user can always override

## Next

- The approved plan runs in this session: /implementation:implement.
- The execution shape routes phases to worker subagents: /implementation:implement-dispatch.
- The plan holds more than one independently shippable ticket, or a later session, an AFK lane or another person picks it up: /work-items:decompose.

## Gotchas

- **The Step 3 reviewer brief is the lever, not the step.** If the user finds a gap in 5 seconds that the fresh-context reviewer missed, tighten the reviewer brief rather than adding an inline self-critique
- **Don't skip the prerequisite check.** Plans built without exploration miss existing patterns; plans without research repeat solved mistakes. The prerequisite check is 30 seconds; the rework is 30 minutes
- **Scale the plan to the task.** A 50-line plan for a typo fix is over-engineering; a 3-bullet plan for a cross-cutting refactor is under-engineering
- **Don't confuse this skill with built-in plan mode.** If a user types "plan this", they want the discipline, not the permission mode
- **Research-iterate has a ceiling.** 3 iterations max before escalating to the user. If 3 rounds can't resolve it, the approach may need to change, not just the evidence
- **The plan is a proposal.** Never start executing without user approval
- **Step 4.5 (Execution shape) is default ON for ≥2-phase plans.** Skip explicitly only for single-phase plans or trivial fixes, stated in one line
- **Open Decisions resolved BEFORE the plan body is authored.** Surfacing them mid-plan-body forces re-iteration during Step 5
- **Sanity Check criteria are mechanically verifiable.** Write the exact command a reviewer would run (grep, Read assertion, build/test exit)
