---
description: "Rounds of numbered, recommended questions that bring a task, proposal, or choice to shared understanding. An engineering task locks a PLAN.md Brief (goal, constraints, acceptance criteria, assumptions). Use when: 'interview me', 'lock the brief', 'spec this task', 'grill me', 'this is underspecified', 'ask me questions first', 'what do you need to know', 'I have an idea', 'help me think this through', 'acceptance criteria', 'how will we know this is done', or before work whose diff is not quick to review and cheap to retry; skip one that is."
argument-hint: "[me|lock|scope|share|product] [topic]"
user-invocable: true
disable-model-invocation: false
metadata:
  workflow-stage: contract
  summary: Interview in frontier rounds until the task contract is locked
---

**Arguments.** `[me|lock|scope|share|product] [topic]`. e.g., /planning:interview, /planning:interview me, /planning:interview lock, /planning:interview scope, /planning:interview share <topic>, /planning:interview product <idea>, /planning:interview <topic>

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
contains git. The dated record for that composition claim is the
[gather-block convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/gather-block/README.md#the-pre-compute-block-runs-as-one-shell-invocation),
"The pre-compute block runs as one shell invocation".

## Variables

Arguments: `$ARGUMENTS`. `time_units` user layer for [`problem-framing.md`](../../context/problem-framing.md) "Time units": `${user_config.time_units}` (unexpanded means unset).

Shared-session tunnel for [`context/lane-shared.md`](context/lane-shared.md): `tunnel_hostname`: `${user_config.tunnel_hostname}`; `tunnel_token_file`: `${user_config.tunnel_token_file}`; `tunnel_api_token_file`: `${user_config.tunnel_api_token_file}` (an empty hostname means no named tunnel: a quick tunnel).

## Purpose

Rework often comes from acting on assumptions the user never made and the agent never surfaced, an **underspecified** task, one missing the constraints needed to act safely. `/planning:interview` is the pipeline's underspecification resolver: a structured pass driving every unknown the task depends on to a decision OR capturing it as a named, explicit assumption, before exploration, planning, or execution start.

The **pre-clarity** stage. Upstream of exploration, research, and `/planning:plan`. `/planning:plan` presupposes a coherent task; `/planning:interview` produces one out of fuzzy intent. The contract it writes is the target every later stage aims at.

**Supportive, not adversarial.** `/planning:devils-advocate` attacks an existing artifact after the fact. `/planning:interview` walks alongside the user to extract a clear contract from the start. The `product` action is the one exception: the user asked for the idea itself to be tested ([`context/product.md`](context/product.md)).

**Domain-routed.** The interview loop is universal. Any task, proposal, or choice can be its subject. What the session *produces* depends on context: an engineering task in a code repo locks a PLAN.md Brief and can hand off to `/planning:plan`; a general decision drives to a shared understanding and ends there. The domain is inferred from the task's build surface. The problem itself decides, with repo and working directory as context that never suffices alone. Never asked, and it is orthogonal to the `me`/`auto`/`lock` action. Engineering machinery, codebase grounding, the Brief, ADR/glossary outputs, pipeline handoff, engages only when the context is engineering; the universal loop runs either way. A user can override the inference in prose ("this isn't a code task", "interview me on this decision"). An engineering session also reads the consumer's standards before any bundled default, asks the variation-intent question, and prompts quality requirements (NFRs), each scaled by the quality bar: read [`context/loop.md`](context/loop.md) "Engineering defaults" after the Step 1 survey.

**Two invocation modes, one schema.** When intent is fuzzy, `/planning:interview` runs the depth-first Q&A loop. When intent is already clear from conversation, `/planning:interview` synthesizes directly without asking (front-loaded brief). Both write the same output for the session's domain. A PLAN.md Brief for an engineering task, a shared-understanding summary otherwise. The default action **auto-detects** which mode fits and routes accordingly. **Cost framing**: every clarification round-trip skipped is time and tokens saved. Auto-detect removes redundant Q&A; explicit `lock` asks only its one problem question when the user has already given the answer.

## Emit checklist

For interview sessions with ≥2 open questions OR explicit `me` mode, copy `templates/checklist.md` into the topic's memory slice as `<memory_dir>/<topic-slug>/interview-checklist.md` (default `.work/`; **one ledger per topic**. Not per session). Re-interview appends `## Resolved (<round>, <date>)` sections; do not create `interview-checklist-2.md`. Tick each step as completed. Steps 1, 3, 4 are mandatory; Steps 1.5 + 2 are mode-conditional.

The ledger's `## Open-question register` is emitted the moment **any** round is asked, whatever that threshold says. It has to exist before the first reply arrives. The acceptance-criteria coverage prompt does not count as a round here: it writes no register row and does not by itself make the register exist or bring the register gate into scope ([`context/coverage-prompt.md`](context/coverage-prompt.md)). Register mechanics, the drift check, the unattended ladder, and the gate that grades it: [`context/loop.md`](context/loop.md) "The open-question register".

## Gates

Five gates halt this skill. They are stated here, near the top of the file, so they stay in view; the full rule is in the step each line names, and the two never differ in what they forbid.

- **The user's decisions are never synthesized.** Synthesize-directly and the Mixed path's synthesized rest resolve only codebase-resolvable facts and unambiguous conventional defaults. A decision that is genuinely the user's is asked, never folded into the Brief or captured as an assumption. Unattended, and only when the caller declares it, that decision is recorded `blocked` with arbiter `USER-RESERVED` and named as a blocker. Full rule: Step 1.5, the auto-guard and its unattended path.
- **A gap during `lock` synthesis halts the run.** Stop and surface the gap to the user; never fudge it with a guess. `lock` confirms the problem with one question and takes its invocation as confirmation of the rest; neither exempts it from this halt. Full rule: the Action Router `lock` row and Step 1.5.
- **The register gate runs before the contract locks.** Before persisting the contract or handing off, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-open-questions.sh" --ledger <memory_dir>/<topic-slug>/interview-checklist.md`; exit 1 and exit 2 both halt. Only a run that asked no question skips it; the acceptance-criteria coverage prompt is not a question for this purpose, and any other question is ([`context/coverage-prompt.md`](context/coverage-prompt.md)). Full rule: Step 3, "Register gate".
- **The confirmation gate holds the contract until the user confirms.** In `me` and `auto`, the interview ends only on the user's explicit confirmation: before persisting the contract or handing off, restate the shared understanding, opening with the one-line problem, and wait for that confirmation. `lock` confirms the problem with one registered question and its invocation confirms the rest; its STOP-on-gap rule still applies. Full rule: Step 3, "Confirmation gate".
- **The Brief is cross-checked once it exists.** Immediately after writing the Brief, run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-open-questions.sh" --ledger <memory_dir>/<topic-slug>/interview-checklist.md --procedure --brief <memory_dir>/<topic-slug>/PLAN.md`, plus `--surface '<data_dir>'` on a page-surface run; a non-zero exit halts. Fix a missing deferred question or heading in the Brief, never by retiring a row; exit 1 with `brief=unconfirmed` clears only after the user confirms a fresh `restate` and the Brief is exported again. A run that writes no Brief (a general session, `scope`) skips it. Full rule: Step 4, "Cross-check the Brief once it exists".

## Action Router

Parse `$ARGUMENTS` to determine the action. Empty argument routes to `auto` (the intelligent default), and `auto` never picks `product`. Which **leans to `me`-mode relentless prose Q&A by default** unless context heavily informs otherwise (see "Default action leans to `me`" below).

| Argument | Action | When to use |
|----------|--------|-------------|
| *(empty)* | **`auto` (default → leans `me`)** | Survey context, detect gaps; route to relentless prose Q&A unless intent is already crystal-clear or the user said "just lock it" |
| `me` | **Force relentless Q&A** | "Interview me", "ask me everything", "relentless". Skip auto-detect; drive EVERY decision-tree branch to a decision, uncapped, no silent assumptions |
| `me <topic>` | **Force Q&A on narrow topic** | "Interview me about the auth approach". Q&A loop scoped to topic |
| `lock` | **Force synthesis, one problem question** | "Stop asking, just write it", "I'm clear, lock the brief". Skip auto-detect, confirm the one-line problem with one question, synthesize directly. If a real gap surfaces during synthesis, STOP and surface it (do not fudge) |
| `scope` / `scope <topic>` | **Ad hoc scope round** | Short scope Q&A before another skill: ledger + register gate; **no** `PLAN.md` Brief; return `Scope decisions:` for the caller |
| `share [<topic>]` | **Shared session** | "Run this interview as a shared session", "let the designer and the PO answer together". Same loop and gates; the round goes to a page several people answer, per [`context/lane-shared.md`](context/lane-shared.md) |
| `product <idea>` | **Product stress-test** | Reached only by the `product` action, which these idea phrases select when invoking the skill: "should I build this", "is this worth building", "grill me" about a product idea (a "grill me" about a task is `auto`). Skip auto-detect; read [`context/product.md`](context/product.md) and run it: one question per turn from the twenty product principles, then its verdict in place of a Brief |
| `<topic>` | **`auto` on narrow topic** | "Interview the caching approach". Same intelligent default, narrower scope |

Unknown actions route to `auto`; surface the unrecognized request as a one-line side note.

**Default action leans to `me` (relentless prose rounds).** When invoked with no args (or by proactive auto-trigger), bias toward `me`-mode. Drive open decisions through frontier-rounds prose Q&A. Fall back to direct synthesis (`lock`-style) ONLY when context heavily informs against asking: intent already crystal-clear with no open decisions, OR the user signaled "just lock it / stop asking". Auto-detect's synthesize-directly path is for the genuinely-clear case, not the default posture.

**Question surface: inline prose by default.** Rounds render as numbered inline prose. Dictation-friendly, no per-question cap, and each question carries its recommendation, reasoning, and probe in one readable block. `AskUserQuestion` is an opt-in surface, enabled via the plugin's `use_ask_user_question` user config (`${user_config.use_ask_user_question}`, default off). When opted in, use it ONLY for a round of mutually independent questions that fits one `AskUserQuestion` call and whose questions are **simple selections or binary confirms** (the per-call question limit: <https://code.claude.com/docs/en/agent-sdk/user-input#limitations>, as of 2026-10-11; recheck when that section changes the per-call question limit). A card carries options, not a recommendation's reasoning or a constraint-surfacing probe, so any question needing its basis argued stays prose. Fall back to prose when the frontier exceeds that limit, any question in the round depends on another, or a question needs more than a pick. The card cannot express a dependency or a rationale, and chunking a round across multiple cards fragments it. When in doubt, prose.

**Question lanes.** Pick the lane from this table and read only its spoke. All three carry one question shape, [`context/question-shape.md`](context/question-shape.md); read it before writing a question to the page or a shared session. Configured `surface`: **`${user_config.surface}`**; `use_emoji_question_markers`: `${user_config.use_emoji_question_markers}`; `shared_session_open_browser`: `${user_config.shared_session_open_browser}`. A value still shown as its `${user_config.KEY}` token is unset and takes that key's declared default: `surface` `terminal`, `use_emoji_question_markers` `false`, `shared_session_open_browser` `true`. Spokes arrive unexpanded, so put these resolved values in place of their `${user_config.KEY}` tokens.

| Lane | When | Read |
|---|---|---|
| terminal | `surface` is `terminal`, unset or unknown, and no other lane was asked for | nothing more: "Question surface: inline prose by default" above and the Stance below |
| page | `surface` is `page`, or the user asks for the page (offer it on a dense terminal round): start it before the first round and ask no round inline | [`context/lane-page.md`](context/lane-page.md), then [`context/surface.md`](context/surface.md). The terminal stays an input, mirrored with `record-terminal`. A decision this session records or revises in the ledger is mirrored the same way. |
| shared | `share [<topic>]`, or several people should answer one interview together | [`context/lane-shared.md`](context/lane-shared.md): one session per audience, several may run at once |

## Stance: supportive, depth-first, opinionated

The Q&A path of this skill is one engine wrapped in a stop condition and an output contract. Four working principles drive it:

1. **Frontier-rounds loop**. A question is ready once every decision it rests on has an answer, and the set of ready questions is the **frontier**. On a webhook-retry task, the retry budget is ready on day one, while the alert threshold rests on that budget and so sits out until the budget is answered. Each round numbers every ready question, orders them by how much later work each answer would reshape, largest first, sends them together, and waits; the replies decide what is ready next time. One ready question still makes a round
2. **Survey-then-deep**. Before asking blind, do a fast breadth pass (repo files, recent commits, existing skills, relevant project rules) so questions land in real context
3. **Climb-to-anchor**. Find the nearest `CLAUDE.md`, `AGENTS.md`, domain-vocabulary file, or module README by walking UP from the relevant directory toward repo root; let those shape questions instead of asking what is already documented
4. **Immediate doc maintenance** *(engineering sessions only)*. When an answer resolves a domain
   term, invoke `/domain-driven-design:curate-language` via the Skill tool (if that plugin is enabled; else
   record the term and its definition in the resolution field of the open-question register row that resolved it) IMMEDIATELY between questions, not
   batched at end. Route
   decisions, gotchas, and conventions to their proper homes (ADR, project rules, side note) in the
   same response. A general session writes no repo docs. It drives to a shared-understanding summary
   only

**Intake the starting point.** Early in the loop (or before it), establish where the user is. One intake question that discloses their starting point; questions and recommendations calibrate to that disclosure. Route by what it shows; recommend, never auto-switch:

- **Idea stage** (a half-formed idea, "I just had this thought", the user does not yet know what they want): recommend `/planning:brainstorm`, which explores approaches and returns here with a handoff. If the user stays, follow [`problem-framing.md`](../../context/problem-framing.md) "Idea-stage requests".
- **User-facing product work** whose users or success measures are unsettled: recommend `/planning:prd` first.
- **Unfamiliar territory**: when the domain or codebase area is new to the USER, they can't yet evaluate options. Route to a blindspot-surfacing exploration FIRST (invoke `/discovery:blindspot <area>` via the Skill tool if enabled, otherwise a guided walkthrough of the area); an interview over unknown territory locks a contract the user can't assess.
- **A brainstorm handoff exists**: when `<memory_dir>/<topic-slug>/brainstorm.md` has a `## Handoff` block, read it as a settled upstream artifact and seed the Brief from it: Problem into `### Problem`, the Intent and Vision fields into the Goal's lines of the same names, Chosen direction into the Goal, Rejected options (with reasons) into `### Out-of-scope`, Criteria surfaced as acceptance-criteria candidates. The restatement still confirms each.

Every other skill the interview hands to or detours through: [`context/composition.md`](context/composition.md).

**Ask the quality bar in round 1.** When the request does not already state it, round 1 asks which bar the work is for: a throwaway prototype, an internal tool, or production. When the request states it, never re-ask it; treat it as settled. Grilling depth scales with the bar. A prototype gets the scoping questions only, with production concerns (accounts, scaling, monitoring, CI, coverage targets) named as deferred rather than asked. Production gets the full depth, including failure handling, data correctness, security, monitoring, and rollback; an internal tool sits between the two.

**Open with the problem when the request has none.** When the request names no problem (an idea, or a solution with no stated why), round 1's first question asks what problem it solves and why the user wants it solved; keep that answer in the user's words for the Goal's Intent line.

A new effort starts here, however big. When the interview shows the effort will outrun a single session AND is still too foggy to phrase as sharp questions, the user can't yet list the decisions, let alone lock them. Name `/planning:wayfind` to the user (it charts the fog as a decision map and works the frontier down decision by decision, graduating to a Brief once it clears); recommend, never auto-switch. The user can run it in this same session: its chart step reads this topic's ledger, so settled answers become decisions so far and open questions become decision items.

**Question budget scales with what's already settled.** Upstream artifacts, research findings, exploration output, a PRD, a design resolution, count as settled prerequisites: an interview invoked after them starts with a smaller tree and fewer rounds; never re-ask what an artifact already answers. There is no numeric question cap, but a frontier that keeps *ballooning* (each round opens more branches than it closes) is the wayfind signal above, not a license for a marathon session. Surface the routing recommendation instead of grinding on.

**Bulk application work is not a decision set. The interview settles it once, it never executes it.** When the task applies a settled shape across a corpus (every document in a set, every file matching a pattern, every page of a spec), the interview's output is TWO things and no more: the small set of genuinely contested decisions, driven to decisions the normal way, plus an **execution contract**. One line in the session's output artifact, routed by domain like every other output: the Brief's `### Acceptance criteria` in an engineering session, the shared-understanding summary in a general one. Naming the per-unit close-out loop (one source unit at a time: apply, verify, close) and what *closed* means for a unit. NEVER enumerate the per-unit applications as decision rows: an interview that becomes the execution container turns every application step into a decision needing its own adoption ceremony, and the corpus's size becomes the session's length. **Tripwire. Count the candidates against the corpus:** when the candidate question count scales with the number of source units rather than with the number of genuine forks, that is execution masquerading as decisions. Collapse the per-unit rows into the loop, keep only the forks, and say what you collapsed. Distinct from the ballooning frontier above and remedied differently: ballooning routes to `/planning:wayfind`, unit-scaling collapses into the execution contract and hands off to execution.

Tone is collaborative but opinionated. You are not interrogating; you are helping the user think out loud by PROPOSING answers grounded in codebase evidence. When the user gives a definitive answer, lock it. When they hesitate, slow down and offer two or three concrete shapes the answer could take. Every option set names exactly ONE recommended option marked **(RECOMMENDED)** with its basis (each fact with its source, then the one-line inference), except a withheld question (see "Recommended answers"), which is asked open with no recommended option. The surface follows the lane table above: inline prose rounds by default, the page or a shared session when that lane is chosen, and `AskUserQuestion` only in the terminal lane, when the user opted in and the round qualifies.

### Relentless mode (`me`)

Read [`context/relentless-mode.md`](context/relentless-mode.md) before the first round when the action resolves to `me`. It holds what relentless mode means and its canonical framing. The round mechanics below apply to every mode that asks questions.

**Ask each round inline as one numbered set.** Per-question shape within the round:

```text
Q<N>: **<one-line question>**
Context:
- <the problem this decision solves, in one or two sentences> (<link or file:line>)
- <what the source says or ships, paraphrased; label each part of an absorbed idea source or ours> (<link to its exact section>)
- <what exists today, and the gap> (<file:line>)
- <each term the question relies on, defined inline> (<its source, or its agreed terminology row>)

[Source: <the exact text the decision rests on, as a > quote>, <link to its exact section>, <one line on why that text makes this a question>. ONLY when the question rests on text the user has not read]

My recommendation: **<answer>**. <2-3 sentences: why it beats the alternatives>.
Checked against: <each constraint named in words, or none>
Basis: verified, <the Context sources this recommendation rests on>
Inference: <one line: why those facts together lead to this answer for this user>
Flips if: <the condition that would change it, a fact the user can confirm>
[Withheld: <the evidence that would settle it>. ONLY in place of the five parts above, for a question research could not settle]

[Commits you to: <ONLY when the recommendation fixes more than one decision; each part of it, numbered>
- Q<N+1>: <sub-decision>: <recommended value>, one bullet per part, numbered on from Q<N+1>]

Alternatives:
- (a) <option>. <what it gains>, but <what it costs> (<source>)
- (b) <option>. <what it gains>, but <what it costs> (<source>)
```

`Q<N>` numbering runs continuously across rounds (Q1…Q4 in round one, Q5… in round two; visible depth). Close the round with one probe inviting a constraint that breaks the recommendations, worded "something else", never "anything else": "Is there something else that would change these recommendations?" (eval case `interview-closing-probe-something-else`). Add the note that the user may answer in any order. Wait for the answers before computing the next round. The recommendation+basis discipline holds per question. Inline prose carries the recommendation, its reasoning, AND the probe in one readable block; a card cannot.

**One verdict marker.** The `My recommendation:` line is the *single* verdict marker for the question. Never stack a second one: no standalone `**(RECOMMENDED)**` badge line above it, and no `(recommended)` tag repeated in the Alternatives list; the recommended answer is named once, on that line. The alternatives exclude the recommendation: none restates it.

**Context first, as much as the decision needs and no more.** Every question opens with its `Context:` block, before `My recommendation:`, so the user can decide from that question alone without scrolling back or asking what something means; the round-header restate never stands in for it. The block holds what drives the decision: the problem, what the source says or ships (paraphrased, a quote under 15 words only where the exact words matter), what exists today and the gap, which parts of an absorbed idea come from the source and which are ours (labeled), and every term the question relies on, defined inline. If removing a line would not change how a reasonable person decides, remove it; long material goes behind a link. Write one claim per line, each with a link or `file:line` the user can open in one click (a URL with its section anchor, a video timestamp, a repo path); a claim the user stated cites `user, round <N>`, and a claim with no source is labeled `judgment`. `Basis:` keeps its job as the label: it names which of the Context sources the recommendation rests on, so the user sees at once whether it is grounded. Rules shared by every lane: [`context/question-shape.md`](context/question-shape.md) "Context". Eval case: `interview-context-unfamiliar-term-upstream`.

**Alternatives carry their tradeoffs.** One option per bullet, never a run-on sentence or a table: what it would gain, what it would cost, and the source behind that, so it can be weighed against the recommendation. When only one answer is viable, each alternative's line says why it is ruled out.

**Keep the layout whole.** With emoji markers on, the layout is `❓ Q<N>: **<title>**`, the Context block, `➡️ My recommendation:`, `Basis:`, then `Alternatives:` (the owner-approved shape); off, the same without the two markers. Keep a question's information in its own block: no separate index table or terms table at the top of the round, no per-question alternatives table, and no `---` rule between questions.

**No undecided name, scope or design shown as settled.** A name, scope or design the user has not agreed to appears only as a recommendation inside a question, never as a working assumption in prose, a restate, or another question's Context.

**Source first, when the user has not read it.** When a question rests on text the user has not read (a doc, a post, a repo file), add the `Source:` block after the Context block and before `My recommendation:`: that exact text as a `>` quote, a link to its exact section, and one line on why that text makes this a question. The Brief carries the link, not the quote.

**A recommendation that fixes more than one decision lists every part.** When the recommended answer also settles other decisions (a design that picks a platform, a runtime, a credential, an identity), list each under `Commits you to:` with its own `Q<N>`. They are parts of the one recommendation, not a second verdict, and each is registered `open` at ask-time like any question. An explicit acceptance of the headline ("Q5 yes", "accept all recommendations") resolves each listed part to its recommended value (on the page, only the parts the user ticks); the user can overturn one by its number. When an accept-shorthand resolves commitment rows, name their `Q<N>` ids in one line. Choosing an alternative or rejecting the headline withdraws the parts, and any sub-decision the chosen alternative implies is asked in the next round. A sub-decision the recommendation assumes but does not list is not decided by any answer to the headline: list it, or keep it out of the recommendation. A question with a `Commits you to:` block is never asked through an `AskUserQuestion` card; on the page, its parts are the question's `commits` entries. Row shape: [`context/loop.md`](context/loop.md) "Commitment rows".

**Emoji anchors (default off, still configurable).** Emoji markers: `${user_config.use_emoji_question_markers}` (unexpanded or empty means the default, off). With the emoji-markers setting on, prefix the `Q<N>:` line with `❓` and the `My recommendation:` line with `➡️`; with it off (the default), keep the undecorated shape above. Decoration of the existing single verdict marker, never a second one. Conversational rendering only: the ledger, register, and Brief stay plain, and `Q<N>` remains the answer handle. The option is the plugin's `use_emoji_question_markers` user config; set it true for anchors. A user instruction against emoji as formatting wins over the option: keep the plain shape, and the page start command then passes `--emoji-markers false` so the page matches.

**Agree the terms before the first decision.** Before the first decision question, build the ledger's `## Terminology matrix`: one row per term the rounds will rely on, with its definition, its source (`file:line`, URL, or `user, round <N>`) and its status, `proposed` or `agreed`. Show it to the user as the interview's first item, ahead of round 1's decision questions (the problem question may share its message), as one question registered like any other; it is never repeated at the top of a later round, where each question defines its terms inline. A later round that adds a term adds a `proposed` row and asks to agree it in that round. When the rounds rely on no term the user may not share, the matrix reads `none` and nothing is asked; a run that asks no decision question (`lock`, direct synthesis) builds none. A round uses no term missing from the agreed matrix and none left undefined in its own question. Row shape: [`context/loop.md`](context/loop.md) "Terminology matrix".

**Name every code; define every term where it is used.** In every line the user reads (rounds, restatements, recaps, the page, labels, reports), show the human-readable name, never a bare code. When the name is short enough to stand alone, show only the name (`scoped change`, not `C3`); pair code and name (`C3: scoped change`, `question Q14, retry budget`) only where the code itself must be quoted, such as a question id the user answers by. `Checked against:` names constraints in words; the ledger may keep bare ids. When a round leans on session-local shorthand, a coined label, an abbreviation, or cross-repo jargon the user may not share, record it in the ledger's shorthand glossary and define it inline in each question that uses it (`head SHA (the commit the PR points at)`), so a reader with none of the session's knowledge can answer from that question alone. Self-contained is not simplified: keep the precise technical terms and register, and expand a code to its real name, never a metaphor or lay substitute (`pr-merge lane`, not `merge robot`); simplify only when the user asks (`/education:explain`, if enabled). The glossary is ephemeral session vocabulary, distinct from the project's ubiquitous language (owned by `/domain-driven-design:curate-language`), and never touches a project glossary. Ledger shape: [`context/loop.md`](context/loop.md) "Session-shorthand glossary". Eval case: `interview-coded-terms-round-answerable`.

**Check the draft round for bare codes before it is shown.** In the terminal lane, write the drafted round to `<memory_dir>/<topic-slug>/round-<N>.md` (one file per round, kept: `/planning:audit-answers` reads each question's Context from it) and run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-round-codes.sh" --ledger <memory_dir>/<topic-slug>/interview-checklist.md <memory_dir>/<topic-slug>/round-<N>.md`. Exit 1 lists each `bare=<line>:<code>`: give each its name, save the file and run it again, so the kept file is the round as shown. Exit 2 (a missing file, an unterminated fence), or a session with no Bash to run it, is named in one line and the round still goes out. The page lane's wording lint covers the page ([`context/surface.md`](context/surface.md) "Wording lint").

**Partial-round resolution.** The user may answer any subset, in any order, in one reply. Unanswered questions stay OPEN on the frontier. Re-surface them at the top of the next round, labeled "unanswered from last round". NEVER silently resolve an unanswered question to its recommendation; the auto-guard applies inside rounds too. Honor accept-shorthands: "accept all recommendations" resolves the whole round to the recommended answers; "yes to Q5" / "Q5–Q7 yes" resolves that subset. Answers that reshape the tree ("actually, we don't need auth at all") invalidate pending questions. Recompute the frontier before re-asking anything.

**A restated open question keeps the whole contract.** Whenever an open question is shown again for an answer (unanswered from last round, a list after async input, a resume), it uses the identical layout: its Context, its recommendation with `Basis:`, and its alternatives. Never a condensed form, such as a table that keeps the recommendations and drops the basis and alternatives, unless the user asks for one or the summary covers answered items only. A one-line drift reminder that names open questions by id and plain name (below) is a pointer, not a restatement; asking any of them again uses the full layout.

**A hedged reply resolves only the headline.** A reply given with doubt ("yes?", "I think so", "probably") resolves at most the headline of the one question it can be tied to, never that question's `Commits you to:` rows and never the rest of the round. A hedged accept-shorthand ("accept all?") is not an accept-shorthand. Record the headline with a `hedged:` resolution, keep its commitment rows `open`, and echo back in one line what the headline commits to and which rows are still open. A hedged reply that cannot be tied to one question resolves nothing: restate the open rows.

**Register at ask-time; a reply that does not answer is not an answer.** The moment a round is asked, before any reply, write one `open` row per question into the ledger's open-question register. Then, after EVERY user reply and before doing anything else, check the reply against the register's `open` rows and restate any it did not address, in one line, even when the reply changed the subject entirely. Conversational drift is never consent, and the register, not the transcript, which a compaction can empty, is the authority. The one exception is the acceptance-criteria coverage prompt, which gets no row even inside a round while every real question beside it does ([`context/coverage-prompt.md`](context/coverage-prompt.md)). Row shape, statuses, and the drift-restate wording: [`context/loop.md`](context/loop.md) "The open-question register".

**Out-of-band output gets the same check, keyed on relevance.** A round can be overtaken by content the user did not write: a dispatched sub-agent's return, a background task notification, a team report, a Monitor firing. That is the ordinary consequence of not blocking the round. Check it against the `open` and `superseded-by-plan` rows (a superseded row is restated, never resolved by the return): a return touching nothing gets one line and the round stands, a return that contradicts an asked question's recommendation forces a restate naming the superseded recommendation, and a return that answers an open row from the environment resolves it. Re-present narrowly (a one-line pointer for the untouched, the full shape only for the row that moved), never hold the round, and never depend on being woken. The floor is the next user reply. Outcomes, shape, and the floor: [`context/loop.md`](context/loop.md) "Out-of-band drift".

**Rounds fire at phase boundaries.** When reached from inside another workflow's phase, emit the whole open set where the caller hands over, not partway through its phase; a mid-phase blocking question is the exception and states its justification in one line. Rationale: [`context/loop.md`](context/loop.md) "Where a round may fire".

**Visual-first for structural questions (default, not on-request).** When a question concerns structure, file/folder layout, before/after states, naming shapes, schema or flow alternatives, and a compact visual (fenced tree, diff, small table; roughly ≤30 lines) can carry it, LEAD with the visual and hang the question off it. A paragraph describing a tree is much harder to verify against the user's mental model than the tree itself; the visual IS the question. Before/after pairs beat single-state snapshots when the question is a migration. Skip only when no compact visual exists (genuinely abstract trade-offs) or when it would blow past ~30 lines. Then summarize and offer the full visual on request.

**Dialogue: the user drives too.** They may push back or reframe a decision (e.g. "what's hardest to roll back from?"). When they introduce a new axis, **reversibility** is the most common for V1, re-rank the options on it and REVISE your recommendation out loud, stated as old → new → why, where new may be a withheld open question ([re-emitting a changed recommendation](../../context/recommendation-basis.md)). The same holds when a recommendation changes after the user asks for context: re-ask the question in the full layout, its Context now carrying what they asked for, with the old and new recommendation and the reason. Default V1 lens: prefer the most *reversible* start; defer the irreversible/expensive as an explicit out-of-scope decision, never a silent assumption.

**Facts are yours; decisions are the user's.** A *fact*, a path, a current value, an existing pattern, what a file already does, is resolved from the environment (Grep/Read/Glob) and STATED, never asked; spending a question on what the code already answers is friction, not interview. Every candidate question first passes the self-answer step, [`${CLAUDE_PLUGIN_ROOT}/context/self-answer.md`](../../context/self-answer.md): codebase, ADRs, docs and history, then connected tools including MCP servers, then research for external facts. A fact it finds is stated with its `Basis:` and source tag and gets no register row (a contact address or identity still gets one: "Recommended answers"); a fact only an unconnected system holds gets one offer to connect it. Register mechanics: [`context/loop.md`](context/loop.md) "Self-answer gate". The environment is not only the working tree: when a task NAMES an external repo or resource, a sibling checkout under a known repo root / workspace layout, or an `owner/repo` reachable through its host, that is a resolvable fact too, so check the filesystem layout and query the repo host directly (e.g. `gh` for a named `owner/repo`) before defaulting to a user question. Cue, not mandate, except where a recommendation is consequential (next paragraph): there grounding is mandatory. Otherwise resolve what's cheaply resolvable, and don't turn every named mention into a research project; a recommendation of any kind still cites a fact, so a question the cheap lookup leaves with none is asked withheld ("Recommended answers"). A *decision* with real tradeoffs and no environment answer ALWAYS goes to the user; never resolve one on their behalf, however obvious the answer looks. **In-flight lookups.** A slow fact lookup (deep exploration, external research) runs in a sub-agent. Sort the frontier by one test, does this question need the lookup's result? A question that does is held for a later round; a question that does not is asked in this round, without waiting for the lookup.

**Ground before recommending.** Lightweight codebase gate per question (Grep/Read/Glob). If a recommendation needs more, external best-practice, a library API, deeper exploration, dispatch or do the lookup (research/exploration capability, or inline), then recommend grounded. No recommendation rests on training recall or convention alone ("Recommended answers"), and a **consequential** one (cross-repo, shared infrastructure, irreversible, or security) clears the higher bar: ground it in the affected code plus its consumers, and in external research that reads official docs first for a tool or API and the canonical source for a design pattern, never a pattern's popularity alone, and notes recency and dissent. That lookup is an in-flight lookup under the rule above. The contract this plugin ships, the bar and its three outcomes, is [`${CLAUDE_PLUGIN_ROOT}/context/recommendation-basis.md`](../../context/recommendation-basis.md).

**Before presenting an option that adds a mechanism** (a branch, workflow, ruleset, app, service, dependency or check), name the existing control that already covers the same risk, saying whether you read its enforcing source or only a document, and recommend dropping the mechanism if one does; a security control (`/overengineering:justify`'s protected classes) is never dropped without the user's decision, and an abstraction for a stated, known repetition stays when it passes the `reference-dont-duplicate` tests of the standards index (resolved per [`${CLAUDE_PLUGIN_ROOT}/reference/standards-contract.md`](../../reference/standards-contract.md) "Resolution ladder"). For a non-trivial new mechanism, run `/overengineering:justify` on the proposal if enabled.

### Recommended answers

For EVERY question but a withheld one (below), propose an answer grounded in observed evidence. User confirms (fast) or corrects (faster than explaining from scratch). **Every recommendation shows its evidence, never bare judgment.** Each fact the answer rests on sits in the question's Context block with its source (a `file:line`, a URL fetched this session, a session-transcript finding, or tool output); under each `My recommendation:` line, `Basis: verified` names which of those sources the answer rests on, then one `Inference:` line says why those facts together lead to this answer for this user. A `judgment` label alone is not a valid basis in this skill, for a consequential question or any other: the interview holds a stricter bar than the shared [basis contract](../../context/recommendation-basis.md), which still allows that label elsewhere. When only judgment is available, research first (the self-answer step, and "Ground before recommending" for a consequential question); when research leaves no fact to cite, ask the question withheld (below). Like `Checked against:`, the basis is part of the recommendation, not a second verdict marker and not part of the Context block; on a card the facts, the inference and the `Flips if:` line ride inside the option's basis text, and on the page the facts go in the question's `context` while the basis text names their sources and carries the inference and the `Flips if:` line, and the `Flips if:` line counts toward the basis prose's 3-sentence budget ([`context/surface.md`](context/surface.md) R12). Mark each recommendation once. In an inline round that marker IS the `My recommendation:` line (one verdict marker, never a second stacked badge); in an `AskUserQuestion` card it is the option tagged **(RECOMMENDED)**. Detail in [`context/loop.md`](context/loop.md) "Frontier rounds".

**State a reused value literally, with where it was read.** When a recommendation reuses an existing value (an email address, account, subscription, region, secret name, repository), the question states the literal value and its source (a `file:line`, tool output, or the connected system that holds it), for example "alerts go to `ops@example.com`, the `budgetContactEmail` in `Pulumi.production.yaml:12`". "The existing X" or "the same address as Y" alone is not allowed: an accepted round would then confirm a value the user never saw.

**Contact addresses and identities are owner-reserved facts.** An email address or other notification target, a login, or a user or service identity that anything will be created with or sent to is the user's to confirm, even when the environment holds a candidate; it is the exception to "Facts are yours" above. Propose the candidate you found as the recommendation, with its literal value and source, and register the question like any other. The row stays `open` until the user confirms that literal, so the register gate holds the contract and nothing is created with the value before then; an accept-shorthand confirms it only when the question showed the literal. In `lock` such a value is a gap: STOP and surface it; in `auto` direct synthesis it makes the path Mixed. Unattended, it is `blocked` with **arbiter: USER-RESERVED**, per [`context/loop.md`](context/loop.md) "Unattended path".

**Word each question so yes accepts the recommendation.** When the recommendation is negative, ask "Should X stay out of this change?", never "Should we do X?" answered "No", because "Q<N> yes" and "accept all" must both mean the recommended answer.

**A withheld question carries no recommendation marker.** Two questions are exceptions to "every question carries a recommendation", and their recommendation is **withheld**: a question research cannot settle (a recommendation with no fact to cite would be bare judgment, consequential or not), and, at the idea stage in the terminal lane, a question about why the user wants this or where it heads, since a proposed answer would put words in their mouth. It is asked open, never on a card, with a `Withheld:` line naming the evidence that would settle it in place of the `My recommendation:` line, its `Basis:` evidence list, its `Inference:` line and its `Flips if:` line; no option is tagged **(RECOMMENDED)**, and on the page its `recommendation` field carries the `Withheld:` text. It is registered like any question.

### Domain-aware behaviors

When the task touches domain concepts, these behaviors activate during Q&A. The probing behaviors run in any session; the two that write repo artifacts, **inline vocabulary update** and **ADR**, are engineering-only (per the Step 1 domain classification), so a general session, gated to a shared-understanding summary, never mutates a project glossary or proposes an ADR:

- **glossary challenge**. Two triggers share one response, a probe: any domain term the user uses two ways, and any term that collides with an existing definition
- **domain scenario exploration**. Test where one concept ends and the next begins with a concrete case of your own making ("a member returns one volume of a two-volume loan: is the loan open or closed?")
- **inline vocabulary update** *(engineering sessions only)*. When a term resolves, invoke
  `/domain-driven-design:curate-language` immediately (if that plugin is enabled; else
  record the term and its definition in the resolution field of the open-question register row that resolved it). That skill owns discovery-first
  placement, the consumer's
  file shape, purity, canonical terms, rejected synonyms, and known-context routing; the interview
  resumes after the update
- **ADR, behind the admission test** *(engineering sessions only)*. Propose an architecture decision record only for a decision that is **costly to undo** AND **not obvious from the code** AND **chosen over a live alternative**; most decisions fail one of the three and get none. When the `architecture` plugin is enabled, invoke `/architecture:record-decision` via the Skill tool, passing the decision and its rationale; it owns convention discovery, the no-convention offer-and-defer, and the write. Otherwise write to the repository's declared ADR convention (a managed `docs/adr/` README, a project rule, or an existing `docs/adr/` shape); if none is declared, offer and defer. Never prescribe a location or format

## Acceptance-criteria capture

Two behaviors ride on the moment acceptance criteria are captured; read both files then.

The coverage prompt is always on and asked once, writes no register row, and does not by itself bring the register gate into scope: [`context/coverage-prompt.md`](context/coverage-prompt.md).

EARS pattern tags apply only when the consuming team's convention selects them, through the `acceptance_criteria_format` resolution ladder, whose step-1 project root is `${CLAUDE_PROJECT_DIR}` (unexpanded or empty means unset): [`context/ears.md`](context/ears.md).

## The interview loop

Five steps. Step 1 (Survey) runs every action. Step 1.5 (Auto-detect) runs on `auto` only. Step 2 (Q&A loop) runs on `me` or `auto`-routed-to-Q&A. Detail in [`context/loop.md`](context/loop.md).

### Step 1. Survey before you ask

Spend the first turn grounding yourself. Read the project's `CLAUDE.md` / `AGENTS.md` if not already in context, Glob/Grep keywords, scan `git log --oneline -20`, climb to the nearest domain-vocabulary file, list relevant project rules, check the topic's memory slice `<memory_dir>/<topic-slug>/` (default `.work/`) for a prior PLAN.md / PRD / design artifacts and for exploration / research artifacts.

Survey output: one paragraph "Here is what I see in the repo."

**Classify the domain** from what the survey shows. *engineering* (a build or behavior-change task, or a technical subject that yields a build artifact) or *general* (a decision or idea with no build surface). The deciding signal is the **task/build surface itself**, not the working directory: a general decision raised from inside a code repo is still general, and the engineering machinery must never engage on cwd alone. Repo/cwd is context that breaks the tie only when the task surface is genuinely indeterminate. Then lean engineering inside a code repo, else general. This is inferred, never asked; honor any explicit user override. The domain governs which machinery engages and what the session produces (see Purpose "Domain-routed"); it is orthogonal to the `me`/`auto`/`lock` action.

**Engineering sessions only**. If a prior PLAN.md Brief exists, ask whether to **resume**, **revise**, or **start fresh** (the latter appends a dated scope-change note to the top of the Brief capturing why before rewriting. The Brief is never committed, so that note is its only history; the copy published to the pull request body or the linked issue carries it). On **resume**, before the first resumed round, resolve the surface through `${CLAUDE_PLUGIN_ROOT}` again (never an absolute path copied from a handoff) and run `round.sh --dir '<memory_dir>/<topic-slug>/interview-surface' doctor --ledger <ledger>`; it names each element the running version needs and the ledger lacks. A general session or the `scope` action never creates or edits a PLAN.md Brief, so it skips this prompt.

Then route per action.

### Step 1.5. Auto-detect (default action only)

For `auto`: classify intent against `context/loop.md` "Step 1.5. Auto-detect" criteria. Three outcomes:

- **Synthesize directly** (clear) → skip Step 2; proceed to Step 3 (confirmation gate), then Step 4 (Persist)
- **Q&A loop** (fuzzy) → continue to Step 2
- **Mixed** → ask the residue (one round. The few open questions together), then synthesize; proceed to Step 3, then Step 4

**Auto-guard. Never decide an interactive choice for the user.** Synthesize-directly (and the Mixed path's "synthesize the rest") applies ONLY to decisions with a verifiable answer (codebase-resolvable) or an unambiguous conventional default. When a remaining decision is genuinely the user's, a design choice with real tradeoffs and no codebase answer, do NOT fold it into the Brief. STOP and either ask it inline (a residue round) or offer to switch: *"This is a real design decision, not mine to pick. Answer it, or want me to run `/planning:interview me` and drive every open branch to a decision?"* Silently capturing such a choice as an assumption is the failure mode this guard prevents.

**Unattended path: the guard holds, the run does not idle.** `/planning:interview` can be reached with no human to answer (a loop, a spawned worker, another skill's chain). The condition is **declared by the caller, never sniffed**. There is no supported way for a session to observe that it is non-interactive. Unattended, codebase-resolvable and unambiguous-conventional decisions resolve as usual and are recorded `auto-resolved (unattended)`; a decision genuinely the user's is recorded `blocked` in the register, written to the Brief's `### Deferred questions` with **arbiter: USER-RESERVED**, and named as a blocker in the output. That extends the auto-guard rather than excepting it. The guard forbids the choice *disappearing*, and a named blocker is the choice made maximally visible. Stop on blockers; never wait indefinitely, and never read absence of objection as confirmation. Full ladder: [`context/loop.md`](context/loop.md) "Unattended path".

For `me` / `me <topic>`: skip Step 1.5 except loop.md's "Problem first" paragraph, force Q&A.
For `scope` / `scope <topic>`: skip Step 1.5 except loop.md's "Problem first" paragraph; with no topic, scope the current task. Run Step 2–3, then the **`scope` persist path** below instead of the engineering Brief in Step 4. Do not offer `/planning:plan` handoff; stop after returning decisions.
For `lock`: skip Step 1.5 AND Step 2, synthesize directly. If a gap surfaces mid-synthesis, STOP and surface; do not fudge.

### Step 2. Drive the frontier-rounds loop

Run rounds: restate working understanding → compute the frontier (every open question whose prerequisites are settled) → ask the whole frontier as one numbered set → capture the answers → recompute. Categorize each open item as resolvable / blocked / defer-with-assumption / defer-fully. The restate is also the **session-hop anchor**: after a handoff, resume, or long gap it re-establishes the decided set and this round's stakes before any question, so a returning reader is grounded without re-reading the whole ledger.

Full surfacing-question taxonomy + categorization heuristics in [`context/loop.md`](context/loop.md).

On the page surface, Step 3's confirmation gate runs on the page: post the restatement with a `restate` op and wait for the user's `confirm-understanding` event, per [`context/surface.md`](context/surface.md) "Confirmation gate".

**`me` mode** maintains a **decision-tree ledger**. One live checkbox per branch, ticked on resolve, remaining-open surfaced periodically (not every turn. Keeps the flow clean like the inline format). Persist each answer the moment it locks in (Step 4), loop until zero open consequential branches. Ask via the inline format (Stance "Relentless mode"). Ledger shape + per-round mechanics + reversibility-lens question shape in [`context/loop.md`](context/loop.md) "Decision-tree ledger".

**Keep a running constraint ledger.** The ledger's `## Constraint ledger` section holds one row per constraint. Every constraint the user states is written at once as `confirmed`, the moment it is stated, never batched to Step 4; a constraint taken from an upstream artifact is `inherited` (a prior Brief, a PRD, a design resolution). Every recommendation names the constraints it was checked against on one line under `My recommendation:`, in words, `Checked against: V1 ships without SSO; no new runtime dependencies` or `Checked against: none`; the ledger's `C<N>` ids stay in the ledger. That line is part of the recommendation, not a second verdict marker and not part of the Context block. On the page it opens the question's `facts` field, each constraint named in words, since the page's wording lint flags a bare `C<N>` ([`context/surface.md`](context/surface.md) "Wording lint"). A card has no recommendation line, so a question goes on an `AskUserQuestion` card only when its line would read `Checked against: none`; one that cites a constraint is asked in prose. An `inherited` constraint the contract relies on is asked as a register row at ask-time: the answer flips its tag to `confirmed`, and unattended it takes the ladder (`blocked`, USER-RESERVED, when it is the user's call). In `lock` a relied-on inherited constraint is a gap: STOP and surface it (Step 1.5); in `auto` direct synthesis it makes the path Mixed and is asked in the residue round. Row shape: [`context/loop.md`](context/loop.md) "Constraint ledger".

**Re-ground open recommendations before they are shown.** On resume, and before a queued round is shown, check each open recommendation: its `Basis:` cites a source read this session or a constraint row, and it does not rest on an artifact the constraint ledger now excludes. A consequential one that fails gets a research dispatch before the user sees it, or is shown marked "not yet researched". When the user adds a constraint mid-interview, write the `confirmed` row at once and re-check every open recommendation's `Checked against:` line against it; revise the ones it changes and say which.

**Check each draft round against earlier answers before it is shown.** Every round after the first, before it is asked inline or posted with `add-round`, gets a contradiction pass: a fresh-context non-fork sub-agent runs only the assumption sweep's contradiction category over the draft round and the register's `answered` rows ([`context/assumption-sweep.md`](context/assumption-sweep.md) "Pre-round contradiction pass"). Fix each contradiction in the draft before the round goes out: revise the recommendation so it holds with the earlier answer or constraint, or, for an earlier answer, ask one question that names both sides. A question that weighs earlier answers, whether it comes from this pass or the sweep, lists their `Q<N>` ids as the answers it reconciles; a round of sweep items is labeled a sweep round, per that file's "Disposition".

**Composed artifacts are candidates.** A design from explore or research output, or read from an existing implementation, is a candidate, never a recommendation, until re-derived against the constraint ledger: check it against every row, recommend only what survives, and name the rows on its `Checked against:` line. A research or exploration brief dispatched mid-interview carries the constraint ledger verbatim.

**Label evidence by when it was true.** When a recommendation rests on historical evidence (past metrics, merged PRs, an existing implementation) and the survey finds a recent process change or cannot tell, label each finding `past`, `current`, or `intended` before a recommendation rests on it. A process change is one the survey finds (a changelog, commit, ticket, or user statement dated after the evidence window) or cannot rule out. State or ask any currency you cannot establish; past-only evidence never alone grounds a recommendation.

**What, not how: the mechanism tripwire.** "Does not plan implementation" has a trigger. When a question or its recommendation names a mechanism (a tool, an API, a credential or token scope, a runtime, a platform per step), ask once whether the user wants mechanism-level decisions settled now or at planning. Ask it in the same round as the first mechanism-naming question and register it like any other question; until it is answered, recommendations carry no mechanism part. When the answer is "at planning", no later recommendation fixes a mechanism, and every still-`open` mechanism row, commitment rows included, becomes `deferred`: carried to the Brief's `### Deferred questions` under the arbiter rule in an engineering session, listed as deferred in the shared-understanding summary in a general one. When the answer is "now", write `C<N> | confirmed | mechanism decisions settled in this interview | user, round <N>` at once, and the Brief's Constraints records that this topic overrides "does not plan implementation".

**Sweep for assumptions before Step 3.** In `me` and `auto` with a register, including the `auto` Mixed path after its residue round, the loop ends with a fresh-context assumption sweep. Once no open question remains on the frontier, and before the Step 3 register gate and confirmation gate, dispatch a non-fork sub-agent to inventory undecided details, hidden defaults, contradictions, and hedged or free-text rows across the ledger, the recommendations, and any composed artifacts. You turn each item into a register row at the next contiguous `Q<N>`, a stated fact, or, for hedged rows, a line in the confirmation restate. Any `open` row it adds returns the run to Step 2, and the next sweep covers only what the new answers changed; Step 3 is reached when a sweep adds no `open` row. A run that asked no question skips it, and so does `lock`; unattended, an item that is the user's decision is `blocked`. The acceptance-criteria coverage prompt is never a sweep item ([`context/coverage-prompt.md`](context/coverage-prompt.md)). Scope, item shape, and disposition: [`context/assumption-sweep.md`](context/assumption-sweep.md).

### Step 3. Recognize the stop condition

Stop when no question is left to ask. Every unknown the task depends on resolved OR captured as named assumption. The user can describe the goal in one paragraph without contradicting the constraints, and acceptance criteria are testable. The coverage prompt has been asked once and answered ("neither applies" counts), or skipped and reported unexamined per [`context/coverage-prompt.md`](context/coverage-prompt.md). Don't stop early on impatience; don't keep asking past the stop condition.

**Register gate.** Before persisting the contract or handing off, run the register through its mechanical check. That no question is left to ask is a judgment, and this is the part of it a script can decide. **Ledger only here**: the Brief does not exist yet (Step 4 writes it), and `--brief` names a file it requires to be present.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-open-questions.sh" \
  --ledger <memory_dir>/<topic-slug>/interview-checklist.md
```

Exit 1 (a row is `open` or `superseded-by-plan`) and exit 2 (ungradeable) both HALT. Resolve or explicitly retire an `open` row and re-run; a `superseded-by-plan` row leaves only on the user's reply to it ([`context/loop.md`](context/loop.md) "Superseded by plan"). Never lock a contract over a non-zero exit; that is the reported failure restated. **A run that asked no question wrote no register, has nothing to gate, and skips this**: `auto` routing to synthesize-directly with no open decision. `lock` always writes its problem row, so its register gates. The carve-out is about the absence of questions, never about which action produced it: the moment ANY question exists. Asked, surfaced mid-synthesis, or blocked unattended. A register exists and the gate applies. The `--brief` cross-check runs in Step 4, once there is a Brief to cross-check against; it also exits 1 with `brief=unconfirmed` while the Brief is stamped `Restatement: UNCONFIRMED`. The gate reads only that stamp, so it cannot see a Brief edited after a Confirm: after such an edit, post a new `restate`, get a fresh Confirm and export again.

**The acceptance-criteria coverage prompt is not a question for this purpose**: it writes no register row and does not by itself bring this gate into scope, and no other question, whether asked beside it or later in the session, shares that exemption ([`context/coverage-prompt.md`](context/coverage-prompt.md)).

**Confirmation gate (`me` and `auto`):** that no question is left to ask does not end the interview on its own. Before persisting the contract or handing off, restate the shared understanding, opening with the one-line problem, and get the user's explicit confirmation that it is reached. Do not act on the interview's output until they confirm. `lock` confirms the problem with one question, registered like any row; its invocation confirms the rest (its STOP-on-gap rule still applies).

**Recap and procedure check (`me` and `auto`).** Before asking for confirmation, the restatement carries a Q&A recap: one line per `Q<N>` in the ledger's `## Open-question register`, shaped `Q<N> <status>: <question text> (<resolution>)`, generated from the register on disk, never from the transcript, so it survives a compaction. Generate it with `bash "${CLAUDE_PLUGIN_ROOT}/surface/round.sh" export-ledger --recap --ledger <memory_dir>/<topic-slug>/interview-checklist.md --out <memory_dir>/<topic-slug>/recap.md`, which reads the ledger alone, so the terminal lane, with no page data, passes no `--dir`. Paste the contents of `recap.md` verbatim in place of a recap of your own: no paraphrased or hand-shortened line, and no HTML or collapsible block, which the terminal shows as raw tags. Each recap saves its rows beside the ledger (`interview-checklist.last-recap.json`, overwritten each time). After the first confirmation, add `--changed`: the recap then lists only the rows changed since the last recap, plus one line counting the rest by status. The page lane's `restate` keeps the full recap ([`context/surface.md`](context/surface.md) "Confirmation gate"). **When every answer was accepted as recommended or confirmed after its read-back** ([`context/loop.md`](context/loop.md) "Drift check"), save a recap with the command above once each round's read-backs are confirmed, without pasting it, so the first confirmation pastes the `--changed` recap too: it lists only the answers changed since, with one line counting the rest. The restatement adds the intent, each `hedged:` row ([`context/loop.md`](context/loop.md) "Hedged flag") and each stated assumption the user has not yet seen, and does not re-list the unchanged accepted answers (eval evidence: `interview-final-brief-changes-only`). Then run the procedure check beside the register gate, ledger only, and cite its exit code and `procedure=` field as the evidence that the procedure ran, never your own account of it:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-open-questions.sh" \
  --ledger <memory_dir>/<topic-slug>/interview-checklist.md --procedure
```

A non-zero exit HALTS the confirmation request; stderr names each defect (a round missing from the register, a retired row with no resolution). Fix the ledger and re-run. One exception, on the page surface only: an exit 1 whose only `open` rows are accepted questions held open by unticked commitments (the rows `round.sh status` lists on `accepted, to confirm:` lines) lets the restate go out, because the page offers those ticks inside the restatement box ([`context/surface.md`](context/surface.md) "Confirmation gate"). Any other defect still halts it, and the Step 3 register gate still holds those rows until they are ticked. It checks only what a file can show. Not checked, and not implied by a green exit or by the recap: whether the Step 1 survey grounded the questions, whether the domain was classified, whether register rows were written at ask-time rather than answer-time, and whether the frontier was recomputed between rounds. `/planning:audit-answers` adversarially re-validates the answers; the recap shows the user the Q&A and the check shows the procedure ran, and neither composes nor duplicates it. A run with no register skips both.

**Close the restatement with an active request.** In the terminal lane, the restatement ends by asking the user to confirm it or to name the `Q<N>` numbers of the items to change, for example "Confirm this, or name the Q numbers to change." A run with no register asks the user to confirm it or say what to change. Never close on a yes/no check ("Sound good?", "Does this look right?"). When the recap command or the procedure check cannot be run (no Bash in the session), the restatement still goes out with that gap named in one line and no hand-written recap in its place; it is never replaced by setup questions or a request to run them. A check that ran and exited non-zero still halts, as above. Eval evidence: case `interview-final-confirm-active-reply`.

**`me` mode tightening:** "captured as named assumption" is NOT a valid stop for a *consequential* branch. Drive it to a decision (a decision MAY be "defer to post-V1", but it must be explicit and surfaced, never silent). The stop condition is an **empty decision-tree ledger** plus the confirmation gate. Not a question count.

### Step 4. Persist the contract

Derive `<topic-slug>` from the task or current branch name (kebab-case, ≤40 chars, shared with `/planning:prd`, `/planning:design`, `/planning:plan`). The contract (`PLAN.md`) and the working ledgers land in the memory slice `<memory_dir>/<topic-slug>/` (default `.work/`), per the lifecycle artifact protocol [`${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md`](${CLAUDE_PLUGIN_ROOT}/reference/artifact-protocol.md). *What* gets persisted follows the Step 1 domain classification.

**The memory slice is not a durable home.** It self-ignores and never reaches git, so it is lost with the checkout. Durable outcomes go to the pull request body or the linked issue: a decision that passes the ADR admission test also becomes an ADR, and a follow-up becomes a tracker item. That close-out belongs to `/planning:plan`. So when the user asks where to keep something past this branch, never offer the memory slice: name the destination (the PR body, the linked issue, an ADR, or a tracker item), and the slice holds the Brief only until it is published there.

**General (non-engineering) sessions** persist a shared-understanding summary, the decisions reached and their rationale, to the memory slice (nothing downstream enforces against it), or inline when the user wants no artifact. NEVER create or edit a PLAN.md Brief for a general decision: the `## Brief`/`## Plan` structure is the engineering shape. In `me` mode, the continuation discipline below still applies, with the summary standing in for the Brief.

**Engineering sessions** write the Brief section into `<memory_dir>/<topic-slug>/PLAN.md` (default `.work/`) as it locks, **except `scope` action**, which never writes `PLAN.md` (see below). The rest of this step, everything below, is the Brief machinery and is engineering-only.

**`scope` action (ad hoc, no Brief).** When the action is `scope`, do **not** create or edit
`PLAN.md` in the memory slice. After the Step 3 register gate passes, emit a **`Scope decisions:`**
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

**`me` mode persists incrementally, not just at the end.** Lock each answer into the decision-tree ledger (`interview-checklist.md`) + the relevant PLAN.md Brief section the moment it resolves, except in **`scope` action**, which never writes PLAN.md sections. So a crash, context clear, or overflow never loses resolved branches, and the session can continue elsewhere at any round boundary with nothing left to flush. Recommend routing the next step with `/session-flow:workflow` (if installed; otherwise Step 5's fallback) when the user or the harness signals it, or when branches keep opening faster than they close (Step 5); never on your own estimate of remaining context. Target the light V1-spec Brief shape (scope / schema / code-surface bullets). Keep it terse.

PLAN.md holds `## Brief` + `## Plan` sections. `/planning:interview` writes only the Brief section; the Plan section stays empty until `/planning:plan` fills it.

**Cross-check the Brief once it exists.** Immediately after writing it, re-run the register gate with `--procedure --brief <memory_dir>/<topic-slug>/PLAN.md`, plus `--surface '<data_dir>'` on a page-surface run, which checks the Brief against the page's export ([`context/surface.md`](context/surface.md) "Wrap-up" lists what it fails). This run proves every `deferred` and `blocked` row actually reached `### Deferred questions`, and that the Brief carries all nine template headings (TLDR, Problem, Goal, Work size, Constraints, Acceptance criteria, Captured assumptions, Out-of-scope, Deferred questions); the Step 3 run could not check either because the file was not written yet. It matches on the `Q<N>` id, so each deferred entry must lead with one. A non-zero exit means the Brief is missing a question the ledger retired or a template heading: fix the Brief, do not retire the row. Exit 1 with `brief=unconfirmed` means the Brief is stamped `Restatement: UNCONFIRMED`: the user confirms the latest `restate`, then the Brief is exported again. The gate reads only the stamp and cannot see a Brief edited after a Confirm; after such an edit, post a new `restate`, get a fresh Confirm and export again. A general session writes no Brief and skips this.

If a PLAN.md Brief exists and user chose **revise**, edit the Brief in-place. If **start fresh**, append a dated scope-change note to the top of the Brief capturing why before rewriting. Never silently overwrite: that note is the Brief's only history (Step 1).

Section schema: write the literal `## Brief` template (TLDR / Problem / Goal / Work size / Constraints / Acceptance criteria / Captured assumptions / Out-of-scope / Deferred questions) per [`context/loop.md`](context/loop.md) "Brief template (the literal shape)"; Problem and Work size follow [`../../context/problem-framing.md`](../../context/problem-framing.md). `### Acceptance criteria` stays plain bullets in both formats, tagged or not, per [`context/ears.md`](context/ears.md); it is never converted to checkboxes. Each **Deferred question** leads with its **`Q<N>` id**, the tie back to its register row and what the Step 4 gate greps this section for, and carries an **arbiter tag** (`/planning:plan` default, or `USER-RESERVED` when its resolution could change acceptance criteria / out-of-scope / constraints). Both are required; loop.md covers when to use which.

### Step 5. Hand off

Route the handoff by what the session produced. Do NOT auto-clear or auto-invoke. Recommend; let the user pull the trigger. Read [`context/handoff.md`](context/handoff.md) at the stop boundary, before recommending: it owns the route for a mid-flow arrival, a general session, an engineering Brief by task shape, a question only another person can answer, and an interview that outgrew the session.

## Page surface exit codes

`round.sh` exits 0 when done, 1 when refused (the message names the cause), 2 when a prerequisite is missing (Python 3, or curl for `ensure-running`), 5 when `ensure-running` started the page server but it did not answer, and 6 when `export-ledger --diff` or `ledger-check` finds the page and the ledger disagree, or a ledger merge kept a conflicting row. `watch.sh` exits 2 too when curl is missing. Exit 2 or 5 from `ensure-running` takes the degrade; on exit 6, reconcile the rows it prints and carry on. `round.sh --help` lists the codes, and [`context/surface.md`](context/surface.md) "Start and stop" covers the watcher's own codes and the recovery for each.

## Session-config recommendation (model, effort, advisor)

Turn the interview's read of complexity and ambiguity into a recommendation for how the session carrying the work forward should be configured. *When* it lands follows from *what* it configures: an engineering interview recommends at the stop/handoff boundary, for the downstream execution session; a terminal interview (a general decision, per Step 5) recommends at the early post-survey surface and again at the stop boundary, for the current session.

Read [`context/session-config.md`](context/session-config.md) at that boundary, before forming the recommendation: it owns the two orthogonal knobs and their picking signals, the advisor pairing, the rule that current model and effort names are fetched live and never pinned (and that a failed fetch degrades rather than halts), the advisory framing, and the per-surface wording. Do not form the recommendation from this summary.

## Routing by size and fog

Read [`context/routing.md`](context/routing.md) at entry and at every round boundary. It owns why the entry gate is diff size and retry cost, the bigger-than-you-thought check that recommends `/planning:wayfind chart` on fog or `/session-flow:workflow` on context size alone, what the wayfind handoff carries, and the "this is small, ship it" exit with the gates it still runs.

## What this skill does NOT do

- `context/gotchas.md`. Failure patterns from real sessions

- **Does not deep-dive the codebase**. Step 1 is a fast survey; the codebase gate in Step 2 is a lightweight per-question check (Grep/Read/Glob). Neither is exploration-depth work. If exploration grows beyond quick lookups, stop and recommend the exploration capability
- **Does not plan implementation**. The Brief says *what* and *what we are assuming*; `/planning:plan` says *how*. Resist drafting an approach mid-interview
- **Does not write code or run tests**. Discovery skill. In an engineering session it DOES write domain docs outside the topic's slices when the project keeps them: domain-vocabulary updates (inline, between questions) and ADRs (written through `/architecture:record-decision` when that plugin is enabled, else by hand into the declared convention) are first-class interview outputs alongside the Brief (a general session writes none)
- **Does not adversarially attack the user's idea**, except in the `product` action, where the user asked for the idea to be tested ([`context/product.md`](context/product.md)). That is `/planning:devils-advocate`. Domain scenario exploration (probing concept boundaries through invented edge cases) discovers domain semantics. It is not plan-attacking. If you find yourself wanting to push back on the goal itself, surface once, capture response, continue
- **Does not gate a quick change**. A change whose diff is quick to review and cheap to retry skips `/planning:interview`: build it, review the diff, and align on it there (the quick-change on-ramp of `/session-flow:workflow`). Behavior change alone does not force the interview. Work that fails either test, or whose diff turns out not to be quick to review, is **interview-first**, and auto-detect keeps that cheap (synthesize-on-clear, relentless-Q&A-on-fuzzy)
- **Does not fudge gaps in `lock` mode**. If a true unknown surfaces during synthesis, STOP and surface it. Fall back to `auto` or `me` instead of guessing
- **Does not export Gherkin**. Named as a deferred extension point so its absence reads as a decision rather than an oversight: nothing here emits `.feature` files or `Given`/`When`/`Then` scenarios, and the EARS tags are a bracketed prefix vocabulary on a plain bullet, not a step grammar. A Gherkin export is a separate slice against a separate contract, and none of it is built here

## Next

- Contract locked: /planning:design, which records a one-line early exit when no design question is open.
- Quickly accepted answers want a fresh-context check: /planning:audit-answers.
- The interview outgrew one session and the effort is still foggy: /planning:wayfind chart.
- Unsure where this leaves the work, or arrived mid-flow: /session-flow:workflow.

## Spoke paths

The `context/` files write the plugin's root directory as `<plugin-root>`, which is
`${CLAUDE_PLUGIN_ROOT}`. Put that path in place of the placeholder before running a command or
writing it into a brief. Those files arrive through the Read tool as plain bytes, so a `${…}` token
in them would reach the Bash tool unsubstituted, and the Bash tool's environment has no
`CLAUDE_PLUGIN_ROOT` to expand it from. Basis: the plugins reference,
<https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves>, verified
2026-10-07; recheck when that table adds supporting files to where a `${…}` reference resolves.

Two spokes own the acceptance-criteria rules: [`context/coverage-prompt.md`](context/coverage-prompt.md) holds the coverage prompt and its register exemption, and [`context/ears.md`](context/ears.md) holds the EARS tags and how `acceptance_criteria_format` resolves, through the shared ladder in [`${CLAUDE_PLUGIN_ROOT}/context/authoring-formats.md`](../../context/authoring-formats.md).

## Composition with other skills

Every skill this interview hands to, detours through, or receives from, and the mid-interview detour rule: [`context/composition.md`](context/composition.md).
