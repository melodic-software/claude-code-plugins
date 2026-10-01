---
description: "Interview to shared understanding on a plan, decision, or idea, in rounds of numbered, recommended questions. An engineering task locks a PLAN.md Brief (goal, constraints, acceptance criteria, assumptions). Use when: 'interview me', 'lock the brief', 'spec this task', 'grill me', 'this is underspecified', 'ask me questions first', 'what do you need to know', 'acceptance criteria', 'how will we know this is done', or before behavior-changing work with ambiguous intent. Skip mechanical work."
argument-hint: "[action] [topic]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: contract
  summary: Interview in frontier rounds until the task contract is locked
---

**Arguments.** `[action] [topic]`. e.g., /planning:interview, /planning:interview me, /planning:interview lock, /planning:interview scope, /planning:interview <topic>

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

Rework often comes from acting on assumptions the user never made and the agent never surfaced, an **underspecified** task, one missing the constraints needed to act safely. `/planning:interview` is the pipeline's underspecification resolver: a structured pass driving every unknown the task depends on to a decision OR capturing it as a named, explicit assumption, before exploration, planning, or execution start.

The **pre-clarity** stage. Upstream of exploration, research, and `/planning:plan`. `/planning:plan` presupposes a coherent task; `/planning:interview` produces one out of fuzzy intent. The contract it writes is the target every later stage aims at.

**Supportive, not adversarial.** `/planning:devils-advocate` attacks an existing artifact after the fact. `/planning:interview` walks alongside the user to extract a clear contract from the start.

**Domain-routed.** The interview loop is universal. It interviews any plan, decision, or idea. What the session *produces* depends on context: an engineering task in a code repo locks a PLAN.md Brief and can hand off to `/planning:plan`; a general decision drives to a shared understanding and ends there. The domain is inferred from the task's build surface. The problem itself decides, with repo and working directory as context that never suffices alone. Never asked, and it is orthogonal to the `me`/`auto`/`lock` action. Engineering machinery, codebase grounding, the Brief, ADR/glossary outputs, pipeline handoff, engages only when the context is engineering; the universal loop runs either way. A user can override the inference in prose ("this isn't a code task", "interview me on this decision").

**Two invocation modes, one schema.** When intent is fuzzy, `/planning:interview` runs the depth-first Q&A loop. When intent is already clear from conversation, `/planning:interview` synthesizes directly without asking (front-loaded brief). Both write the same output for the session's domain. A PLAN.md Brief for an engineering task, a shared-understanding summary otherwise. The default action **auto-detects** which mode fits and routes accordingly.

**Cost framing**: every clarification round-trip skipped is time and tokens saved. Auto-detect removes redundant Q&A; explicit `lock` skips Q&A entirely when the user has already given the answer.

## Emit checklist

For interview sessions with ≥2 open questions OR explicit `me` mode, copy `templates/checklist.md` into the topic's memory slice as `<memory_dir>/<topic-slug>/interview-checklist.md` (default `.work/`; **one ledger per topic**. Not per session). Re-interview appends `## Resolved (<round>, <date>)` sections; do not create `interview-checklist-2.md`. Tick each step as completed. Steps 1, 3, 4 are mandatory; Steps 1.5 + 2 are mode-conditional.

The ledger's `## Open-question register` is emitted the moment **any** round is asked, whatever that threshold says. It has to exist before the first reply arrives. The acceptance-criteria coverage prompt is the one thing that does not count as a round for this purpose: it writes no row and does not by itself make the register exist (see "Acceptance-criteria capture"). Register mechanics, the drift check, the unattended ladder, and the gate that grades it: [`context/loop.md`](context/loop.md) "The open-question register".

## Action Router

Parse `$ARGUMENTS` to determine the action. Empty argument routes to `auto` (the intelligent default). Which **leans to `me`-mode relentless prose Q&A by default** unless context heavily informs otherwise (see "Default action leans to `me`" below).

| Argument | Action | When to use |
|----------|--------|-------------|
| *(empty)* | **`auto` (default → leans `me`)** | Survey context, detect gaps; route to relentless prose Q&A unless intent is already crystal-clear or the user said "just lock it" |
| `me` | **Force relentless Q&A** | "Interview me", "ask me everything", "relentless". Skip auto-detect; drive EVERY decision-tree branch to a decision, uncapped, no silent assumptions |
| `me <topic>` | **Force Q&A on narrow topic** | "Interview me about the auth approach". Q&A loop scoped to topic |
| `lock` | **Force synthesis, no Q&A** | "Stop asking, just write it", "I'm clear, lock the brief". Skip auto-detect, synthesize directly. If a real gap surfaces during synthesis, STOP and surface it (do not fudge) |
| `scope` / `scope <topic>` | **Ad hoc scope round** | Short scope Q&A before another skill: ledger + register gate; **no** `PLAN.md` Brief; return `Scope decisions:` for the caller |
| `<topic>` | **`auto` on narrow topic** | "Interview the caching approach". Same intelligent default, narrower scope |

Unknown actions route to `auto`; surface the unrecognized request as a one-line side note.

**Default action leans to `me` (relentless prose rounds).** When invoked with no args (or by proactive auto-trigger), bias toward `me`-mode. Drive open decisions through frontier-rounds prose Q&A. Fall back to direct synthesis (`lock`-style) ONLY when context heavily informs against asking: intent already crystal-clear with no open decisions, OR the user signaled "just lock it / stop asking". Auto-detect's synthesize-directly path is for the genuinely-clear case, not the default posture.

**Question surface: inline prose by default.** Rounds render as numbered inline prose. Dictation-friendly, no per-question cap, and each question carries its recommendation, reasoning, and probe in one readable block. `AskUserQuestion` is an opt-in surface, enabled via the plugin's `use_ask_user_question` user config (`${user_config.use_ask_user_question}`, default off). When opted in, use it ONLY for a round of ≤4 mutually independent questions that are **simple selections or binary confirms**. A card carries options, not a recommendation's reasoning or a constraint-surfacing probe, so any question needing its basis argued stays prose. Fall back to prose when the frontier exceeds 4, any question in the round depends on another, or a question needs more than a pick. The card cannot express a dependency or a rationale, and chunking a round across multiple cards fragments it. When in doubt, prose.

**Question surface: the page.** Configured surface: **`${user_config.surface}`**. If it is `page`, start the page with the command below before the first round and ask no round inline. `page` selects a local page on 127.0.0.1 that this session watches; `terminal` is the default. A value other than `page` or `terminal`, or an unexpanded `user_config` token, falls back to `terminal`, with a one-line note only for a real unknown value. The page is two-way and is the input surface: the user answers each question there and every save reaches this session. The terminal stays a valid input, mirrored onto the page with `record-terminal`. A decision this session records or revises in the ledger is mirrored the same way. `surface: page` wins over `use_ask_user_question`, which applies only when the surface is `terminal`. The user may ask for the page at any point, whatever the setting. On a dense terminal round, offer the page; when the page cannot start, offer the read-only table. Start it with one command; the data dir resolves through the topic-docs binding, never CWD-relative:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/surface/round.sh" --dir '<memory_dir>/<topic-slug>/interview-surface' ensure-running --open --emoji-markers '${user_config.use_emoji_question_markers}'
```

Then write the frontier with `add-round` and arm the watcher as a background Bash task. Write the register's `open` rows yourself in the same step as `add-round`; the frontier-rounds contract (recommendation, basis, alternatives, probe, partial rounds, gates) holds on the page as it does inline. When Python, curl or bash is missing, the port cannot bind, the server stays unreachable after a restart (the watcher exits 2), or the session runs on a remote host the browser cannot reach, render the read-only decision table instead and say in one line which prerequisite failed. Substitution record: claim, non-sensitive `userConfig` values substitute into skill bodies as `user_config.KEY` tokens, and an unset key with a `default` substitutes that default; basis, [plugins-reference "User configuration"](https://code.claude.com/docs/en/plugins-reference#user-configuration): "Non-sensitive values can also be substituted in skill and agent content.", and the `default` row, "Value used when the user provides nothing" (that the default is what substitutes is a reading of that row); as of 2026-09-24; recheck when that section changes or a run shows a literal token. Wake command, events, rules and wrap-up exports: [`context/surface.md`](context/surface.md).

## Stance: supportive, depth-first, opinionated

The Q&A path of this skill is one engine wrapped in a stop condition and an output contract. Four working principles drive it:

1. **Frontier-rounds loop**. The decision space is a tree; the **frontier** is every decision whose prerequisites are already settled. Ask the whole frontier as one numbered round, wait for the answers, recompute the frontier, ask the next round. A question whose answer depends on another question still open in this round belongs to a *later* round. Within a round, order by architectural blast radius. The answer that would change the most downstream work goes first. A frontier of one question degenerates to a single-question round
2. **Survey-then-deep**. Before asking blind, do a fast breadth pass (repo files, recent commits, existing skills, relevant project rules) so questions land in real context
3. **Climb-to-anchor**. Find the nearest `CLAUDE.md`, `AGENTS.md`, domain-vocabulary file, or module README by walking UP from the relevant directory toward repo root; let those shape questions instead of asking what is already documented
4. **Immediate doc maintenance** *(engineering sessions only)*. When an answer resolves a domain
   term, invoke `/domain-driven-design:curate-language` via the Skill tool (if that plugin is installed; else
   record the term in the Brief's glossary notes) IMMEDIATELY between questions, not
   batched at end. Route
   decisions, gotchas, and conventions to their proper homes (ADR, project rules, side note) in the
   same response. A general session writes no repo docs. It drives to a shared-understanding summary
   only

**Intake the starting point.** Early in the loop (or before it), establish where the user is. One intake question that discloses their starting point; questions and recommendations calibrate to that disclosure. When the territory itself is unfamiliar to the USER, they can't yet evaluate options because they don't know the domain or codebase area. Route to a blindspot-surfacing exploration FIRST (invoke `/discovery:blindspot <area>` via the Skill tool if installed, otherwise a guided walkthrough of the area); an interview over unknown territory locks a contract the user can't assess.

When the effort is too big to hold at once AND still too foggy to phrase as sharp questions, the user can't yet list the decisions, let alone lock them; that is upstream of `/planning:interview`. Name `/planning:wayfind` to the user (it charts the fog as a decision map and works the frontier down decision by decision, graduating to a Brief once it clears); recommend, never auto-switch.

**Question budget scales with what's already settled.** Upstream artifacts, research findings, exploration output, a PRD, a design resolution, count as settled prerequisites: an interview invoked after them starts with a smaller tree and fewer rounds; never re-ask what an artifact already answers. There is no numeric question cap, but a frontier that keeps *ballooning* (each round opens more branches than it closes) is the wayfind signal above, not a license for a marathon session. Surface the routing recommendation instead of grinding on.

**Bulk application work is not a decision set. The interview settles it once, it never executes it.** When the task applies a settled shape across a corpus (every document in a set, every file matching a pattern, every page of a spec), the interview's output is TWO things and no more: the small set of genuinely contested decisions, driven to decisions the normal way, plus an **execution contract**. One line in the session's output artifact, routed by domain like every other output: the Brief's `### Acceptance criteria` in an engineering session, the shared-understanding summary in a general one. Naming the per-unit close-out loop (one source unit at a time: apply, verify, close) and what *closed* means for a unit. NEVER enumerate the per-unit applications as decision rows: an interview that becomes the execution container turns every application step into a decision needing its own adoption ceremony, and the corpus's size becomes the session's length. **Tripwire. Count the candidates against the corpus:** when the candidate question count scales with the number of source units rather than with the number of genuine forks, that is execution masquerading as decisions. Collapse the per-unit rows into the loop, keep only the forks, and say what you collapsed. Distinct from the ballooning frontier above and remedied differently: ballooning routes to `/planning:wayfind`, unit-scaling collapses into the execution contract and hands off to execution.

Tone is collaborative but opinionated. You are not interrogating; you are helping the user think out loud by PROPOSING answers grounded in codebase evidence. When the user gives a definitive answer, lock it. When they hesitate, slow down and offer two or three concrete shapes the answer could take. Every option set names exactly ONE recommended option marked **(RECOMMENDED)** with a one-line basis, except a withheld question (see "Recommended answers"), which is asked open with no recommended option. The surface follows the two "Question surface" rules above: inline prose rounds by default, the page when `surface` is `page` or the user asks for it, and `AskUserQuestion` only on the terminal, when the user opted in and the round qualifies.

### Relentless mode (`me`)

Read [`context/relentless-mode.md`](context/relentless-mode.md) before the first round when the action resolves to `me`. It holds what relentless mode means and its canonical framing. The round mechanics below apply to every mode that asks questions.

**Ask each round inline as one numbered set.** Per-question shape within the round:

```text
Q<N>: <one question>
[<one line of context — ONLY when the round-header restate doesn't reach this question, or the first round after a session gap>]

My recommendation: **<answer>** — <2-3 sentences; grounded in codebase/convention; why it beats the alternatives>.
Basis: <verified, file:line / tool output / URL fetched this session | judgment>
[Withheld: <the evidence that would settle it>. ONLY in place of both lines above, for a consequential question research could not settle]

[Commits you to: <ONLY when the recommendation fixes more than one decision; each part of it, numbered>
- Q<N+1>: <sub-decision>: <recommended value>
- Q<N+2>: <sub-decision>: <recommended value>]

Alternatives to consider:
- (a) <option> — <one-line tradeoff>
- (b) <option> — <one-line tradeoff>
- (c) <option> — <one-line tradeoff>
```

`Q<N>` numbering runs continuously across rounds (Q1…Q4 in round one, Q5… in round two; visible depth). Close the round with one probe inviting a constraint that breaks the recommendations, and the note that the user may answer in any order. Wait for the answers before computing the next round. The recommendation+basis discipline holds per question. Inline prose carries the recommendation, its reasoning, AND the probe in one readable block; a card cannot.

**One verdict marker, at most one context line.** The `My recommendation:` line is the *single* verdict marker for the question. Never stack a second one: no standalone `**(RECOMMENDED)**` badge line above it, and no `(recommended)` tag repeated in the Alternatives list; the recommended answer is named once, on that line. Per-question context is at most ONE line and usually absent. The round-header restate carries shared context, so add a line only when it doesn't reach this question or the session just resumed after a gap.

**A recommendation that fixes more than one decision lists every part.** When the recommended answer also settles other decisions (a design that picks a platform, a runtime, a credential, an identity), list each under `Commits you to:` with its own `Q<N>`. They are parts of the one recommendation, not a second verdict, and each is registered `open` at ask-time like any question. An explicit acceptance of the headline ("Q5 yes", "accept all recommendations") resolves each listed part to its recommended value (on the page, only the parts the user ticks); the user can overturn one by its number. When an accept-shorthand resolves commitment rows, name their `Q<N>` ids in one line. Choosing an alternative or rejecting the headline withdraws the parts, and any sub-decision the chosen alternative implies is asked in the next round. A sub-decision the recommendation assumes but does not list is not decided by any answer to the headline: list it, or keep it out of the recommendation. A question with a `Commits you to:` block is never asked through an `AskUserQuestion` card; on the page, its parts are the question's `commits` entries. Row shape: [`context/loop.md`](context/loop.md) "Commitment rows".

**Emoji anchors (default off, still configurable).** When `${user_config.use_emoji_question_markers}` is true, prefix the `Q<N>:` line with `❓` and the `My recommendation:` line with `➡️`. When it is false (the default), keep the undecorated shape above. Decoration of the existing single verdict marker, never a second one. Conversational rendering only: the ledger, register, and Brief stay plain, and `Q<N>` remains the answer handle. The option is the plugin's `use_emoji_question_markers` user config; set it true for anchors. A user instruction against emoji as formatting wins over the option: keep the plain shape, and the page start command then passes `--emoji-markers false` so the page matches.

**Define session shorthand once, then park it.** When a round introduces session-local shorthand, a coined label, an abbreviation, or cross-repo jargon the user may not share ("lanes", "gate vacuity"), define it in one clause at first use and record it in the ledger's shorthand glossary, then use the term freely. This is ephemeral session vocabulary, distinct from the project's ubiquitous language (owned by `/domain-driven-design:curate-language`), and never touches a project glossary. Ledger shape: [`context/loop.md`](context/loop.md) "Session-shorthand glossary".

**Partial-round resolution.** The user may answer any subset, in any order, in one reply. Unanswered questions stay OPEN on the frontier. Re-surface them at the top of the next round, labeled "unanswered from last round". NEVER silently resolve an unanswered question to its recommendation; the auto-guard applies inside rounds too. Honor accept-shorthands: "accept all recommendations" resolves the whole round to the recommended answers; "yes to Q5" / "Q5–Q7 yes" resolves that subset. Answers that reshape the tree ("actually, we don't need auth at all") invalidate pending questions. Recompute the frontier before re-asking anything.

**A hedged reply resolves only the headline.** A reply given with doubt ("yes?", "I think so", "probably") resolves at most the headline of the one question it can be tied to, never that question's `Commits you to:` rows and never the rest of the round. A hedged accept-shorthand ("accept all?") is not an accept-shorthand. Record the headline with a `hedged:` resolution, keep its commitment rows `open`, and echo back in one line what the headline commits to and which rows are still open. A hedged reply that cannot be tied to one question resolves nothing: restate the open rows.

**Register at ask-time; a reply that does not answer is not an answer.** The moment a round is asked, before any reply, write one `open` row per question into the ledger's open-question register. Then, after EVERY user reply and before doing anything else, check the reply against the register's `open` rows and restate any it did not address, in one line, even when the reply changed the subject entirely. Conversational drift is never consent, and the register, not the transcript, which a compaction can empty, is the authority. One exception, and only one: the acceptance-criteria coverage prompt gets no row even when it rides along in a round, because it carries no decision to track. Every real question in that same round is registered exactly as always. Row shape, statuses, and the drift-restate wording: [`context/loop.md`](context/loop.md) "The open-question register".

**Out-of-band output gets the same check, keyed on relevance.** A round can be overtaken by content the user did not write: a dispatched sub-agent's return, a background task notification, a team report, a Monitor firing. That is the ordinary consequence of not blocking the round. Check it against the `open` and `superseded-by-plan` rows (a superseded row is restated, never resolved by the return): a return touching nothing gets one line and the round stands, a return that contradicts an asked question's recommendation forces a restate naming the superseded recommendation, and a return that answers an open row from the environment resolves it. Re-present narrowly (a one-line pointer for the untouched, the full shape only for the row that moved), never hold the round, and never depend on being woken. The floor is the next user reply. Outcomes, shape, and the floor: [`context/loop.md`](context/loop.md) "Out-of-band drift".

**Rounds fire at phase boundaries.** When reached from inside another workflow's phase, emit the whole open set where the caller hands over, not partway through its phase; a mid-phase blocking question is the exception and states its justification in one line. Rationale: [`context/loop.md`](context/loop.md) "Where a round may fire".

**Visual-first for structural questions (default, not on-request).** When a question concerns structure, file/folder layout, before/after states, naming shapes, schema or flow alternatives, and a compact visual (fenced tree, diff, small table; roughly ≤30 lines) can carry it, LEAD with the visual and hang the question off it. A paragraph describing a tree is much harder to verify against the user's mental model than the tree itself; the visual IS the question. Before/after pairs beat single-state snapshots when the question is a migration. Skip only when no compact visual exists (genuinely abstract trade-offs) or when it would blow past ~30 lines. Then summarize and offer the full visual on request.

**Dialogue: the user drives too.** They may push back or reframe a decision (e.g. "what's hardest to roll back from?"). When they introduce a new axis, **reversibility** is the most common for V1, re-rank the options on it and REVISE your recommendation out loud, stated as old → new → why, where new may be a withheld open question ([re-emitting a changed recommendation](../../context/recommendation-basis.md)). Default V1 lens: prefer the most *reversible* start; defer the irreversible/expensive as an explicit out-of-scope decision, never a silent assumption.

**Facts are yours; decisions are the user's.** A *fact*, a path, a current value, an existing pattern, what a file already does, is resolved from the environment (Grep/Read/Glob) and STATED, never asked; spending a question on what the code already answers is friction, not interview. The environment is not only the working tree: when a task NAMES an external repo or resource, a sibling checkout under a known repo root / workspace layout, or an `owner/repo` reachable through its host, that is a resolvable fact too, so check the filesystem layout and query the repo host directly (e.g. `gh` for a named `owner/repo`) before defaulting to a user question. Cue, not mandate, except where a recommendation is consequential (next paragraph): there grounding is mandatory. Otherwise resolve what's cheaply resolvable, and don't turn every named mention into a research project. A *decision* with real tradeoffs and no environment answer ALWAYS goes to the user; never resolve one on their behalf, however obvious the answer looks. When a fact lookup is slow (deep exploration, external research), dispatch it to a sub-agent and DON'T block the round: a running lookup is an unsettled prerequisite, so only the questions downstream of it wait for the next round. Ask the rest of the frontier now.

**Ground before recommending.** Lightweight codebase gate per question (Grep/Read/Glob). If a recommendation needs more, external best-practice, a library API, deeper exploration, dispatch or do the lookup (research/exploration capability, or inline), then recommend grounded. A **consequential** recommendation (cross-repo, shared infrastructure, irreversible, or security) is never made from training recall or convention alone: ground it in the affected code plus its consumers, and in external research that reads official docs first, then authoritative articles, and notes recency and dissent. That lookup goes to a sub-agent under the non-blocking rule above, so only the questions downstream of it wait. The contract this plugin ships, the bar and its three outcomes, is [`${CLAUDE_PLUGIN_ROOT}/context/recommendation-basis.md`](../../context/recommendation-basis.md).

### Recommended answers

For EVERY question, propose an answer grounded in observed codebase state. User confirms (fast) or corrects (faster than explaining from scratch). When no codebase signal exists, a non-consequential question may be recommended from conventions, labeled `Basis: judgment`; a consequential one is grounded first, per "Ground before recommending". Every `My recommendation:` line carries a `Basis:` line under it, `verified` with the `file:line`, tool output, or URL it rests on, or `judgment` ([basis label](../../context/recommendation-basis.md)). Like `Checked against:`, it is part of the recommendation, not a second verdict marker and not the context line; on a card or the page it rides inside the option's basis text. Mark each recommendation with its one-line basis. In an inline round that marker IS the `My recommendation:` line (one verdict marker, never a second stacked badge); in an `AskUserQuestion` card it is the option tagged **(RECOMMENDED)**. Detail in [`context/loop.md`](context/loop.md) "Frontier rounds".

**A withheld question carries no recommendation marker.** A consequential question research cannot settle is the one exception to "every question carries a recommendation": the recommendation is **withheld**. It is asked open, never on a card, with a `Withheld:` line naming the evidence that would settle it in place of both the `My recommendation:` and `Basis:` lines; no option is tagged **(RECOMMENDED)**, and on the page its `recommendation` field carries the `Withheld:` text. It is registered like any question.

### Domain-aware behaviors

When the task touches domain concepts, these behaviors activate during Q&A. The probing behaviors run in any session; the two that write repo artifacts, **inline vocabulary update** and **ADR**, are engineering-only (per the Step 1 domain classification), so a general session, gated to a shared-understanding summary, never mutates a project glossary or proposes an ADR:

- **glossary challenge**. When the user uses a domain term two ways, or a term collides with an existing definition, probe it
- **domain scenario exploration**. Invent edge cases that probe concept boundaries ("what happens when a Customer cancels half an Order?")
- **inline vocabulary update** *(engineering sessions only)*. When a term resolves, invoke
  `/domain-driven-design:curate-language` immediately (if that plugin is installed; else
  record the term in the Brief's glossary notes). That skill owns discovery-first
  placement, the consumer's
  file shape, purity, canonical terms, rejected synonyms, and known-context routing; the interview
  resumes after the update
- **ADR, offered sparingly** *(engineering sessions only)*. Propose an architecture decision record only when a decision is hard to reverse AND surprising without context AND the result of a real trade-off. When the `architecture` plugin is installed, invoke `/architecture:record-decision` via the Skill tool, passing the decision and its rationale; it owns convention discovery, the no-convention offer-and-defer, and the write. Otherwise write to the repository's declared ADR convention (a managed `docs/adr/` README, a project rule, or an existing `docs/adr/` shape); if none is declared, offer and defer. Never prescribe a location or format

## Acceptance-criteria capture

Two behaviors ride on the moment acceptance criteria are captured. The first is always on; the
second fires only when the consuming team's convention selects it.

### Coverage prompt. Always on, asked once

While capturing acceptance criteria, ask ONE question: are the criteria missing an
**unwanted-behavior** case (an `IF <trigger>, THEN <response>` criterion) and a **state-driven**
case (a `WHILE <state>, <response>` criterion)? One prompt covering both, never a per-criterion
interrogation, and **"neither applies" is a valid answer** that closes it for the session. This runs
whatever the acceptance-criteria format resolves to, and with no convention surface present at all;
it is a coverage check, not a format.

It is **not** a `Q<N>` decision. Never write it into the open-question register, never mark it
`blocked`, and never route it to `### Deferred questions`. The register gates the contract, and a
coverage check parked there would hold a lock hostage to a question that carries no decision.

**It therefore does not bring the Step 3 register gate into scope by itself.** A synthesize-directly
run whose ONLY question was this prompt wrote no register, has nothing to gate, and skips the gate
exactly as a run that asked nothing does. Without this, that path would ask a question it is
forbidden to register and then trip a gate demanding the row.

**The exemption covers this prompt and nothing else.** It is not a license for a question asked
beside it. A residue decision, a frontier round, a gap surfaced mid-synthesis, a `blocked` row from
an unattended run: any OTHER question is a register question as usual. It writes its row at
ask-time and brings the gate into scope, whether or not the coverage prompt was asked in the same
breath. One coverage check is exempt; a round that happens to contain one is not.

Per action: `me`, `auto` routed to Q&A, and the Mixed path ask it inside a round. `auto` routed to
synthesize-directly asks it as the sole residue question. `lock` skips it, because invoking `lock`
is the user saying stop asking, and reports it unexamined exactly as a non-interactive run does.

### Non-interactive runs skip the ask and say so

A run with nobody to answer, a dispatched worker, a forked subagent, a headless invocation, or any
caller that declared the run unattended, **SKIPS** the ask instead of blocking on it, and the
session's returned summary states that **unwanted-behavior and state-driven coverage went
unexamined**. Write the same line into the Brief's `### Captured assumptions` so it outlives the
summary. A prompt nobody can answer must not stall the run and must not silently vanish.

**That line is the coverage note and nothing else.** It records that a check went unrun. It is never
a place to park a decision, it satisfies no part of the auto-guard, and it changes nothing about the
unattended ladder: a decision genuinely the user's is still recorded `blocked`, still written to
`### Deferred questions` with **arbiter: USER-RESERVED**, and still named as a blocker. Capturing a
user's decision as an assumption is the failure the auto-guard exists to prevent, and no line here
licenses it.

The unattended condition is **declared by the caller, never sniffed**, the same rule the auto-guard's
unattended path states. There is no supported way for a session to observe that it is
non-interactive, so never read an environment variable to decide this.

### EARS tags, when the convention selects them

Resolve `acceptance_criteria_format` per the ladder below. Under `free-text`, the default and every
degrade, emit criteria exactly as today: `- <testable criterion>`, untagged, byte-comparable in
shape to a run with no convention surface at all. Under `ears`, every emitted criterion carries a
bracketed pattern prefix on that same plain-bullet form:

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

The five names are exactly `ubiquitous`, `event-driven`, `state-driven`, `unwanted-behavior`, and
`optional-feature`. This vocabulary is a contract with whatever reads the tag downstream, and a name
spelled any other way, `unwanted_behavior`, `unwanted`, `event`, reads as no tag at all and breaks
detection silently rather than loudly. The tag prefixes the criterion; it never replaces the
testable sentence, and an untaggable criterion is a criterion still owed a shape, not a criterion
owed a sixth pattern.

Where the tags travel: they land in the Brief's `### Acceptance criteria`, and a consumer that
publishes the Brief verbatim as a tracker container body carries them with it. They do not reach
per-slice criteria, which are freshly authored by whatever decomposes the work, because a vertical
slice owns everything it grades.

### Resolution ladder for `acceptance_criteria_format`

Restated here rather than cited: an installed plugin never sees the publishing repository's
convention docs, so a path citation would make that publisher a runtime dependency of this session.

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
5. Default: `acceptance_criteria_format` is `free-text` — emit untagged plain-bullet
   criteria, exactly today's shape.
6. Degrade soft, and say so. No pointer line, no convention home on disk, no
   `authoring-formats/README.md`, no YAML block, an absent key, or an unrecognized value
   each resolve to the documented default. Name the cause in one clause and continue;
   never hard-fail, and never ask the operator to create the surface mid-task.
7. Report provenance whenever the resolved value shapes output: name the key, the value,
   and the layer it came from — `argument`, `team convention doc <path>`, or `default`.
```

This plugin ships the step-2 resolver at
`bash "${CLAUDE_PLUGIN_ROOT}/lib/resolve-convention-home.sh"`: exit 0 prints the home on stdout,
exit 1 means no pointer line is bound, exit 2 is usage, and exit 3 is a FAIL (two pointer lines
in one region, an unterminated or nested region, an invalid pointer path, or a pointer whose
target directory does not exist). Every non-zero exit is a
step-6 degrade, `free-text`, cause named in one clause, never a halt and never a prompt to go create
the surface.

## The interview loop

Five steps. Step 1 (Survey) runs every action. Step 1.5 (Auto-detect) runs on `auto` only. Step 2 (Q&A loop) runs on `me` or `auto`-routed-to-Q&A. Detail in [`context/loop.md`](context/loop.md).

### Step 1. Survey before you ask

Spend the first turn grounding yourself. Read the project's `CLAUDE.md` / `AGENTS.md` if not already in context, Glob/Grep keywords, scan `git log --oneline -20`, climb to the nearest domain-vocabulary file, list relevant project rules, check the topic's contract slice `<contract_dir>/<topic-slug>/` (default `docs/topics/`) for a prior PLAN.md / PRD / design artifacts and its memory slice `<memory_dir>/<topic-slug>/` (default `.work/`) for exploration / research artifacts.

Survey output: one paragraph "Here is what I see in the repo."

**Classify the domain** from what the survey shows. *engineering* (a build or behavior-change task, or a technical subject that yields a build artifact) or *general* (a decision or idea with no build surface). The deciding signal is the **task/build surface itself**, not the working directory: a general decision raised from inside a code repo is still general, and the engineering machinery must never engage on cwd alone. Repo/cwd is context that breaks the tie only when the task surface is genuinely indeterminate. Then lean engineering inside a code repo, else general. This is inferred, never asked; honor any explicit user override. The domain governs which machinery engages and what the session produces (see Purpose "Domain-routed"); it is orthogonal to the `me`/`auto`/`lock` action.

**Engineering sessions only**. If a prior PLAN.md Brief exists, ask whether to **resume**, **revise**, or **start fresh** (the latter appends a dated scope-change note to the top of the Brief capturing why before rewriting, and the commit carrying the rewrite states the pivot rationale. The contract is branch-tracked, so git log is the history). A general session or the `scope` action never creates or edits a PLAN.md Brief, so it skips this prompt.

Then route per action.

### Step 1.5. Auto-detect (default action only)

For `auto`: classify intent against `context/loop.md` "Step 1.5. Auto-detect" criteria. Three outcomes:

- **Synthesize directly** (clear) → skip Step 2; proceed to Step 3 (confirmation gate), then Step 4 (Persist)
- **Q&A loop** (fuzzy) → continue to Step 2
- **Mixed** → ask the residue (one round. The few open questions together), then synthesize; proceed to Step 3, then Step 4

**Auto-guard. Never decide an interactive choice for the user.** Synthesize-directly (and the Mixed path's "synthesize the rest") applies ONLY to decisions with a verifiable answer (codebase-resolvable) or an unambiguous conventional default. When a remaining decision is genuinely the user's, a design choice with real tradeoffs and no codebase answer, do NOT fold it into the Brief. STOP and either ask it inline (a residue round) or offer to switch: *"This is a real design decision, not mine to pick. Answer it, or want me to run `/planning:interview me` and drive every open branch to a decision?"* Silently capturing such a choice as an assumption is the failure mode this guard prevents.

**Unattended path: the guard holds, the run does not idle.** `/planning:interview` can be reached with no human to answer (a loop, a spawned worker, another skill's chain). The condition is **declared by the caller, never sniffed**. There is no supported way for a session to observe that it is non-interactive. Unattended, codebase-resolvable and unambiguous-conventional decisions resolve as usual and are recorded `auto-resolved (unattended)`; a decision genuinely the user's is recorded `blocked` in the register, written to the Brief's `### Deferred questions` with **arbiter: USER-RESERVED**, and named as a blocker in the output. That extends the auto-guard rather than excepting it. The guard forbids the choice *disappearing*, and a named blocker is the choice made maximally visible. Stop on blockers; never wait indefinitely, and never read absence of objection as confirmation. Full ladder: [`context/loop.md`](context/loop.md) "Unattended path".

For `me` / `me <topic>`: skip Step 1.5, force Q&A.
For `scope` / `scope <topic>`: skip Step 1.5; with no topic, scope the current task. Run Step 2–3, then the **`scope` persist path** below instead of the engineering Brief in Step 4. Do not offer `/planning:plan` handoff; stop after returning decisions.
For `lock`: skip Step 1.5 AND Step 2, synthesize directly. If a gap surfaces mid-synthesis, STOP and surface; do not fudge.

### Step 2. Drive the frontier-rounds loop

Run rounds: restate working understanding → compute the frontier (every open question whose prerequisites are settled) → ask the whole frontier as one numbered set → capture the answers → recompute. Categorize each open item as resolvable / blocked / defer-with-assumption / defer-fully. The restate is also the **session-hop anchor**: after a handoff, resume, or long gap it re-establishes the decided set and this round's stakes before any question, so a returning reader is grounded without re-reading the whole ledger.

Full surfacing-question taxonomy + categorization heuristics in [`context/loop.md`](context/loop.md).

On the page surface, Step 3's confirmation gate runs on the page: post the restatement with a `restate` op and wait for the user's `confirm-understanding` event, per [`context/surface.md`](context/surface.md) "Confirmation gate".

**`me` mode** maintains a **decision-tree ledger**. One live checkbox per branch, ticked on resolve, remaining-open surfaced periodically (not every turn. Keeps the flow clean like the inline format). Persist each answer the moment it locks in (Step 4), loop until zero open consequential branches. Ask via the inline format (Stance "Relentless mode"). Ledger shape + per-round mechanics + reversibility-lens question shape in [`context/loop.md`](context/loop.md) "Decision-tree ledger".

**Keep a running constraint ledger.** The ledger's `## Constraint ledger` section holds one row per constraint. Every constraint the user states is written at once as `confirmed`, the moment it is stated, never batched to Step 4; a constraint taken from an upstream artifact is `inherited` (a prior Brief, a PRD, a design resolution). Every recommendation names the constraints it was checked against on one line under `My recommendation:`, `Checked against: C1, C3` or `Checked against: none`. That line is part of the recommendation, not a second verdict marker and not the question's context line. On the page it opens the question's `facts` field, each constraint named in words, since the page's wording lint flags a bare `C<N>` ([`context/surface.md`](context/surface.md) "Wording lint"). A card has no recommendation line, so a question goes on an `AskUserQuestion` card only when its line would read `Checked against: none`; one that cites a constraint is asked in prose. An `inherited` constraint the contract relies on is asked as a register row at ask-time: the answer flips its tag to `confirmed`, and unattended it takes the ladder (`blocked`, USER-RESERVED, when it is the user's call). In `lock` a relied-on inherited constraint is a gap: STOP and surface it (Step 1.5); in `auto` direct synthesis it makes the path Mixed and is asked in the residue round. Row shape: [`context/loop.md`](context/loop.md) "Constraint ledger".

**Composed artifacts are candidates.** A design from explore or research output, or read from an existing implementation, is a candidate, never a recommendation, until re-derived against the constraint ledger: check it against every row, recommend only what survives, and name the rows on its `Checked against:` line. A research or exploration brief dispatched mid-interview carries the constraint ledger verbatim.

**Label evidence by when it was true.** When a recommendation rests on historical evidence (past metrics, merged PRs, an existing implementation) and the survey finds a recent process change or cannot tell, label each finding `past`, `current`, or `intended` before a recommendation rests on it. A process change is one the survey finds (a changelog, commit, ticket, or user statement dated after the evidence window) or cannot rule out. State or ask any currency you cannot establish; past-only evidence never alone grounds a recommendation.

**What, not how: the mechanism tripwire.** "Does not plan implementation" has a trigger. When a question or its recommendation names a mechanism (a tool, an API, a credential or token scope, a runtime, a platform per step), ask once whether the user wants mechanism-level decisions settled now or at planning. Ask it in the same round as the first mechanism-naming question and register it like any other question; until it is answered, recommendations carry no mechanism part. When the answer is "at planning", no later recommendation fixes a mechanism, and every still-`open` mechanism row, commitment rows included, becomes `deferred`: carried to the Brief's `### Deferred questions` under the arbiter rule in an engineering session, listed as deferred in the shared-understanding summary in a general one. When the answer is "now", write `C<N> | confirmed | mechanism decisions settled in this interview | user, round <N>` at once, and the Brief's Constraints records that this topic overrides "does not plan implementation".

**Sweep for assumptions before Step 3.** In `me` and `auto` with a register, including the `auto` Mixed path after its residue round, the loop ends with a fresh-context assumption sweep. Once the frontier is empty, and before the Step 3 register gate and confirmation gate, dispatch a non-fork sub-agent to inventory undecided details, hidden defaults, contradictions, and hedged or free-text rows across the ledger, the recommendations, and any composed artifacts. You turn each item into a register row at the next contiguous `Q<N>`, a stated fact, or, for hedged rows, a line in the confirmation restate. Any `open` row it adds returns the run to Step 2, and the next sweep covers only what the new answers changed; Step 3 is reached when a sweep adds no `open` row. A run that asked no question skips it, and so does `lock`; unattended, an item that is the user's decision is `blocked`. The acceptance-criteria coverage prompt is never a sweep item. Scope, item shape, and disposition: [`context/assumption-sweep.md`](context/assumption-sweep.md).

### Step 3. Recognize the stop condition

Stop when the frontier is empty. Every unknown the task depends on resolved OR captured as named assumption. The user can describe the goal in one paragraph without contradicting the constraints, and acceptance criteria are testable. The coverage prompt has been asked once and answered ("neither applies" counts), or skipped and reported unexamined per "Acceptance-criteria capture". Don't stop early on impatience; don't keep asking past the stop condition.

**Register gate.** Before persisting the contract or handing off, run the register through its mechanical check. An empty frontier is a judgment, and this is the part of it a script can decide. **Ledger only here**: the Brief does not exist yet (Step 4 writes it), and `--brief` names a file it requires to be present.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-open-questions.sh" \
  --ledger <memory_dir>/<topic-slug>/interview-checklist.md
```

Exit 1 (a row is `open` or `superseded-by-plan`) and exit 2 (ungradeable) both HALT. Resolve or explicitly retire an `open` row and re-run; a `superseded-by-plan` row leaves only on the user's reply to it ([`context/loop.md`](context/loop.md) "Superseded by plan"). Never lock a contract over a non-zero exit; that is the reported failure restated. **A run that asked no question wrote no register, has nothing to gate, and skips this**. `lock` synthesizing with no gap, and equally `auto` routing to synthesize-directly with no open decision. The carve-out is about the absence of questions, never about which action produced it: the moment ANY question exists. Asked, surfaced mid-synthesis, or blocked unattended. A register exists and the gate applies. The `--brief` cross-check runs in Step 4, once there is a Brief to cross-check against.

**One thing is not a question for this purpose: the acceptance-criteria coverage prompt.** It carries no decision, writes no register row, and asking it does not by itself make a register exist or bring this gate into scope, so a synthesize-directly run whose only question was the coverage prompt still skips the gate. Read it narrowly. It exempts that one prompt, never a real question asked in the same round or the same session: any other question still writes its row at ask-time and still brings the gate into scope. See "Acceptance-criteria capture".

**Confirmation gate (`me` and `auto`):** an empty frontier is necessary but not sufficient. Before persisting the contract or handing off, restate the shared understanding and get the user's explicit confirmation that it is reached. Do not act on the interview's output until they confirm. `lock` is exempt: invoking it IS the confirmation (its STOP-on-gap rule still applies).

**Recap and procedure check (`me` and `auto`).** Before asking for confirmation, the restatement carries a Q&A recap: one line per `Q<N>` in the ledger's `## Open-question register`, shaped `Q<N> <status>: <question text> (<resolution>)`, generated from the register on disk, never from the transcript, so it survives a compaction. Then run the procedure check beside the register gate, ledger only, and cite its exit code and `procedure=` field as the evidence that the procedure ran, never your own account of it:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-open-questions.sh" \
  --ledger <memory_dir>/<topic-slug>/interview-checklist.md --procedure
```

A non-zero exit HALTS the confirmation request; stderr names each defect (a round missing from the register, a retired row with no resolution). Fix the ledger and re-run. It checks only what a file can show. Not checked, and not implied by a green exit or by the recap: whether the Step 1 survey grounded the questions, whether the domain was classified, whether register rows were written at ask-time rather than answer-time, and whether the frontier was recomputed between rounds. `/planning:audit-answers` adversarially re-validates the answers; the recap shows the user the Q&A and the check shows the procedure ran, and neither composes nor duplicates it. A run with no register skips both.

**`me` mode tightening:** "captured as named assumption" is NOT a valid stop for a *consequential* branch. Drive it to a decision (a decision MAY be "defer to post-V1", but it must be explicit and surfaced, never silent). The stop condition is an **empty decision-tree ledger** plus the confirmation gate. Not a question count.

### Step 4. Persist the contract

Derive `<topic-slug>` from the task or current branch name (kebab-case, ≤40 chars, shared with `/planning:prd`, `/planning:design`, `/planning:plan`). The contract lands in the topic's contract slice `<contract_dir>/<topic-slug>/` (default `docs/topics/`); working ledgers land in the memory slice `<memory_dir>/<topic-slug>/` (default `.work/`). Roots, tier, and precedence resolve per the topic-docs binding [`${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md`](${CLAUDE_PLUGIN_ROOT}/reference/topic-docs.md). *What* gets persisted follows the Step 1 domain classification.

**Neither slice is a durable home.** Under `contract_tier: branch`, the contract slice is pruned before the branch merges: durable outcomes graduate first, decisions and specs to an ADR or spec through the vault seam and follow-ups to a tracker item, then a final commit deletes `<contract_dir>/<topic-slug>/`, and the topic-docs convention's required check fails a PR that leaves any path under it. That close-out belongs to `/planning:plan` (the binding's "Close-out: the vault seam"). The memory slice self-ignores and never reaches git at all, so under `contract_tier: local`, where the contract sits there, nothing is pruned and the required check has nothing to fail. So when the user asks where to keep something past this branch, never offer either slice: name the graduated destination, an ADR, a spec, or a tracker item, and the contract slice holds it only until that graduation.

**General (non-engineering) sessions** persist a shared-understanding summary, the decisions reached and their rationale, to the memory slice (nothing downstream enforces against it), or inline when the user wants no artifact. NEVER create or edit a PLAN.md Brief for a general decision: the `## Brief`/`## Plan` structure is the engineering shape. In `me` mode, the incremental-persistence and handoff discipline below still applies, with the summary standing in for the Brief.

**Engineering sessions** write the Brief section into `<contract_dir>/<topic-slug>/PLAN.md` (default `docs/topics/`; the memory slice under `contract_tier: local`), a contract document committed on the task branch as it locks, **except `scope` action**, which never writes `PLAN.md` (see below). The rest of this step, everything below, is the Brief machinery and is engineering-only.

**`scope` action (ad hoc, no Brief).** When the action is `scope`, do **not** create or edit
`PLAN.md` in the contract slice. After the Step 3 register gate passes, emit a **`Scope decisions:`**
section in chat (one `- <question>: <answer>` line per resolved row) and keep the open-question
ledger in the memory slice as the durable record. With no Brief to hold them, every `deferred` and
`blocked` row is returned in the same section as a `Deferred: Q<N> <question> (arbiter: <tag>)` or
`Blocked: Q<N> <question> (arbiter: <tag>)` line, each leading with its `Q<N>` id and carrying its
arbiter (`/planning:plan` by default, `USER-RESERVED` under the rule in
[`context/loop.md`](context/loop.md) "Brief template (the literal shape)"), so a choice never
silently disappears. A `Blocked:` line, and a `Deferred:` line tagged `USER-RESERVED`, tells the
caller to stop and ask the user that question before going on. The caller owns where these lines
land (for example a repo-sweep step commit). Skip the Step 4 `--brief` cross-check and skip
`/planning:plan` handoff.

**`me` mode persists incrementally, not just at the end.** Lock each answer into the decision-tree ledger (`interview-checklist.md`) + the relevant PLAN.md Brief section the moment it resolves, except in **`scope` action**, which never writes PLAN.md sections. So a crash, context clear, or overflow never loses resolved branches, and a handoff can happen at any round boundary with nothing left to flush. Offer a handoff (`/session-flow:handoff` if installed, otherwise write a resume note in the topic's memory slice) when the user or the harness signals it, or when branches keep opening faster than they close (Step 5); never on your own estimate of remaining context. Target the light V1-spec Brief shape (scope / schema / code-surface bullets). Keep it terse.

PLAN.md holds `## Brief` + `## Plan` sections. `/planning:interview` writes only the Brief section; the Plan section stays empty until `/planning:plan` fills it.

**Cross-check the Brief once it exists.** Immediately after writing it, re-run the register gate with `--procedure --brief <contract_dir>/<topic-slug>/PLAN.md`. This run proves every `deferred` and `blocked` row actually reached `### Deferred questions`, and that the Brief carries all seven template headings (TLDR, Goal, Constraints, Acceptance criteria, Captured assumptions, Out-of-scope, Deferred questions); the Step 3 run could not check either because the file was not written yet. It matches on the `Q<N>` id, so each deferred entry must lead with one. A non-zero exit means the Brief is missing a question the ledger retired or a template heading: fix the Brief, do not retire the row. A general session writes no Brief and skips this.

If a PLAN.md Brief exists and user chose **revise**, edit the Brief in-place. If **start fresh**, append a dated scope-change note to the top of the Brief capturing why before rewriting. Never silently overwrite, and let the commit message carry the pivot rationale.

Section schema: write the literal `## Brief` template (TLDR / Goal / Constraints / Acceptance criteria / Captured assumptions / Out-of-scope / Deferred questions) per [`context/loop.md`](context/loop.md) "Brief template (the literal shape)". `### Acceptance criteria` stays plain bullets in both formats, tagged or not, per "Acceptance-criteria capture" above; it is never converted to checkboxes. Each **Deferred question** leads with its **`Q<N>` id**, the tie back to its register row and what the Step 4 gate greps this section for, and carries an **arbiter tag** (`/planning:plan` default, or `USER-RESERVED` when its resolution could change acceptance criteria / out-of-scope / constraints). Both are required; loop.md covers when to use which.

### Step 5. Hand off

Route the handoff by what the session produced. **A general (non-engineering) session is terminal**. It produced a shared-understanding summary, not a Brief; deliver that summary and stop, offering no pipeline handoff (nothing downstream consumes it). **An engineering session** wrote a PLAN.md Brief. Recommend the next step per task shape:

- **Code change with unknowns about the codebase** → clear context, then codebase exploration (`/discovery:explore` if installed. It reads the Brief as scope)
- **Code change relying on external libs/APIs/best-practices** → external research (`/discovery:research` if installed)
- **Already understand the codebase and the externals** → `/planning:plan`
- **Task is small and the contract IS the plan** → proceed directly to implementation
- **Interview outgrew one session (branches keep opening faster than they close, or the user or harness asks for a pause)** → handoff now (`/session-flow:handoff` if installed, otherwise write a resume note), clear, resume. The ledger + Brief survive; resume continues from the first open branch. Before the first resumed round, resolve the surface through `${CLAUDE_PLUGIN_ROOT}` again (never an absolute path copied from the handoff) and run `round.sh doctor --ledger <ledger>`, which lists what the running version needs and the ledger lacks ([`context/surface.md`](context/surface.md) "Resume")

Do NOT auto-clear or auto-invoke. Recommend; let the user pull the trigger.

## Session-config recommendation (model, effort, advisor)

Turn the interview's read of complexity and ambiguity into a recommendation for how the session
carrying the work forward should be configured. *When* it lands follows from *what* it configures:
an engineering interview recommends at the stop/handoff boundary, for the downstream execution
session; a terminal interview (a general decision, per Step 5) recommends at the early post-survey
surface and again at the stop boundary, for the current session.

Read [`context/session-config.md`](context/session-config.md) at that boundary, before forming the
recommendation: it owns the two orthogonal knobs and their picking signals, the advisor pairing,
the rule that current model and effort names are fetched live and never pinned (and that a failed
fetch degrades rather than halts), the advisory framing, and the per-surface wording. Do not form
the recommendation from this summary.

## What this skill does NOT do

- `context/gotchas.md`. Failure patterns from real sessions

- **Does not deep-dive the codebase**. Step 1 is a fast survey; the codebase gate in Step 2 is a lightweight per-question check (Grep/Read/Glob). Neither is exploration-depth work. If exploration grows beyond quick lookups, stop and recommend the exploration capability
- **Does not plan implementation**. The Brief says *what* and *what we are assuming*; `/planning:plan` says *how*. Resist drafting an approach mid-interview
- **Does not write code or run tests**. Discovery skill. In an engineering session it DOES write domain docs outside the topic's slices when the project keeps them: domain-vocabulary updates (inline, between questions) and ADRs (written through `/architecture:record-decision` when that plugin is installed, else by hand into the declared convention) are first-class interview outputs alongside the Brief (a general session writes none)
- **Does not adversarially attack the user's idea**. That is `/planning:devils-advocate`. Domain scenario exploration (probing concept boundaries through invented edge cases) discovers domain semantics. It is not plan-attacking. If you find yourself wanting to push back on the goal itself, surface once, capture response, continue
- **Does not gate truly mechanical work**. Typo, lint-only, whitespace, comment, single-line non-behavioral fix, and routine dependency bumps skip `/planning:interview`. Everything that creates or changes behavior, contracts, structure, or design is **interview-first by default**. Auto-detect keeps that cheap (synthesize-on-clear, relentless-Q&A-on-fuzzy). The bar is behavior-change, not fuzziness
- **Does not fudge gaps in `lock` mode**. If a true unknown surfaces during synthesis, STOP and surface it. Fall back to `auto` or `me` instead of guessing
- **Does not export Gherkin**. Named as a deferred extension point so its absence reads as a decision rather than an oversight: nothing here emits `.feature` files or `Given`/`When`/`Then` scenarios, and the EARS tags are a bracketed prefix vocabulary on a plain bullet, not a step grammar. A Gherkin export is a separate slice against a separate contract, and none of it is built here

## Next

- Contract locked: /planning:plan.
- Design-significant threads remain: /planning:design.

## Composition with other skills

| When | Skill | How it composes |
|---|---|---|
| Pre-task fuzzy intent or lock-the-brief | **`/planning:interview`** (this) | Produces PLAN.md Brief |
| Product intent fuzzy (whose problem, what success) | `/planning:prd` | Upstream of `/planning:interview`; PRD answers *what for whom and why* |
| Need codebase grounding | `/discovery:explore` (if installed) | Reads PLAN.md Brief as scope |
| Need external evidence | `/discovery:research` (if installed) | Reads PLAN.md Brief as scope |
| A question needs something built to react to | `/prototype:explore-directions` (look and feel) or `/prototype:pressure-test` (logic, state, data shape) (if installed) | Mid-interview detour: confirm scope and checkpoint, build the throwaway, react to it, return and answer in one line |
| Plan the implementation | `/planning:plan` | Reads PLAN.md Brief + explore + research findings |
| Stress-test the plan | `/planning:devils-advocate` | Adversarial pass on `/planning:plan` output |
| Validate the interview's answers via agents | `/planning:audit-answers` | Fresh validators challenge each answer in the filled ledger (hand-answered or auto-accepted); only the doubtful ones return as human questions. The Step 3 recap and `--procedure` check show the Q&A and that the procedure ran; this re-validates the answers, and neither duplicates the other |
| Record a decision that earns an ADR | `/architecture:record-decision` (if installed) | Owns ADR convention discovery, the no-convention offer-and-defer, and the write; without it the interview writes to the declared convention or defers |
| Pause and resume later | `/session-flow:handoff` (if installed) | Captures session state, distinct from the Brief (mid-task pause vs pre-execution intent) |

**Mid-interview composition (`me` mode):** research, exploration, prototyping, and handoff are not only downstream. Invoke them *during* the interview when a recommendation needs external/codebase grounding, when a question needs something built to react to, or when branches outgrow the session. Return to the open branch after. **The ungrillable question:** when a look, feel, or behavior question cannot be answered by asking. The user has to see the thing to know what they think. Stop grilling and route it to a throwaway prototype: `/prototype:explore-directions` (look and feel) or `/prototype:pressure-test` (logic, state, data shape), invoked via the Skill tool if installed. Those skills gate their own model-initiated entry, so confirm the spike's scope with the user and checkpoint this interview before handing off. The detour leaves an active workflow. Checkpointing is persistence the interview already owes: the question registered `open` at ask-time, plus the ledger and Brief written per lock-in, which is what lets the open branch survive the detour. Then come back and answer the question in one line. The prototype is the instrument that produces the answer, not a deliverable; it is thrown away.

`/planning:interview` is sister to `/planning:plan`: one resolves *what*, the other resolves *how*. They share the topic slug, share the directory, feed each other.
