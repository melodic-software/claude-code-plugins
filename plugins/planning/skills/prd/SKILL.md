---
description: "Write a Product Requirements Document that locks product intent (problem, users, success metrics) before any engineering plan, in three tiers with a review mode. Use when: 'write a PRD', 'spec out a feature', 'product brief', 'product requirements doc', 'define the requirements', 'what are we actually building', 'acceptance criteria', 'how will we know it worked', or a user-facing change needs written alignment. Engineering-internal work: /planning:interview or /planning:plan."
argument-hint: "[tier] [task description]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: prd
  summary: Lock product intent. Problem, users, success metrics. Before planning
---

**Arguments.** `[tier] [task description]`. e.g., /planning:prd, /planning:prd one-pager add gig calendar, /planning:prd review

## Repository context. Gather first

Collect these with **individual** Bash calls, one command per call, never combined:

- Current branch, `git branch --show-current`
- Recent commits, `git log --oneline -5`
- Working tree status (empty = clean), `git status --porcelain | head -10`

Keep the pipe in the command: a read-time cap bounds nothing, since the Bash tool returns the full output first. Treat a failure (not a repository, git unavailable) as an unknown value and carry on. Keep these as body Bash calls, not pre-compute lines: the pre-compute block runs as one shell invocation, and a worktree-isolated session refuses a compound command that contains git. Dated record: the worktree skill's [reference/gather-block.md](https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/plugins/source-control/skills/worktree/reference/gather-block.md), "The pre-compute block runs as one shell invocation".

## Variables

Arguments: `$ARGUMENTS`

## Purpose

`/planning:prd` produces the lockable product-intent contract: what we are building, for which users, against what measurable success, before any engineering plan, exploration, or research. It runs **upstream of exploration and `/planning:plan`**, before or alongside `/planning:interview`:

- `/planning:prd` answers *what should we build, for whom, and why*. Required for new user-facing features, business-driven changes, cross-team initiatives
- `/planning:interview` answers *what is the engineering contract for this task*. Required whenever intent is fuzzy or underspecified, regardless of source
- A product feature usually wants both: `/planning:prd` → `/planning:interview` → exploration → research → `/planning:design` → `/planning:plan`. Engineering-internal work skips `/planning:prd`

The PRD is **never an implementation plan**: problem, users, success, yes; architecture, files, tests, code shapes, no. If the user pulls toward implementation mid-PRD, anchor back to *what for whom* and let `/planning:plan` pick up after.

**Cost framing**: locking product intent up-front is the cheapest version of the conversation. Every later session that runs against a written PRD costs less than one that infers product goals from a half-formed thought.

## Trigger conditions. When to invoke `/planning:prd`

Invoke `/planning:prd` when ALL of these are true:

- The work has a **user-facing surface**: new feature, screen, flow, public API, or external behavior
- The change is **business- or product-driven**: solves a user problem, opens a market, hits a metric. Not engineering-internal cleanup
- **Alignment matters**: multiple stakeholders, cross-team work, or a written reference for future agents

## Skip conditions. When to NOT invoke `/planning:prd`

If ANY of these hold, do NOT write a PRD. Tell the user explicitly: *"This is engineering-internal. No PRD. Recommend `/planning:interview` (if intent is fuzzy) or `/planning:plan` (if it's clear)."*

- **Refactors** (no behavior change)
- **Infrastructure** (build, CI, hooks, config, dependency bumps, lockfiles)
- **Conventions** (rules files, doc updates, lint rules, analyzers)
- **Bug fixes** (a bug already implies the desired behavior)
- **Single-team engineering work** with no user-visible surface
- **Tooling**, scripts, internal automation
- **Documentation-only** changes

If ambiguous, surface the question once and let the user pick. Never silently write a PRD for an engineering-internal task.

## Action Router

Read `$ARGUMENTS` whole. If its first word is one of the tier words in the table (`one-pager`, `consumer`, `consumer-feature`, `b2b`, `b2b-internal`, `synthesize`, `review`), that row wins and the rest of `$ARGUMENTS` is the task. Any other first word starts the task description, not a tier. When `$ARGUMENTS` is empty, ask for the tier (surface rules below).

| Argument | Action | Use case |
|----------|--------|----------|
| *(empty)* | **Smart default** | If a prior PRD exists for the topic, offer resume/revise/start-fresh. Otherwise prompt for tier + task. |
| `<task description>` (no tier word) | **Full PRD, prompt for tier** | Run skip-condition check, then ask which template tier (one-pager / consumer-feature / B2B-internal). |
| `one-pager <task>` | **Tier 1. Thin one-pager** | Small feature, single team, fast lock. ~½ page. |
| `consumer <task>` or `consumer-feature <task>` | **Tier 2. Consumer feature** | User-facing app feature with metrics, user stories, risk surface. ~1 page. |
| `b2b <task>` or `b2b-internal <task>` | **Tier 3. B2B / internal** | Stakeholders, compliance, integration, rollout, change-management. ~2 pages. |
| `synthesize <task>` | **Synthesis-only PRD** | Skip Q&A. Produce PRD from existing conversation context when it already holds rich product context. Still runs skip-condition check (Step 1) and survey (Step 2). |
| `review` | **PRD review** | Critique an existing PRD.md against template + skip-conditions. |

Tier choice rationale: [`context/templates.md`](context/templates.md). When the tier is unclear from the task description, present the three tiers with one-line descriptions: via `AskUserQuestion` when the plugin's `use_ask_user_question` user config (`${user_config.use_ask_user_question}`) is on, numbered inline prose otherwise.

## The PRD process

### Step 1. Skip-condition check

Before any other work, run this mandatory check: validate the request matches the trigger conditions. If it matches the skip conditions, STOP and tell the user:

> *"This looks engineering-internal (`<reason>`). PRDs add cost without value here. Recommend:
> `/planning:interview` for fuzzy intent OR `/planning:plan` directly if scope is clear."*

Do not proceed unless the user explicitly overrides ("write the PRD anyway") OR clarifies the user-facing/business framing.

### Step 2. Survey before you write

Spend the first turn grounding yourself, in parallel:

- Take product direction and current modules from the project's always-loaded instructions (root `CLAUDE.md` / `AGENTS.md`), already in context; read a nested `AGENTS.md` under the area the topic touches, since those load only when a file they cover is read
- If the project keeps a domain-vocabulary file (e.g. `UBIQUITOUS-LANGUAGE.md`) and the topic touches a known module, walk UP from the relevant directory toward the repo root and read the first match
- `Glob` and `Grep` for keywords from `$ARGUMENTS` to spot existing surfaces
- `git log --oneline -20` for recent product direction
- List the project's own rules files that govern the area (architecture, modules, conventions)
- Note what `<memory_dir>/<topic-slug>/` (default `.work/`) already contains: prior PRD, PLAN, design, exploration and research artifacts

If a prior `PRD.md` exists for this topic, ask: **resume** (continue from open questions), **revise** (in-place edits, bump `updated:`), or **start fresh** (append a dated restart note capturing why below the PRD's frontmatter, then rewrite; PRD.md is never committed, so the restart note is its only history, carried by the copy pasted into the pull request body or linked issue).

Survey output is a one-paragraph summary in your reply. Then move to frontier-rounds Q&A.

### Step 3. Pick the template tier

If not specified in `$ARGUMENTS`, surface the tier choice (card only under the `use_ask_user_question` opt-in; numbered prose otherwise):

| Tier | When |
|------|------|
| **1. One-pager** | Small feature, single team owns it, low ambiguity. ~½ page. Sections collapsed; one-line each. |
| **2. Consumer-feature** | User-facing app feature with metrics, 1-2 user stories, risk surface. ~1 page. Full sections. |
| **3. B2B-internal** | Internal/B2B feature with stakeholders, compliance, integration, rollout, change-management. ~2 pages. Full sections + stakeholders, rollout, dependencies/integrations. |

Tier governs section depth, not section presence: all three tiers cover the same seven required sections (problem, goals, non-goals, users + user stories, success metrics, dependencies/risks, open questions).

Full templates: [`context/templates.md`](context/templates.md). Read on demand.

### Step 3.5. Synthesis-only path (`synthesize`)

With `synthesize`, skip Step 4 Q&A and produce the PRD from existing conversation context: prior discussion, explored files, research findings, user statements already captured. Steps 1 and 2 still run.

`synthesize` also skips the always-on coverage prompt and reports it unexamined, per "Acceptance-criteria capture" below.

If after the survey a required section has NO answerable content in the conversation, record it as an open question rather than forcing Q&A; `/planning:interview` or `/planning:plan` picks it up downstream.

### Step 4. Drive frontier-rounds Q&A

**Skipped when `synthesize` was invoked**. Go directly to Step 5.

Ask in frontier rounds: each round surfaces every open question whose prerequisites are settled as one numbered set (grouped by PRD section), each with a recommendation; a question that depends on another still open waits for the round after its prerequisite resolves. Render a round via `AskUserQuestion` only when the plugin's `use_ask_user_question` user config (`${user_config.use_ask_user_question}`) is on and the round is independent questions that fit one `AskUserQuestion` call (the per-call question limit: <https://code.claude.com/docs/en/agent-sdk/user-input#limitations>, as of 2026-10-11; recheck when that section changes the per-call question limit). Inline prose otherwise.

Each recommendation carries a `Basis:` line: `verified` with the `file:line`, tool output, or URL it rests on, or `judgment` (non-consequential only). A consequential one (cross-repo, shared infrastructure, irreversible, or security) is grounded before it is presented, in the affected code plus its consumers and in external research that reads official docs first; route that work to the exploration or research capability rather than doing it here. One research cannot settle is withheld: ask the question open and name the evidence that would settle it, or record it under **Open questions**. A changed recommendation is restated as old → new → why. Contract: [`${CLAUDE_PLUGIN_ROOT}/context/recommendation-basis.md`](../../context/recommendation-basis.md).

Each candidate question first passes the self-answer step, [`${CLAUDE_PLUGIN_ROOT}/context/self-answer.md`](../../context/self-answer.md): a fact it settles is stated with its basis and source tag, not asked.

Question shapes that recur, in priority order:

| Section | Highest-value surfacing question |
|---------|----------------------------------|
| Problem | "Whose problem is this, and what do they currently do instead?" |
| Goals | "If we ignore implementation, what changes for the user when this ships?" Then, once for the feature: "Which shortcut in building this would cost users something, and do we take it or not?" |
| Non-goals | "What is explicitly out of scope so we don't drift?" Then: "For every new option, control or setting: what is it for?" Any that no one can explain lands in this section. |
| Users | "Who is the primary user. One persona or many? Walk me through their day before and after." |
| User stories | "Pick the one most-important journey: as a `<role>` I want to `<action>` so that `<outcome>`." |
| Success metrics | "How will we know it worked? Name the metric and the threshold. Adoption %, conversion %, time saved, error rate." Then: "Which repeated task that brings users back does this improve, and does the metric measure that task?" |
| Acceptance-criteria coverage | Asked once, per "Acceptance-criteria capture" below. Never one question per criterion. |
| Dependencies / risks | "What outside this team must exist or change for this to ship? What's the biggest risk?" |
| Open questions | "What is genuinely undecided that `/planning:plan` needs an answer to?" |

Stop asking once every required section has either a resolved answer or an explicit "open question with revisit trigger".

### Step 5. Persist the PRD

Derive `<topic-slug>` from the task description or current branch name (kebab-case, ≤40 chars), the same slug `/planning:interview`, `/planning:design`, and `/planning:plan` use for this topic. Write to `<memory_dir>/<topic-slug>/PRD.md` (default `.work/`), never committed; placement per the lifecycle artifact protocol [`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md). Once it locks, paste the PRD into the pull request body or the linked issue. PRD.md lives alongside `PLAN.md` (the plan skill's output) and the topic's design artifacts.

When a PRD.md already exists for the topic, never silently overwrite it: offer resume, revise, or start fresh. If scope shifted, append a dated restart note capturing why before rewriting.

Frontmatter:

```yaml
---
status: draft         # draft | locked | superseded
tier: one-pager       # one-pager | consumer-feature | b2b-internal
created: <ISO-8601 UTC, e.g. 2026-06-04T14:30:00Z>
updated: <ISO-8601 UTC, e.g. 2026-06-04T14:30:00Z>
---
```

Required sections (every tier; verbosity varies):

1. **Problem**. What is broken, missed, or unmet for users today
2. **Goals**. Outcome-level, not implementation-level
3. **Non-goals**. Explicit out-of-scope items, including any setting, control or option with no stated reason. Asking for a reason never cuts an option the consuming project keeps configurable on purpose: there the option stays and its reason is recorded
4. **Users**. Primary persona(s) + 1-2 user stories in `as a <role>, I want <action>, so that <outcome>` form
5. **Success metrics**. Named metric + threshold + measurement window, tied to the repeated task users come back for; when the metric does not measure that task, say so
6. **Dependencies / risks**. Outside-team dependencies + top 1-3 risks with mitigations
7. **Open questions**. Anything genuinely undecided that `/planning:plan` needs answered

Tier-3 (B2B) adds: **Stakeholders**, **Rollout**, **Compliance / integration**.

**Durability over precision.** Describe the product through its interfaces, types, and behavior contracts, not file paths or line numbers; the PRD should still be accurate after a refactor.

**Written for a product owner who scans.** Each section opens with its point and carries no more words than the meaning needs: invoke `/writing:be-concise` via the Skill tool when the `writing` plugin is enabled; otherwise apply that discipline inline. The seven required sections, the tier's depth, and every metric, threshold, and open question stay as they are.

**Non-goals graduation edge.** A non-goal that is a permanent, deliberate rejection, not a deferral, graduates to the consuming repo's rejected-concept ledger at `docs/out-of-scope/<concept>.md`, one file per concept, accreting a "Prior requests" log entry each time the concept resurfaces, so future proposals are answered by the ledger instead of relitigated. Create the file lazily on first permanent rejection; when the consumer keeps no ledger, the plain Non-goals list suffices.

Test-seam sketching (where the feature will be tested, and at how few seams) is not a PRD concern; it happens in `/planning:design` as a design thread.

Optionally offer to render the finalized PRD as a self-contained HTML pitch view for non-engineer stakeholders: a static generated view, never an editor with real data bound in. PRD.md stays the record. Write the view to the OS temp directory, never beside `PRD.md`; placement and rules: [`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md).

### Step 6. Hand off

After writing the PRD, recommend the next step by remaining ambiguity:

- **Engineering scope still fuzzy** (constraints, untouchable areas, perf budget unclear) → clear context, then `/planning:interview` (it reads the topic's `PRD.md` as scope)
- **Engineering scope is clear, codebase grounding needed** → `/discovery:explore` if enabled, otherwise the environment's codebase-exploration capability
- **Need external research (libs, APIs, comparables)** → `/discovery:research` if enabled, otherwise the strongest research capability available
- **Engineering scope clear and externals understood** → `/planning:design`, which records a one-line early exit when no design question is open and hands off to `/planning:plan`
- **The locked PRD is one unit of work that a later session, an AFK lane or another person picks up** → `/work-items:track add --agent-ready`, one tracker item carrying the PRD's acceptance criteria
- **An open question waits on a stakeholder** → `/planning:questionnaire`, which sends it to the person who holds the answer

Do NOT auto-clear or auto-invoke. Recommend; let the user pull the trigger.

## Acceptance-criteria capture

Two behaviors apply when this PRD turns product intent into verifiable statements (the Step 4 success-metrics and user-story rows and any acceptance criterion the run writes down). The first is always on; the second fires only when the consuming team's convention selects it.

### Coverage prompt. Always on, asked once

While capturing those verifiable statements, ask ONE question: are they missing an **unwanted-behavior** case (an `IF <trigger>, THEN <response>` criterion) and a **state-driven** case (a `WHILE <state>, <response>` criterion)? One prompt covering both, never a per-criterion interrogation, and **"neither applies" is a valid answer** that closes it for the session. This runs whatever the acceptance-criteria format resolves to, and with no convention surface present at all; it is a coverage check, not a format.

### Non-interactive runs skip the ask and say so

The **`synthesize` action skips it**, along with any run that has nobody to answer: a dispatched worker, a forked subagent, a headless invocation, or any caller that declared the run unattended. In every one of those the ask is SKIPPED rather than blocking, and the returned summary states that **unwanted-behavior and state-driven coverage went unexamined**. Record the same line in the PRD's **Open questions** section so it outlives the summary.

The unattended condition is **declared by the caller, never sniffed**: never read an environment variable to decide it; `synthesize` is an explicit argument, which is a declaration.

### EARS tags, when the convention selects them

Resolve `acceptance_criteria_format` per the ladder below. Under `free-text`, the default and every degrade, every section is emitted untagged, the same shape as a run with no convention surface at all. Under `ears`, each acceptance criterion this run emits carries a bracketed pattern prefix on a plain bullet:

| Tag | Pattern |
|---|---|
| `[ubiquitous]` | an always-true requirement, no trigger and no state |
| `[event-driven]` | `WHEN <trigger>, <response>` |
| `[state-driven]` | `WHILE <state>, <response>` |
| `[unwanted-behavior]` | `IF <trigger>, THEN <response>` |
| `[optional-feature]` | `WHERE <feature is included>, <response>` |

```text
- [event-driven] WHEN the upload completes, the manifest is rewritten
- [unwanted-behavior] IF the upload fails, THEN the partial manifest is discarded
```

The five names are exactly `ubiquitous`, `event-driven`, `state-driven`, `unwanted-behavior`, and `optional-feature`. A downstream reader matches the literal name, so a variant spelling (`unwanted_behavior`, `unwanted`, `event`) is an untagged criterion that looks tagged and fails silently.

**Scope.** The seven required sections carry no acceptance-criteria list of their own, and this skill adds none: the **Success metrics** table is a measurement with a threshold and a window, not an EARS pattern, and it stays a table under both formats. Tags attach to acceptance criteria this run writes as plain bullets; the durable home for tagged criteria is the Brief `/planning:interview` locks downstream. This skill owes the coverage question, the exact vocabulary, and the same resolution, so a PRD-then-interview pipeline does not change its answer halfway through.

### Resolution ladder for `acceptance_criteria_format`

Restated here rather than cited: an installed plugin never sees the publishing repository's convention docs, so a path citation would make that publisher a runtime dependency of this session.

```markdown
1. Anchor at the repository root: `${CLAUDE_PROJECT_DIR}` when set, otherwise
   `git rev-parse --show-toplevel`. Never a CWD-relative read.
2. Resolve the convention home `<home>` from the pointer line in the marked
   `<!-- BEGIN GENERATED: convention-home -->` region of the root instruction file
   (`AGENTS.md` canonical; `CLAUDE.md` unless it is a pure `@AGENTS.md` shim). Use the
   bundled resolver where the plugin ships one; never hand-parse the root file.
3. The printed home is repo-relative: join it to the root resolved in step 1,
   then read `<home>/authoring-formats/README.md` from that path and take the
   key's value from its fenced YAML block.
4. Layer order is one layer deep: an explicit invocation argument, where the skill has
   one, then the team convention doc, then the documented default. A convention-doc
   surface has no personal overlay, so there is no further layer to consult.
5. Default: `acceptance_criteria_format` is `free-text` — emit untagged criteria,
   exactly today's shape.
6. Degrade soft, and say so. No pointer line, no convention home on disk, no
   `authoring-formats/README.md`, no YAML block, an absent key, or an unrecognized value
   each resolve to the documented default. Name the cause in one clause and continue;
   never hard-fail, and never ask the operator to create the surface mid-task.
7. Report provenance whenever the resolved value shapes output: name the key, the value,
   and the layer it came from — `argument`, `team convention doc <path>`, or `default`.
```

This plugin ships the step-2 resolver at `bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh"`: exit 0 prints the home on stdout, exit 1 means no pointer line is bound, exit 2 is usage, and exit 3 is a FAIL (two pointer lines in one region, an unterminated or nested region, an invalid pointer path, or a pointer whose target directory does not exist). Every non-zero exit is a step-6 degrade, `free-text`, cause named in one clause, never a halt and never a prompt to go create the surface.

## PRD review mode (`review`)

When invoked with `review`:

1. Locate the topic's `PRD.md` (slug derivation above)
2. Evaluate against the seven required sections. Flag any missing or fuzzy
3. Evaluate against skip-conditions. If engineering-internal, recommend supersession with a `/planning:interview` brief
4. Check goals are *outcomes*, not implementations (the most common failure mode)
5. Check success metrics have a *measurement window* and *threshold*, not vague language
6. Present findings: what's strong, what's missing, what to revise

Review checks structure and convention; `/planning:devils-advocate` (run later against `/planning:plan`'s plan, not the PRD) checks failure modes.

## What this skill does NOT do

- **Does not plan implementation**. Architecture, files, tests, code is `/planning:plan`'s job. If you find yourself writing "we'll add `XHandler` to module Y", move that to open questions as an architecture decision for later
- **Does not run exploration or research**. Step 2's survey is a fast grounding pass. If product framing requires deep external research (competitive analysis, market data), pause the PRD and recommend the research capability first
- **Does not gate other skills**. Engineering-internal tasks skip `/planning:prd`; product features can skip it if intent is already locked elsewhere (roadmap doc, recent ADR, prior PRD)
- **Does not adversarially attack the user's product idea**. Surface obvious product risk once in the *risks* section and continue. Pushback belongs in product review, not PRD authoring
- **Does not write code, run tests, or modify anything outside the topic's memory slice**, apart from pasting the locked PRD into the pull request body or linked issue
- **Does not export Gherkin**. Nothing here emits `.feature` files or `Given`/`When`/`Then` scenarios; the EARS tags are a bracketed prefix vocabulary on a plain bullet, not a step grammar. A Gherkin export is a separate slice against a separate contract

## Composition with other skills

| When | Skill | How it composes |
|---|---|---|
| Pre-PRD: problem still rough, no candidate approach chosen | `/planning:brainstorm` | Diverges cheapest→most-ambitious candidates; the resonating direction feeds this PRD |
| Pre-task: product feature, fuzzy intent | **`/planning:prd`** (this) | Produces the topic's `PRD.md` |
| Pre-task: any fuzzy task. Including post-PRD constraint discovery | `/planning:interview` | Produces the Brief in `PLAN.md` (reads PRD if present) |
| Need codebase grounding | `/discovery:explore` (if enabled) | Reads PRD + PLAN as scope |
| Need external evidence | `/discovery:research` (if enabled) | Reads PRD + PLAN as scope |
| Need design exploration (types, contracts, topology) | `/planning:design` | Reads PRD + PLAN; produces design artifacts that `/planning:plan` consumes |
| Plan the implementation | `/planning:plan` | Reads PRD + PLAN + explore + research findings |
| Stress-test the plan | `/planning:devils-advocate` | Adversarial pass on `/planning:plan` output (not the PRD) |

## Next

- PRD locked: /planning:interview for the engineering contract, or /planning:design when the Brief already exists.
- PRD locked and it is one unit of work for a later session, an AFK lane or another person: /work-items:track add --agent-ready.
- An open question waits on a stakeholder: /planning:questionnaire.
- Unsure where this leaves the work, or arrived mid-flow: /session-flow:workflow.

## Gotchas

- **Goals as outcomes, never implementations.** "Add a search box" is not a goal; "users can find a song from any of its lyrics in <2 seconds" is. Goals that pre-decide the architecture are the most common PRD failure
- **Success metrics need a window.** "Increase engagement" is not a metric; "DAU/MAU rises from X to Y over 30 days post-launch" is
- **Tier governs verbosity, not which sections exist.** Tier-1 is one line per section; tier-3 is a full paragraph. Don't drop sections; drop words
- **The PRD is never an architecture document.** When discussion drifts to implementation, anchor back to *what for whom* and capture architecture questions under **open questions** for `/planning:plan`
