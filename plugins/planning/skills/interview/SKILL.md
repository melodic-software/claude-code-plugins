---
name: interview
description: "Interview relentlessly to reach shared understanding on a plan, decision, or idea — one question at a time, each with a recommendation. Routes by context: an engineering task locks a task contract (goal, constraints, acceptance criteria, named assumptions) into a PLAN.md Brief that feeds the planning pipeline; a general decision drives to a shared understanding and stops. Synthesizes directly when intent is clear, runs depth-first Q&A when gaps remain, or grills relentlessly on request. Use proactively before behavior-changing work when intent is ambiguous, or on explicit request ('interview me', 'grill me', 'lock the brief', 'spec this task'); skip for mechanical work (typo/lint/whitespace/rename) and casual conversation."
argument-hint: "[action] [topic] (e.g., /planning:interview, /planning:interview me, /planning:interview lock, /planning:interview <topic>)"
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

Most rework comes from acting on assumptions the user never made and the agent never surfaced. `/interview` prevents it: a structured pass driving every load-bearing unknown to a decision OR capturing it as a named, explicit assumption — before exploration, planning, or execution start.

The **pre-clarity** stage — upstream of exploration, research, and `/planning:plan`. `/planning:plan` presupposes a coherent task; `/interview` produces one out of fuzzy intent. The contract it writes is the target every later stage aims at.

**Supportive, not adversarial.** `/devils-advocate` attacks an existing artifact after the fact. `/interview` walks alongside the user to extract a clear contract from the start.

**Domain-routed.** The interview loop is universal — it grills any plan, decision, or idea. What the session *produces* depends on context: an engineering task in a code repo locks a PLAN.md Brief and can hand off to `/planning:plan`; a general decision drives to a shared understanding and ends there. The domain is inferred from the task's build surface — the problem itself decides, with repo and working directory as context that never suffices alone — never asked, and it is orthogonal to the `me`/`auto`/`lock` action. Engineering machinery — codebase grounding, the Brief, ADR/glossary outputs, pipeline handoff — engages only when the context is engineering; the universal loop runs either way. A user can override the inference in prose ("this isn't a code task", "grill me on this decision").

**Two invocation modes, one schema.** When intent is fuzzy, `/interview` runs the depth-first Q&A loop. When intent is already clear from conversation, `/interview` synthesizes directly without asking (front-loaded brief). Both write the same output for the session's domain — a PLAN.md Brief for an engineering task, a shared-understanding summary otherwise. The default action **auto-detects** which mode fits and routes accordingly.

**Cost framing**: every clarification round-trip skipped is time and tokens saved. Auto-detect removes redundant Q&A; explicit `lock` skips Q&A entirely when the user has already given the answer.

## Emit checklist

For interview sessions with ≥2 open questions OR explicit `me` mode, copy `templates/checklist.md` into the topic's memory slice as `<memory_dir>/<topic-slug>/interview-checklist.md` (default `.work/`; **one ledger per topic** — not per session). Re-interview appends `## Resolved (<round>, <date>)` sections; do not create `interview-checklist-2.md`. Tick each step as completed. Steps 1, 3, 4 are mandatory; Steps 1.5 + 2 are mode-conditional.

## Action Router

Parse `$ARGUMENTS` to determine the action. Empty argument routes to `auto` (the intelligent default) — which **leans to `me`-mode relentless prose Q&A by default** unless context heavily informs otherwise (see "Default action leans to `me`" below).

| Argument | Action | When to use |
|----------|--------|-------------|
| *(empty)* | **`auto` (default → leans `me`)** | Survey context, detect gaps; route to relentless prose Q&A unless intent is already crystal-clear or the user said "just lock it" |
| `me` | **Force relentless Q&A** | "Interview me", "ask me everything", "relentless" — skip auto-detect; drive EVERY decision-tree branch to a decision, uncapped, no silent assumptions |
| `me <topic>` | **Force Q&A on narrow topic** | "Interview me about the auth approach" — Q&A loop scoped to topic |
| `lock` | **Force synthesis, no Q&A** | "Stop asking, just write it", "I'm clear, lock the brief" — skip auto-detect, synthesize directly. If a real gap surfaces during synthesis, STOP and surface it (do not fudge) |
| `<topic>` | **`auto` on narrow topic** | "Interview the caching approach" — same intelligent default, narrower scope |

Unknown actions route to `auto`; surface the unrecognized request as a one-line side note.

**Default action leans to `me` (relentless prose Q&A).** When invoked with no args (or by proactive auto-trigger), bias toward `me`-mode — drive open decisions through one-question-at-a-time prose Q&A. Fall back to direct synthesis (`lock`-style) ONLY when context heavily informs against asking: intent already crystal-clear with no open decisions, OR the user signalled "just lock it / stop asking". Auto-detect's synthesize-directly path is for the genuinely-clear case, not the default posture.

**NEVER use `AskUserQuestion` for dependent / sequential interview questions.** Dependent decisions (where a later question's framing or option set depends on an earlier answer) go ONE AT A TIME IN PROSE — the side-by-side multiple-choice card fragments a sequential interrogation. `AskUserQuestion` is reserved for genuinely *batched independent* choices (≤4, answers don't reshape each other). When in doubt during an interview, ask in prose.

## Stance: supportive, depth-first, opinionated

The Q&A path of this skill is one engine wrapped in a stop condition and an output contract. Four working principles drive it:

1. **Depth-first Q&A loop** — ONE question at a time, resolve the load-bearing one, then surface the next; rank questions by architectural blast radius — the answer that would change the most downstream work goes first
2. **Survey-then-deep** — before asking blind, do a fast breadth pass (repo files, recent commits, existing skills, relevant project rules) so questions land in real context
3. **Climb-to-anchor** — find the nearest `CLAUDE.md`, `AGENTS.md`, domain-vocabulary file, or module README by walking UP from the relevant directory toward repo root; let those shape questions instead of asking what is already documented
4. **Immediate doc maintenance** *(engineering sessions only)* — when an answer resolves a domain
   term, invoke `/planning:domain-modeling` IMMEDIATELY between questions, not batched at end. Route
   decisions, gotchas, and conventions to their proper homes (ADR, project rules, side note) in the
   same response. A general session writes no repo docs — it drives to a shared-understanding summary
   only

**Intake the starting point.** Early in the loop (or before it), establish where the user is — one intake question that discloses their starting point; questions and recommendations calibrate to that disclosure. When the territory itself is unfamiliar to the USER — they can't yet evaluate options because they don't know the domain or codebase area — route to a blindspot-surfacing exploration FIRST (`/discovery:explore blindspot <area>` if installed, otherwise a guided walkthrough of the area); an interview over unknown territory locks a contract the user can't assess.

When the effort is too big to hold at once AND still too foggy to phrase as sharp questions — the user can't yet list the decisions, let alone lock them — that is upstream of `/interview`. Name `/planning:wayfind` to the user (it charts the fog as a decision map and works it down one decision at a time, graduating to a Brief once it clears); recommend, never auto-switch.

Tone is collaborative but opinionated. You are not interrogating; you are helping the user think out loud by PROPOSING answers grounded in codebase evidence. When the user gives a definitive answer, lock it. When they hesitate, slow down and offer two or three concrete shapes the answer could take. Every option set names exactly ONE recommended option marked **(RECOMMENDED)** with a one-line basis — `AskUserQuestion` for 2-4 side-by-side independent choices, prose for open-ended. **`me` mode overrides this surface — see "Relentless mode" below.**

### Relentless mode (`me`)

`me` is the **relentless interview** — drive EVERY *consequential* branch of the decision tree to a *decision*. No question cap (some plans need three, some fifty; the escape hatch is the user saying "wrap up", never a counter). Relentless is not exhausting: every question leads with a recommendation, so most answers are a one-tap "correct".

**Canonical framing** (what `me` means, in one breath): *interview relentlessly about every aspect of the task until you reach a shared understanding; walk down each branch of the decision tree, resolving dependencies between decisions one-by-one; for each question, provide your recommended answer; ask the questions one at a time; and if a question can be answered by exploring the environment (filesystem, tools, etc.), explore the environment instead of asking.*

**Ask inline, ONE question per turn — NOT `AskUserQuestion`.** Shape:

```text
Q<N>: <one question>

My recommendation: **<answer>** — <2-3 sentences; grounded in codebase/convention; why it beats the alternatives>.

Alternatives to consider:
- (a) <option> (recommended) — <one-line tradeoff>
- (b) <option> — <one-line tradeoff>
- (c) <option> — <one-line tradeoff>

Which one — <probe inviting a constraint that breaks the recommendation>?
```

Wait for the answer before the next question. The recommendation+basis discipline still holds — only the surface differs: inline prose carries the recommendation, its reasoning, AND the "what pushes against this?" probe in one message; a card cannot.

**Visual-first for structural questions (default, not on-request).** When a question concerns structure — file/folder layout, before/after states, naming shapes, schema or flow alternatives — and a compact visual (fenced tree, diff, small table; roughly ≤30 lines) can carry it, LEAD with the visual and hang the question off it. A paragraph describing a tree is much harder to verify against the user's mental model than the tree itself; the visual IS the question. Before/after pairs beat single-state snapshots when the question is a migration. Skip only when no compact visual exists (genuinely abstract trade-offs) or when it would blow past ~30 lines — then summarize and offer the full visual on request.

**Dialogue — the user drives too.** They may push back or reframe a decision (e.g. "what's hardest to roll back from?"). When they introduce a new axis — **reversibility** is the most common for V1 — re-rank the options on it and REVISE your recommendation out loud. Default V1 lens: prefer the most *reversible* start; defer the irreversible/expensive as an explicit out-of-scope decision, never a silent assumption.

**Explore instead of asking.** If a question is answerable from the codebase — a path, a current value, an existing pattern, what a file already does — resolve it by Grep/Read/Glob and STATE the finding; do NOT spend a question on what the code already answers. Asking the user to confirm a fact you could have read is friction, not interview.

**Ground before recommending.** Lightweight codebase gate per question (Grep/Read/Glob). If a recommendation needs more — external best-practice, a library API, deeper exploration — pause the loop, do it (research/exploration capability, or inline lookup), then return grounded. Never recommend a load-bearing technical choice from training recall alone — ground it in code read this session or an official source fetched this session.

### Recommended answers

For EVERY question, propose an answer grounded in observed codebase state. User confirms (fast) or corrects (faster than explaining from scratch). When no codebase signal exists, recommend based on conventions and state the basis. Mark that recommendation as **(RECOMMENDED)** with its one-line basis. Detail in [`context/loop.md`](context/loop.md) "Per-round loop" step 4.

### Domain-aware behaviors

When the task touches domain concepts, these behaviors activate during Q&A. The probing behaviors run in any session; the two that write repo artifacts — **inline vocabulary update** and **ADR** — are engineering-only (per the Step 1 domain classification), so a general session, gated to a shared-understanding summary, never mutates a project glossary or proposes an ADR:

- **glossary challenge** — when the user uses a domain term two ways, or a term collides with an existing definition, probe it
- **domain scenario exploration** — invent edge cases that probe concept boundaries ("what happens when a Customer cancels half an Order?")
- **inline vocabulary update** *(engineering sessions only)* — when a term resolves, invoke
  `/planning:domain-modeling` immediately. That skill owns discovery-first placement, the consumer's
  file shape, purity, canonical terms, rejected synonyms, and known-context routing; the interview
  resumes after the update
- **ADR, offered sparingly** *(engineering sessions only)* — propose an architecture decision record only when a decision is hard to reverse AND surprising without context AND the result of a real trade-off. Write to the repository's declared ADR convention (a managed `docs/adr/` README, a project rule, or an existing `docs/adr/` shape); if none is declared, offer and defer — never prescribe a location or format

## The interview loop

Five steps. Step 1 (Survey) runs every action. Step 1.5 (Auto-detect) runs on `auto` only. Step 2 (Q&A loop) runs on `me` or `auto`-routed-to-Q&A. Detail in [`context/loop.md`](context/loop.md).

### Step 1 — Survey before you ask

Spend the first turn grounding yourself. Read the project's `CLAUDE.md` / `AGENTS.md` if not already in context, Glob/Grep keywords, scan `git log --oneline -20`, climb to the nearest domain-vocabulary file, list relevant project rules, check the topic's contract slice `<contract_dir>/<topic-slug>/` (default `docs/topics/`) for a prior PLAN.md / PRD / design artifacts and its memory slice `<memory_dir>/<topic-slug>/` (default `.work/`) for exploration / research artifacts.

Survey output: one paragraph "Here is what I see in the repo."

**Classify the domain** from what the survey shows — *engineering* (a build or behavior-change task, or a technical subject that yields a build artifact) or *general* (a decision or idea with no build surface). The deciding signal is the **task/build surface itself**, not the working directory: a general decision raised from inside a code repo is still general, and the engineering machinery must never engage on cwd alone. Repo/cwd is context that breaks the tie only when the task surface is genuinely indeterminate — then lean engineering inside a code repo, else general. This is inferred, never asked; honor any explicit user override. The domain governs which machinery engages and what the session produces (see Purpose "Domain-routed"); it is orthogonal to the `me`/`auto`/`lock` action.

**Engineering sessions only** — if a prior PLAN.md Brief exists, ask whether to **resume**, **revise**, or **start fresh** (the latter appends a dated scope-change note to the top of the Brief capturing why before rewriting, and the commit carrying the rewrite states the pivot rationale — the contract is branch-tracked, so git log is the history). A general session never creates or edits a PLAN.md Brief, so it skips this prompt.

Then route per action.

### Step 1.5 — Auto-detect (default action only)

For `auto`: classify intent against `context/loop.md` "Step 1.5 — Auto-detect" criteria. Three outcomes:

- **Synthesize directly** (clear) → skip to Step 4 (Persist)
- **Q&A loop** (fuzzy) → continue to Step 2
- **Mixed** → ask the residue (one question), then synthesize

**Auto-guard — never decide an interactive choice for the user.** Synthesize-directly (and the Mixed path's "synthesize the rest") applies ONLY to decisions with a verifiable answer (codebase-resolvable) or an unambiguous conventional default. When a remaining decision is genuinely the user's — a design choice with real tradeoffs and no codebase answer — do NOT fold it into the Brief. STOP and either ask it inline (one question) or offer to switch: *"This is a real design decision, not mine to pick — answer it, or want me to run `/planning:interview me` and drive every open branch to a decision?"* Silently capturing such a choice as an assumption is the failure mode this guard prevents.

For `me` / `me <topic>`: skip Step 1.5, force Q&A.
For `lock`: skip Step 1.5 AND Step 2, synthesize directly. If a gap surfaces mid-synthesis, STOP and surface — do not fudge.

### Step 2 — Drive the depth-first loop

Run rounds: restate working understanding → ask ONE question (most load-bearing) → capture answer → update open list. Categorize each open item as resolvable / defer-with-assumption / defer-fully.

Full surfacing-question taxonomy + categorization heuristics in [`context/loop.md`](context/loop.md).

**`me` mode** maintains a **decision-tree ledger** — one live checkbox per branch, ticked on resolve, remaining-open surfaced periodically (not every turn — keeps the flow clean like the inline format). Persist each answer the moment it locks in (Step 4), loop until zero open consequential branches. Ask via the inline format (Stance "Relentless mode"). Ledger shape + per-round mechanics + reversibility-lens question shape in [`context/loop.md`](context/loop.md) "Decision-tree ledger".

### Step 3 — Recognize the stop condition

Stop when every load-bearing unknown is resolved OR captured as named assumption, the user can describe the goal in one paragraph without contradicting the constraints, acceptance criteria are testable, and the user signals readiness. Don't stop early on impatience; don't keep asking past the stop condition.

**`me` mode tightening:** "captured as named assumption" is NOT a valid stop for a *consequential* branch — drive it to a decision (a decision MAY be "defer to post-V1", but it must be explicit and surfaced, never silent). The stop condition is an **empty decision-tree ledger** plus user readiness — not a question count.

### Step 4 — Persist the contract

Derive `<topic-slug>` from the task or current branch name (kebab-case, ≤40 chars — shared with `/prd`, `/design`, `/planning:plan`). The contract lands in the topic's contract slice `<contract_dir>/<topic-slug>/` (default `docs/topics/`); working ledgers land in the memory slice `<memory_dir>/<topic-slug>/` (default `.work/`) — roots, tier, and precedence resolve per the topic-docs binding [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md). *What* gets persisted follows the Step 1 domain classification.

**General (non-engineering) sessions** persist a shared-understanding summary — the decisions reached and their rationale — to the memory slice (nothing downstream enforces against it), or inline when the user wants no artifact. NEVER create or edit a PLAN.md Brief for a general decision: the `## Brief`/`## Plan` structure is the engineering shape. In `me` mode, the incremental-persistence and context-pressure-flush discipline below still applies, with the summary standing in for the Brief.

**Engineering sessions** write the Brief section into `<contract_dir>/<topic-slug>/PLAN.md` (default `docs/topics/`; the memory slice under `contract_tier: local`) — a contract document, committed on the task branch as it locks. The rest of this step — everything below — is the Brief machinery and is engineering-only.

**`me` mode persists incrementally, not just at the end.** Lock each answer into the decision-tree ledger (`interview-checklist.md`) + the relevant PLAN.md Brief section the moment it resolves — so a crash, context clear, or overflow never loses resolved branches. **Context-pressure flush:** if the conversation is getting heavy, force-flush the current ledger + partial Brief to disk and offer a handoff (`/session-flow:handoff` if installed, otherwise write a resume note in the topic's memory slice) before continuing. Target the light V1-spec Brief shape (scope / schema / code-surface bullets) — keep it terse.

PLAN.md holds `## Brief` + `## Plan` sections. `/interview` writes only the Brief section; the Plan section stays empty until `/planning:plan` fills it.

If a PLAN.md Brief exists and user chose **revise**, edit the Brief in-place. If **start fresh**, append a dated scope-change note to the top of the Brief capturing why before rewriting — never silently overwrite — and let the commit message carry the pivot rationale.

Section schema: write the literal `## Brief` template — TLDR / Goal / Constraints / Acceptance criteria / Captured assumptions / Out-of-scope / Deferred questions — per [`context/loop.md`](context/loop.md) "Brief template (the literal shape)". Each **Deferred question** carries an **arbiter tag** (`/planning:plan` default, or `USER-RESERVED` when its resolution could change acceptance criteria / out-of-scope / constraints) — load-bearing; loop.md covers when to use which.

### Step 5 — Hand off

Route the handoff by what the session produced. **A general (non-engineering) session is terminal** — it produced a shared-understanding summary, not a Brief; deliver that summary and stop, offering no pipeline handoff (nothing downstream consumes it). **An engineering session** wrote a PLAN.md Brief — recommend the next step per task shape:

- **Code change with unknowns about the codebase** → clear context, then codebase exploration (`/discovery:explore` if installed — it reads the Brief as scope)
- **Code change relying on external libs/APIs/best-practices** → external research (`/discovery:research` if installed)
- **Already understand the codebase and the externals** → `/planning:plan`
- **Task is small and the contract IS the plan** → proceed directly to implementation
- **Interview outgrew one session (many branches, context filling)** → handoff now (`/session-flow:handoff` if installed, otherwise write a resume note), clear, resume — the ledger + Brief survive; resume continues from the first open branch

Do NOT auto-clear or auto-invoke. Recommend; let the user pull the trigger.

## What this skill does NOT do

- `context/gotchas.md` — failure patterns from real sessions

- **Does not deep-dive the codebase** — Step 1 is a fast survey; the codebase gate in Step 2 is a lightweight per-question check (Grep/Read/Glob). Neither is exploration-depth work. If exploration grows beyond quick lookups, stop and recommend the exploration capability
- **Does not plan implementation** — the Brief says *what* and *what we are assuming*; `/planning:plan` says *how*. Resist drafting an approach mid-interview
- **Does not write code or run tests** — discovery skill. In an engineering session it DOES write domain docs outside the topic's slices when the project keeps them: domain-vocabulary updates (inline, between questions) and ADRs are first-class interview outputs alongside the Brief (a general session writes none)
- **Does not adversarially attack the user's idea** — that is `/devils-advocate`. Domain scenario exploration (probing concept boundaries through invented edge cases) discovers domain semantics — it is not plan-attacking. If you find yourself wanting to push back on the goal itself, surface once, capture response, continue
- **Does not gate truly mechanical work** — typo, lint-only, whitespace, comment, single-line non-behavioral fix, and routine dependency bumps skip `/interview`. Everything that creates or changes behavior, contracts, structure, or design is **interview-first by default** — auto-detect keeps that cheap (synthesize-on-clear, relentless-Q&A-on-fuzzy). The bar is behavior-change, not fuzziness
- **Does not fudge gaps in `lock` mode** — if a true unknown surfaces during synthesis, STOP and surface it. Fall back to `auto` or `me` instead of guessing

## Composition with other skills

| When | Skill | How it composes |
|---|---|---|
| Pre-task fuzzy intent or lock-the-brief | **`/interview`** (this) | Produces PLAN.md Brief |
| Product intent fuzzy (whose problem, what success) | `/prd` | Upstream of `/interview`; PRD answers *what for whom and why* |
| Need codebase grounding | `/discovery:explore` (if installed) | Reads PLAN.md Brief as scope |
| Need external evidence | `/discovery:research` (if installed) | Reads PLAN.md Brief as scope |
| Plan the implementation | `/planning:plan` | Reads PLAN.md Brief + explore + research findings |
| Stress-test the plan | `/devils-advocate` | Adversarial pass on `/planning:plan` output |
| Pause and resume later | `/session-flow:handoff` (if installed) | Captures session state, distinct from the Brief (mid-task pause vs pre-execution intent) |

**Mid-interview composition (`me` mode):** research, exploration, and handoff are not only downstream — invoke them *during* the interview when a recommendation needs external/codebase grounding or when branches outgrow the session. Return to the open branch after.

`/interview` is sister to `/planning:plan`: one resolves *what*, the other resolves *how*. They share the topic slug, share the directory, feed each other.
