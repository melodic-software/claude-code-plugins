---
name: interview
description: "Interview relentlessly to reach shared understanding on a plan, decision, or idea — questions arrive in frontier rounds: every question whose prerequisites are settled asked together as one numbered set, each with a recommendation. Routes by context: an engineering task locks a task contract (goal, constraints, acceptance criteria, named assumptions) into a PLAN.md Brief that feeds the planning pipeline; a general decision drives to a shared understanding and stops. Synthesizes directly when intent is clear, runs the rounds loop when gaps remain, or interviews relentlessly on request. Use proactively before behavior-changing work when intent is ambiguous or underspecified, or on explicit request ('interview me', 'lock the brief', 'spec this task', 'grill me', 'this is underspecified'); skip for mechanical work (typo/lint/whitespace/rename) and casual conversation."
argument-hint: "[action] [topic] (e.g., /planning:interview, /planning:interview me, /planning:interview lock, /planning:interview <topic>)"
user-invocable: true
disable-model-invocation: false
shell: bash
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Recent commits: !`git log --oneline -5 2>/dev/null || echo "no commits"`
Working tree status: !`git status --porcelain 2>/dev/null | head -10 || echo "clean"`

## Variables

Arguments: `$ARGUMENTS`

## Purpose

Most rework comes from acting on assumptions the user never made and the agent never surfaced — an **underspecified** task, one missing the constraints needed to act safely. `/interview` is the pipeline's underspecification resolver: a structured pass driving every load-bearing unknown to a decision OR capturing it as a named, explicit assumption — before exploration, planning, or execution start.

The **pre-clarity** stage — upstream of exploration, research, and `/planning:plan`. `/planning:plan` presupposes a coherent task; `/interview` produces one out of fuzzy intent. The contract it writes is the target every later stage aims at.

**Supportive, not adversarial.** `/devils-advocate` attacks an existing artifact after the fact. `/interview` walks alongside the user to extract a clear contract from the start.

**Domain-routed.** The interview loop is universal — it interviews any plan, decision, or idea. What the session *produces* depends on context: an engineering task in a code repo locks a PLAN.md Brief and can hand off to `/planning:plan`; a general decision drives to a shared understanding and ends there. The domain is inferred from the task's build surface — the problem itself decides, with repo and working directory as context that never suffices alone — never asked, and it is orthogonal to the `me`/`auto`/`lock` action. Engineering machinery — codebase grounding, the Brief, ADR/glossary outputs, pipeline handoff — engages only when the context is engineering; the universal loop runs either way. A user can override the inference in prose ("this isn't a code task", "interview me on this decision").

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

**Default action leans to `me` (relentless prose rounds).** When invoked with no args (or by proactive auto-trigger), bias toward `me`-mode — drive open decisions through frontier-rounds prose Q&A. Fall back to direct synthesis (`lock`-style) ONLY when context heavily informs against asking: intent already crystal-clear with no open decisions, OR the user signalled "just lock it / stop asking". Auto-detect's synthesize-directly path is for the genuinely-clear case, not the default posture.

**Question surface: inline prose by default.** Rounds render as numbered inline prose — dictation-friendly, no per-question cap, and each question carries its recommendation, reasoning, and probe in one readable block. `AskUserQuestion` is an opt-in surface, enabled via the plugin's `use_ask_user_question` user config (`${user_config.use_ask_user_question}`, default off). When opted in, use it ONLY for a round of ≤4 mutually independent questions that are **simple selections or binary confirms** — a card carries options, not a recommendation's reasoning or a constraint-surfacing probe, so any question needing its basis argued stays prose. Fall back to prose when the frontier exceeds 4, any question in the round depends on another, or a question needs more than a pick — the card cannot express a dependency or a rationale, and chunking a round across multiple cards fragments it. When in doubt, prose.

**Artifact escape hatch for a dense round.** When a round is large or its questions are dense — a wall of prose the user cannot scan — OFFER to render the *whole frontier* as a **self-contained HTML decision table** written to the topic-docs **ephemeral tier** — one OS temp directory per interview run, never the memory slice and never the session scratchpad (the ledger and terminal stay the tracked record; the HTML is a scannable view, not the source of truth, and nothing downstream reads it again). Rows are numbered to the terminal `Q<N>` so the user still answers by number in the terminal. The table preserves the full inline contract — each recommendation keeps its 2-3 sentence codebase-grounded basis (never a terse label), and the round's closing constraint probe renders with it — so grounding and the challenge mechanism are not lost. A rendering surface for the same frontier, never a round split or a question cap; degrade to a fenced markdown table (same columns and grounding) when HTML rendering is unavailable. Delivery path + column detail: [`context/loop.md`](context/loop.md) "Artifact escape hatch".

## Stance: supportive, depth-first, opinionated

The Q&A path of this skill is one engine wrapped in a stop condition and an output contract. Four working principles drive it:

1. **Frontier-rounds loop** — the decision space is a tree; the **frontier** is every decision whose prerequisites are already settled. Ask the whole frontier as one numbered round, wait for the answers, recompute the frontier, ask the next round. A question whose answer depends on another question still open in this round belongs to a *later* round. Within a round, order by architectural blast radius — the answer that would change the most downstream work goes first. A frontier of one question degenerates to a single-question round
2. **Survey-then-deep** — before asking blind, do a fast breadth pass (repo files, recent commits, existing skills, relevant project rules) so questions land in real context
3. **Climb-to-anchor** — find the nearest `CLAUDE.md`, `AGENTS.md`, domain-vocabulary file, or module README by walking UP from the relevant directory toward repo root; let those shape questions instead of asking what is already documented
4. **Immediate doc maintenance** *(engineering sessions only)* — when an answer resolves a domain
   term, invoke `/domain-driven-design:curate-language` (if that plugin is installed — else
   record the term in the Brief's glossary notes) IMMEDIATELY between questions, not
   batched at end. Route
   decisions, gotchas, and conventions to their proper homes (ADR, project rules, side note) in the
   same response. A general session writes no repo docs — it drives to a shared-understanding summary
   only

**Intake the starting point.** Early in the loop (or before it), establish where the user is — one intake question that discloses their starting point; questions and recommendations calibrate to that disclosure. When the territory itself is unfamiliar to the USER — they can't yet evaluate options because they don't know the domain or codebase area — route to a blindspot-surfacing exploration FIRST (`/discovery:blindspot <area>` if installed, otherwise a guided walkthrough of the area); an interview over unknown territory locks a contract the user can't assess.

When the effort is too big to hold at once AND still too foggy to phrase as sharp questions — the user can't yet list the decisions, let alone lock them — that is upstream of `/interview`. Name `/planning:wayfind` to the user (it charts the fog as a decision map and works the frontier down decision by decision, graduating to a Brief once it clears); recommend, never auto-switch.

**Question budget scales with what's already settled.** Upstream artifacts — research findings, exploration output, a PRD, a design resolution — count as settled prerequisites: an interview invoked after them starts with a smaller tree and fewer rounds; never re-ask what an artifact already answers. There is no numeric question cap, but a frontier that keeps *ballooning* (each round opens more branches than it closes) is the wayfind signal above, not a license for a marathon session — surface the routing recommendation instead of grinding on.

Tone is collaborative but opinionated. You are not interrogating; you are helping the user think out loud by PROPOSING answers grounded in codebase evidence. When the user gives a definitive answer, lock it. When they hesitate, slow down and offer two or three concrete shapes the answer could take. Every option set names exactly ONE recommended option marked **(RECOMMENDED)** with a one-line basis. The surface follows the "Question surface" rule above: inline prose rounds by default, `AskUserQuestion` only when the user opted in and the round qualifies.

### Relentless mode (`me`)

`me` is the **relentless interview** — drive EVERY *consequential* branch of the decision tree to a *decision*. No question cap (some plans need three, some fifty; the escape hatch is the user saying "wrap up", never a counter). Relentless is not exhausting: every question leads with a recommendation, so most answers are a one-tap "correct".

**Canonical framing** (what `me` means, in one breath): *interview relentlessly about every aspect of the task until you reach a shared understanding; map the decision tree and work it in rounds — each round asks every frontier question (prerequisites settled) as one numbered set, each with your recommended answer, and the answers recompute the frontier; finding facts is your job, never the user's — resolve them from the environment (filesystem, tools, sub-agents) instead of asking; the decisions are the user's — put each one to them and wait.*

**Ask each round inline as one numbered set.** Per-question shape within the round:

```text
Q<N>: <one question>
[<one line of context — ONLY when the round-header restate doesn't reach this question, or the first round after a session gap>]

My recommendation: **<answer>** — <2-3 sentences; grounded in codebase/convention; why it beats the alternatives>.

Alternatives to consider:
- (a) <option> — <one-line tradeoff>
- (b) <option> — <one-line tradeoff>
- (c) <option> — <one-line tradeoff>
```

`Q<N>` numbering runs continuously across rounds (Q1…Q4 in round one, Q5… in round two — visible depth). Close the round with one probe inviting a constraint that breaks the recommendations, and the note that the user may answer in any order. Wait for the answers before computing the next round. The recommendation+basis discipline holds per question — inline prose carries the recommendation, its reasoning, AND the probe in one readable block; a card cannot.

**One verdict marker, at most one context line.** The `My recommendation:` line is the *single* verdict marker for the question — never stack a second one: no standalone `**(RECOMMENDED)**` badge line above it, and no `(recommended)` tag repeated in the Alternatives list; the recommended answer is named once, on that line. Per-question context is at most ONE line and usually absent — the round-header restate carries shared context, so add a line only when it doesn't reach this question or the session just resumed after a gap.

**Define session shorthand once, then park it.** When a round introduces session-local shorthand — a coined label, an abbreviation, or cross-repo jargon the user may not share ("lanes", "gate vacuity") — define it in one clause at first use and record it in the ledger's shorthand glossary, then use the term freely. This is ephemeral session vocabulary, distinct from the project's ubiquitous language (owned by `/domain-driven-design:curate-language`), and never touches a project glossary. Ledger shape: [`context/loop.md`](context/loop.md) "Session-shorthand glossary".

**Partial-round resolution.** The user may answer any subset, in any order, in one reply. Unanswered questions stay OPEN on the frontier — re-surface them at the top of the next round, labelled "unanswered from last round". NEVER silently resolve an unanswered question to its recommendation — the auto-guard applies inside rounds too. Honor accept-shorthands: "accept all recommendations" resolves the whole round to the recommended answers; "yes to Q5" / "Q5–Q7 yes" resolves that subset. Answers that reshape the tree ("actually, we don't need auth at all") invalidate pending questions — recompute the frontier before re-asking anything.

**Visual-first for structural questions (default, not on-request).** When a question concerns structure — file/folder layout, before/after states, naming shapes, schema or flow alternatives — and a compact visual (fenced tree, diff, small table; roughly ≤30 lines) can carry it, LEAD with the visual and hang the question off it. A paragraph describing a tree is much harder to verify against the user's mental model than the tree itself; the visual IS the question. Before/after pairs beat single-state snapshots when the question is a migration. Skip only when no compact visual exists (genuinely abstract trade-offs) or when it would blow past ~30 lines — then summarize and offer the full visual on request.

**Dialogue — the user drives too.** They may push back or reframe a decision (e.g. "what's hardest to roll back from?"). When they introduce a new axis — **reversibility** is the most common for V1 — re-rank the options on it and REVISE your recommendation out loud. Default V1 lens: prefer the most *reversible* start; defer the irreversible/expensive as an explicit out-of-scope decision, never a silent assumption.

**Facts are yours; decisions are the user's.** A *fact* — a path, a current value, an existing pattern, what a file already does — is resolved from the environment (Grep/Read/Glob) and STATED, never asked; spending a question on what the code already answers is friction, not interview. The environment is not only the working tree: when a task NAMES an external repo or resource — a sibling checkout under a known repo root / workspace layout, or an `owner/repo` reachable through its host — that is a resolvable fact too, so check the filesystem layout and query the repo host directly (e.g. `gh` for a named `owner/repo`) before defaulting to a user question. Cue, not mandate — resolve what's cheaply resolvable, don't turn every named mention into a research project. A *decision* — real tradeoffs, no environment answer — ALWAYS goes to the user; never resolve one on their behalf, however obvious the answer looks. When a fact lookup is slow (deep exploration, external research), dispatch it to a sub-agent and DON'T block the round: a running lookup is an unsettled prerequisite, so only the questions downstream of it wait for the next round — ask the rest of the frontier now.

**Ground before recommending.** Lightweight codebase gate per question (Grep/Read/Glob). If a recommendation needs more — external best-practice, a library API, deeper exploration — dispatch or do the lookup (research/exploration capability, or inline), then recommend grounded. Never recommend a load-bearing technical choice from training recall alone — ground it in code read this session or an official source fetched this session.

### Recommended answers

For EVERY question, propose an answer grounded in observed codebase state. User confirms (fast) or corrects (faster than explaining from scratch). When no codebase signal exists, recommend based on conventions and state the basis. Mark it with its one-line basis — in an inline round that marker IS the `My recommendation:` line (one verdict marker, never a second stacked badge); in an `AskUserQuestion` card it is the option tagged **(RECOMMENDED)**. Detail in [`context/loop.md`](context/loop.md) "Frontier rounds".

### Domain-aware behaviors

When the task touches domain concepts, these behaviors activate during Q&A. The probing behaviors run in any session; the two that write repo artifacts — **inline vocabulary update** and **ADR** — are engineering-only (per the Step 1 domain classification), so a general session, gated to a shared-understanding summary, never mutates a project glossary or proposes an ADR:

- **glossary challenge** — when the user uses a domain term two ways, or a term collides with an existing definition, probe it
- **domain scenario exploration** — invent edge cases that probe concept boundaries ("what happens when a Customer cancels half an Order?")
- **inline vocabulary update** *(engineering sessions only)* — when a term resolves, invoke
  `/domain-driven-design:curate-language` immediately (if that plugin is installed; else
  record the term in the Brief's glossary notes). That skill owns discovery-first
  placement, the consumer's
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

- **Synthesize directly** (clear) → skip Step 2; proceed to Step 3 (confirmation gate), then Step 4 (Persist)
- **Q&A loop** (fuzzy) → continue to Step 2
- **Mixed** → ask the residue (one round — the few open questions together), then synthesize; proceed to Step 3, then Step 4

**Auto-guard — never decide an interactive choice for the user.** Synthesize-directly (and the Mixed path's "synthesize the rest") applies ONLY to decisions with a verifiable answer (codebase-resolvable) or an unambiguous conventional default. When a remaining decision is genuinely the user's — a design choice with real tradeoffs and no codebase answer — do NOT fold it into the Brief. STOP and either ask it inline (a residue round) or offer to switch: *"This is a real design decision, not mine to pick — answer it, or want me to run `/planning:interview me` and drive every open branch to a decision?"* Silently capturing such a choice as an assumption is the failure mode this guard prevents.

For `me` / `me <topic>`: skip Step 1.5, force Q&A.
For `lock`: skip Step 1.5 AND Step 2, synthesize directly. If a gap surfaces mid-synthesis, STOP and surface — do not fudge.

### Step 2 — Drive the frontier-rounds loop

Run rounds: restate working understanding → compute the frontier (every open question whose prerequisites are settled) → ask the whole frontier as one numbered set → capture the answers → recompute. Categorize each open item as resolvable / blocked / defer-with-assumption / defer-fully. The restate is also the **session-hop anchor**: after a handoff, resume, or long gap it re-establishes the decided set and this round's stakes before any question, so a returning reader is grounded without re-reading the whole ledger.

Full surfacing-question taxonomy + categorization heuristics in [`context/loop.md`](context/loop.md).

**`me` mode** maintains a **decision-tree ledger** — one live checkbox per branch, ticked on resolve, remaining-open surfaced periodically (not every turn — keeps the flow clean like the inline format). Persist each answer the moment it locks in (Step 4), loop until zero open consequential branches. Ask via the inline format (Stance "Relentless mode"). Ledger shape + per-round mechanics + reversibility-lens question shape in [`context/loop.md`](context/loop.md) "Decision-tree ledger".

### Step 3 — Recognize the stop condition

Stop when the frontier is empty — every load-bearing unknown resolved OR captured as named assumption — the user can describe the goal in one paragraph without contradicting the constraints, and acceptance criteria are testable. Don't stop early on impatience; don't keep asking past the stop condition.

**Confirmation gate (`me` and `auto`):** an empty frontier is necessary but not sufficient — before persisting the contract or handing off, restate the shared understanding and get the user's explicit confirmation that it is reached. Do not act on the interview's output until they confirm. `lock` is exempt: invoking it IS the confirmation (its STOP-on-gap rule still applies).

**`me` mode tightening:** "captured as named assumption" is NOT a valid stop for a *consequential* branch — drive it to a decision (a decision MAY be "defer to post-V1", but it must be explicit and surfaced, never silent). The stop condition is an **empty decision-tree ledger** plus the confirmation gate — not a question count.

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

## Session-config recommendation (model, effort, advisor)

The interview already reads task complexity and ambiguity to drive its rounds — turn
that read into a recommendation for how the session carrying the work forward should
be configured. *When* it lands follows from *what* it configures. Engineering work
hands off to a **downstream execution session** that has not started yet, so its
recommendation belongs at the stop/handoff boundary. A terminal session (general
decisions, per Step 5 above) has nothing downstream — the session carrying the work
IS the current one — so surface a first read **early**, right after the Step 1
survey classifies the domain as general, whenever the survey's complexity/ambiguity
signals warrant a config change: applied then, it can still improve the substantive
rounds it was derived for. At the stop boundary, refresh that read as config for the
**current/next session**, applied now; if the config was raised only at the end (or
not at all), offer to re-evaluate the reached understanding under the raised config
rather than presenting a knob that can no longer affect the finished work. Two
orthogonal knobs, picked per the official distinction:

- **Model tier (capability)** — raise the model when the assistant would be
  *confidently wrong despite full context* (a reasoning ceiling, not missing input).
- **Effort level (thoroughness)** — raise effort when the assistant would
  *under-explore or under-verify* (right answer reachable, but it stops short).

When the recommendation keeps a faster main model, pair it with the **advisor**: a
faster main without a stronger advisor is not the recommended config for non-trivial
work — the documented efficiency pairing escalates planning, ambiguous failures, and
completion checks to a stronger advisor instead of paying for the top model every
turn.

**Source the current names live, never pin them.** Model names, tiers, effort levels,
and accepted advisor pairings drift between versions; the durable *distinction* above
is stable, the *names* are not. Fetch them once when you form the recommendation from
the official docs (mirror `draft-goal-condition`'s never-pin discipline). A doc-fetch
failure **degrades, never halts** — fall back to the durable distinction and tell the
user the current names could not be verified live so they confirm against `/model` /
`/advisor`. Frame the whole thing as advisory (the skill cannot read the current
effort/advisor state) and applicable to engineering and general sessions alike. The
same signals matter **mid-task**, in the inverse direction — but the interview
terminates at handoff, so hand the user a watch-for ("if execution turns out too
complex for the current model/effort, that's the cue to raise it") rather than an
instruction to whatever session executes next. Full detail, sources, and the
knob-picking signals in [`context/session-config.md`](context/session-config.md).

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
| Validate the interview's answers via agents | `/planning:audit-answers` | Fresh validators challenge each answer in the filled ledger (hand-answered or auto-accepted); only the doubtful ones return as human questions |
| Pause and resume later | `/session-flow:handoff` (if installed) | Captures session state, distinct from the Brief (mid-task pause vs pre-execution intent) |

**Mid-interview composition (`me` mode):** research, exploration, and handoff are not only downstream — invoke them *during* the interview when a recommendation needs external/codebase grounding or when branches outgrow the session. Return to the open branch after.

`/interview` is sister to `/planning:plan`: one resolves *what*, the other resolves *how*. They share the topic slug, share the directory, feed each other.
