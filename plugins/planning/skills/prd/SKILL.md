---
name: prd
description: "Produce a Product Requirements Document that locks product intent — problem, users, success metrics — before any engineering plan, with tiers (one-pager / consumer-feature / b2b-internal), a synthesize path, and a review mode. Use for 'write a PRD', 'spec out a feature', 'product brief', or any user-facing business-driven change needing written alignment; skip for refactors, infra, bug fixes, and engineering-internal work (route to /interview or /architect)."
argument-hint: "[tier] [task description] (e.g., /planning:prd, /planning:prd one-pager add gig calendar, /planning:prd review)"
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

Most product-feature rework comes from skipping the *what for whom and why* layer and jumping straight to *how*. `/prd` produces the lockable product intent contract — what we are building, for which users, against what measurable success — before any engineering plan, exploration, or research begins.

This is the **product-intent** stage. **Upstream of exploration**, **upstream of `/architect`**, and may run **before or alongside `/interview`** depending on task shape:

- `/prd` — answers *what should we build, for whom, and why*. Outcome-focused. Required for new user-facing features, business-driven changes, cross-team initiatives
- `/interview` — answers *what is the engineering contract for this task*. Constraint and acceptance-criteria focused. Required whenever intent is fuzzy, regardless of source
- Complementary, not redundant. A product feature usually wants both: `/prd` (product intent) → `/interview` (engineering contract) → exploration → research → `/design` → `/architect`. Engineering-internal work skips `/prd` entirely

The PRD is **never an implementation plan**. Boundaries: problem, users, success — yes. Architecture, files, tests, code shapes — no. That is `/architect`'s job. If the user pulls toward implementation mid-PRD, anchor back to *what for whom* and let `/architect` pick up after.

**Cost framing**: locking product intent up-front is the cheapest version of the conversation. Every later session that runs against a written PRD costs less than one that infers product goals from a half-formed thought.

## Trigger conditions — when to invoke `/prd`

Invoke `/prd` when ALL of these are true:

- The work has a **user-facing surface** — new feature, new screen, new flow, new public API, new external behaviour
- The change is **business- or product-driven** — solves a user problem, opens a market, hits a metric — not engineering-internal cleanup
- **Alignment matters** — multiple stakeholders, cross-team work, or you want a written reference to point the future agent at

## Skip conditions — when to NOT invoke `/prd`

If ANY of these hold, do NOT write a PRD. Tell the user explicitly: *"This is engineering-internal — no PRD. Recommend `/interview` (if intent is fuzzy) or `/architect` (if it's clear)."*

- **Refactors** (no behaviour change)
- **Infrastructure** (build, CI, hooks, config, dependency bumps, lockfiles)
- **Conventions** (rules files, doc updates, lint rules, analyzers)
- **Bug fixes** (a bug already implies the desired behaviour — fix the gap, no PRD)
- **Single-team engineering work** with no user-visible surface
- **Tooling**, scripts, internal automation
- **Documentation-only** changes

If ambiguous (could go either way), surface the question once and let the user pick. Never silently write a PRD for an engineering-internal task.

## Action Router

Parse `$ARGUMENTS` to determine the action. Tier choice can be passed as the first argument; if absent, ask via `AskUserQuestion`.

| Argument | Action | Use case |
|----------|--------|----------|
| *(empty)* | **Smart default** | If a prior PRD exists for the topic, offer resume/revise/start-fresh. Otherwise prompt for tier + task via `AskUserQuestion`. |
| `<task description>` (no tier word) | **Full PRD, prompt for tier** | Run skip-condition check, then ask which template tier (one-pager / consumer-feature / B2B-internal). |
| `one-pager <task>` | **Tier 1 — thin one-pager** | Small feature, single team, fast lock. ~½ page. |
| `consumer <task>` or `consumer-feature <task>` | **Tier 2 — consumer feature** | User-facing app feature with metrics, user stories, risk surface. ~1 page. |
| `b2b <task>` or `b2b-internal <task>` | **Tier 3 — B2B / internal** | Stakeholders, compliance, integration, rollout, change-management. ~2 pages. |
| `synthesize <task>` | **Synthesis-only PRD** | Skip Q&A — produce PRD from existing conversation context. Use when conversation already has rich product context and re-asking would waste the user's time. Still runs skip-condition check (Step 1) and survey (Step 2). |
| `review` | **PRD review** | Critique an existing PRD.md against template + skip-conditions. |

Tier choice rationale lives in [`context/templates.md`](context/templates.md). When tier is unclear from the task description, present the three tiers via `AskUserQuestion` with one-line descriptions — the side-by-side rendering helps the user choose without skimming docs.

## The PRD process

### Step 1 — Skip-condition check (MANDATORY)

Before any other work, validate the request matches the trigger conditions. If it matches the skip conditions, STOP and tell the user:

> *"This looks engineering-internal (`<reason>`). PRDs add cost without value here. Recommend: `/interview` for fuzzy intent OR `/architect` directly if scope is clear."*

Do not proceed unless the user explicitly overrides ("write the PRD anyway") OR clarifies the user-facing/business framing.

### Step 2 — Survey before you write

Spend the first turn grounding yourself, in parallel:

- Read the consuming project's `CLAUDE.md` and `AGENTS.md` for product direction and current modules
- Climb to the nearest domain-vocabulary file (e.g. `UBIQUITOUS-LANGUAGE.md`) if the project keeps one and the topic touches a known module — walk UP from the relevant directory toward repo root and stop at the first match
- `Glob` and `Grep` for keywords from `$ARGUMENTS` to spot existing surfaces
- `git log --oneline -20` for recent product direction
- List the project's own rules files that govern the area (architecture, modules, conventions)
- Note what the topic's contract slice `<contract_dir>/<topic-slug>/` (default `docs/topics/`) already contains — prior PRD, PLAN, design artifacts — and what its memory slice `<memory_dir>/<topic-slug>/` (default `.work/`) holds (exploration/research artifacts)

If a prior `PRD.md` exists for this topic, ask: **resume** (continue from open questions), **revise** (in-place edits, bump `updated:`), or **start fresh** (append a dated restart note capturing why below the PRD's frontmatter, then rewrite; the commit carrying the rewrite states the pivot rationale — the contract is branch-tracked, so git log is the history).

Survey output is a one-paragraph summary in your reply. Then transition to depth-first Q&A.

### Step 3 — Pick the template tier

If not specified in `$ARGUMENTS`, surface tier choice via `AskUserQuestion`:

| Tier | When |
|------|------|
| **1. One-pager** | Small feature, single team owns it, low ambiguity. ~½ page. Sections collapsed; one-line each. |
| **2. Consumer-feature** | User-facing app feature with metrics, 1-2 user stories, risk surface. ~1 page. Full sections. |
| **3. B2B-internal** | Internal/B2B feature with stakeholders, compliance, integration, rollout, change-management. ~2 pages. Full sections + stakeholders, rollout, dependencies/integrations. |

Tier governs section depth, not section presence. All three tiers cover the same seven required sections (problem, goals, non-goals, users + user stories, success metrics, dependencies/risks, open questions). The difference is verbosity.

Full templates: [`context/templates.md`](context/templates.md). Read on demand — keep main context light.

### Step 3.5 — Synthesis-only path (`synthesize`)

When invoked with `synthesize`, skip Step 4 Q&A entirely. Produce the PRD from existing conversation context — prior discussion, explored files, research findings, user statements already captured in the session. Still runs Step 1 (skip-condition check) and Step 2 (survey grounding).

Use when conversation already contains rich product context and re-asking would waste time. The user is signaling "I've told you enough — write it." Respect that signal.

If after the survey (Step 2) a required section has NO answerable content in the conversation, note it as an open question rather than forcing Q&A. The PRD with open questions is still useful — `/interview` or `/architect` picks them up downstream.

### Step 4 — Drive depth-first Q&A

**Skipped when `synthesize` action was invoked** — go directly to Step 5.

ONE question at a time, depth-first — resolve the load-bearing question, then surface the next; never batch unrelated questions. Use `AskUserQuestion` when there are 2-4 distinct named options the user benefits from seeing side by side; use prose for open-ended questions.

Question shapes that recur, in priority order:

| Section | Highest-value surfacing question |
|---------|----------------------------------|
| Problem | "Whose problem is this, and what do they currently do instead?" |
| Goals | "If we ignore implementation, what changes for the user when this ships?" |
| Non-goals | "What is explicitly out of scope so we don't drift?" |
| Users | "Who is the primary user — one persona or many? Walk me through their day before and after." |
| User stories | "Pick the one most-important journey: as a `<role>` I want to `<action>` so that `<outcome>`." |
| Success metrics | "How will we know it worked? Name the metric and the threshold — adoption %, conversion %, time saved, error rate." |
| Dependencies / risks | "What outside this team must exist or change for this to ship? What's the biggest risk?" |
| Open questions | "What is genuinely undecided that the architect needs an answer to?" |

Stop asking once every required section has either a resolved answer or an explicit "open question with revisit trigger".

### Step 5 — Persist the PRD

Derive `<topic-slug>` from the task description or current branch name (kebab-case, ≤40 chars) — the same slug `/interview`, `/design`, and `/architect` will use for this topic. Write to `<contract_dir>/<topic-slug>/PRD.md` (default `docs/topics/`) — the topic's contract slice, committed on the task branch as it locks; under `contract_tier: local` it joins the memory slice instead. Roots, tier, and precedence resolve per the topic-docs binding [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md). PRD.md lives alongside `PLAN.md` (architect's output) and the topic's design artifacts.

Frontmatter:

```yaml
---
status: draft         # draft | locked | superseded
tier: one-pager       # one-pager | consumer-feature | b2b-internal
created: <ISO-8601 UTC, e.g. 2026-06-04T14:30:00Z>
updated: <ISO-8601 UTC, e.g. 2026-06-04T14:30:00Z>
---
```

Required sections (every tier — verbosity varies):

1. **Problem** — what is broken, missed, or unmet for users today
2. **Goals** — outcome-level, not implementation-level
3. **Non-goals** — explicit out-of-scope items
4. **Users** — primary persona(s) + 1-2 user stories in `as a <role>, I want <action>, so that <outcome>` form
5. **Success metrics** — named metric + threshold + measurement window
6. **Dependencies / risks** — outside-team dependencies + top 1-3 risks with mitigations
7. **Open questions** — anything genuinely undecided that `/architect` needs answered

Tier-3 (B2B) adds: **Stakeholders**, **Rollout**, **Compliance / integration**.

**Durability over precision.** PRD content describes interfaces, types, and behavioural contracts — never file paths or line numbers, which go stale before the PRD does. Do not write as if the current implementation structure will persist; the PRD should still read true after a refactor.

**Non-goals graduation edge.** A non-goal that is a permanent, deliberate rejection — not a deferral — outlives the PRD: graduate it to the consuming repo's rejected-concept ledger at `docs/out-of-scope/<concept>.md`, one file per concept, accreting a "Prior requests" log entry each time the concept resurfaces, so future proposals of the same concept get answered by the ledger instead of relitigated. This is a consumer convention with graceful degrade: create the file lazily on first permanent rejection; when the consumer keeps no ledger, the plain Non-goals list suffices.

Test-seam sketching (where the feature will be tested, and at how few seams) is not a PRD concern — it happens in `/planning:design` as a design thread.

Full template structures: [`context/templates.md`](context/templates.md).

Optionally offer to render the finalized PRD as a self-contained, ephemeral HTML pitch view for non-engineer stakeholders — a static generated view, never an editor with real data bound in — while PRD.md stays the tracked record.

### Step 6 — Hand off

After writing the PRD, recommend the next step. The recommendation depends on remaining ambiguity:

- **Engineering scope still fuzzy** (constraints, untouchable areas, perf budget unclear) → clear context, then `/interview` (it will read the topic's `PRD.md` as scope)
- **Engineering scope is clear, codebase grounding needed** → `/discovery:explore` if installed, otherwise whatever codebase-exploration capability the environment provides
- **Need external research (libs, APIs, comparables)** → `/discovery:research` if installed, otherwise the strongest research capability available
- **Engineering scope clear and externals understood** → `/architect`

Do NOT auto-clear or auto-invoke. Recommend; let the user pull the trigger.

## PRD review mode (`review`)

When invoked with `review`:

1. Locate the topic's `PRD.md` (use slug derivation above)
2. Evaluate against the seven required sections — flag any missing or fuzzy
3. Evaluate against skip-conditions — should this PRD even exist? If engineering-internal, recommend supersession with an `/interview` brief
4. Check goals are *outcomes*, not implementations (the most common failure mode)
5. Check success metrics have a *measurement window* and *threshold*, not vague language
6. Present findings: what's strong, what's missing, what to revise

Complementary to `/devils-advocate` — review checks structure and convention; stress-test (run later against `/architect`'s plan, not the PRD) checks failure modes.

## What this skill does NOT do

- **Does not plan implementation** — the PRD is *what for whom and why*. Architecture, files, tests, code is `/architect`'s job. If you find yourself writing "we'll add `XHandler` to module Y", stop and move that to the open-questions section as an architecture decision for later
- **Does not run exploration or research** — Step 2's survey is a *fast grounding pass*, not deep work. If product framing requires deep external research (competitive analysis, market data), pause the PRD and recommend the research capability first
- **Does not gate other skills** — engineering-internal tasks skip `/prd` entirely. Even product features can skip if intent is already locked elsewhere (existing roadmap doc, recent ADR, prior PRD)
- **Does not adversarially attack the user's product idea** — not the PRD's role. If the proposed feature has obvious product risk, surface it once in the *risks* section and continue. Pushback belongs in product review, not PRD authoring
- **Does not write code, run tests, or modify anything outside the topic's contract and memory slices** — pure product-intent skill

## Composition with other skills

| When | Skill | How it composes |
|---|---|---|
| Pre-PRD: problem still rough, no candidate approach chosen | `/brainstorm` | Diverges cheapest→most-ambitious candidates; the resonating direction feeds this PRD |
| Pre-task: product feature, fuzzy intent | **`/prd`** (this) | Produces the topic's `PRD.md` |
| Pre-task: any fuzzy task — including post-PRD constraint discovery | `/interview` | Produces the Brief in `PLAN.md` (reads PRD if present) |
| Need codebase grounding | `/discovery:explore` (if installed) | Reads PRD + PLAN as scope |
| Need external evidence | `/discovery:research` (if installed) | Reads PRD + PLAN as scope |
| Need design exploration (types, contracts, topology) | `/design` | Reads PRD + PLAN; produces design artifacts that `/architect` consumes |
| Plan the implementation | `/architect` | Reads PRD + PLAN + explore + research findings |
| Stress-test the plan | `/devils-advocate` | Adversarial pass on `/architect` output (not the PRD) |

`/prd` is sister to `/architect`: one resolves *what for whom and why*; the other resolves *how*. They share the topic slug, share the contract slice, and feed each other.

## Gotchas

- **Goals as outcomes, never implementations.** "Add a search box" is not a goal; "users can find a song from any of its lyrics in <2 seconds" is. Most common PRD failure: goals that pre-decide the architecture
- **Success metrics need a window.** "Increase engagement" is not a metric; "DAU/MAU rises from X to Y over 30 days post-launch" is. If a metric has no number and no window, it can't validate the feature
- **Don't write a PRD for engineering-internal work.** Skip-condition check is mandatory. PRDs for refactors, hooks, lint rules waste cycles and dilute the convention
- **Tier governs verbosity, not which sections exist.** All three tiers have the same seven required sections. Tier-1 is one line per section; tier-3 is a full paragraph. Don't drop sections to "save time" — drop words
- **The PRD is never an architecture document.** When discussion drifts to implementation, anchor back to *what for whom*. Capture architecture questions in the **open questions** section for `/architect` to resolve
- **Resume vs revise vs start-fresh on prior PRDs.** Never silently overwrite. If scope shifted, append a dated restart note capturing why before rewriting
