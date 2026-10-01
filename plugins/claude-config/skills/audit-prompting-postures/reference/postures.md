# Posture catalog

Fourteen postures. Each row: the applicability predicate (which component purposes it binds), what
counts as present, and the guide pointer that owns the recommended wording. Pointers only.
Wording is fetched live per SKILL.md Phase A; the recheck trigger for every row is a change to its
cited section.

Guide root: <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices>
(sections cited by heading). Model subpages cited by page + heading where a row needs one.

Rows cite the subpages of the current models first. A subpage name in a row means:

- "Fable 5.1 subpage":
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1>
- "Opus 5.5 subpage":
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5>
- "Sonnet 5.5 subpage":
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5>
- "Fable 5 subpage":
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5>
  (P5 only; see that row).
- "Opus 5 subpage" and "Opus 4.8 subpage":
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5>
  and
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-4-8>.
  We keep them in P1 while Claude Code can still put a session on either model. Pointer: for the
  models a session can fall back to, see
  [model configuration: automatic model fallback](https://code.claude.com/docs/en/model-config#automatic-model-fallback).
  As of: 2026-10-01. Recheck trigger: either model leaves Claude Code's model page.

- **Pointer**: for which model each subpage covers, see the
  [model-specific guidance table](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices#model-specific-guidance).
- **As of**: 2026-10-01 (each subpage read as raw markdown that day).
- **Recheck trigger**: a row's cited heading disappears from its subpage, or that table gains or
  drops a row.

A row's "correlate:" note names a heading in the Opus 5.5 usage guide
(correlate with <https://claude.dev/blog/getting-the-most-out-of-opus-5-5/>, published 2026-09-22),
a vendor blog that is never the pointer; the Opus 5.5 subpage sections linked below are. Both are
fetched lazily, like the other subpages. We treat the behaviors the Opus 5.5 rows check (named
stops, a finish line, a task file, a report that leads with what the human owes) as model-neutral,
so proposals citing them carry no model condition.

- **Pointer**: the Opus 5.5 subpage's
  [capabilities relevant to prompting](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#capability-improvements)
  (the rendered page gives this heading the id `capability-improvements`) and
  [unattended agentic runs](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#unattended-agentic-runs).
- **As of**: 2026-09-23 (our probe: the subpage's raw `.md`, 28,311 bytes; no artifact stored).
  Both anchors re-matched against the rendered page on 2026-10-01.
- **Recheck trigger**: a cited heading disappears from either page.

The Sonnet 5.5 subpage backs P2, P6, P8, P12, P13 and P14. We treat P13 and P14 as model-neutral,
so their proposals carry no model condition. P12 is the one model-conditional row: its proposal
carries the Sonnet 5.5 condition.

- **Pointer**: the Sonnet 5.5 subpage's
  [steer initiative and scope](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#steer-initiative-and-scope)
  (P2, P6, P12, P14),
  [mid-turn user messages](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#mid-turn-user-messages-and-task-budgets)
  (P8) and
  [verification on coding tasks](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#verification-on-coding-tasks)
  (P13).
- **As of**: 2026-10-01
- **Recheck trigger**: a cited heading disappears from that subpage, or another model's subpage
  covers self-started review rounds, which re-opens P12's model condition.

A row that names the "Sonnet 5.5 subpage" means
<https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5>.
It is fetched lazily, like the other subpages. The behaviors its cited headings address (a stop
rule that names when to ask, scope held to the request, a real check before "done") are
model-neutral, so proposals citing it carry no model condition. Verified 2026-10-01 against the
subpage's raw `.md` (27,412 bytes); recheck when a cited heading disappears.

## Purpose classification vocabulary

Classify each component by what its body has the model DO (multiple or none):

- **orchestrating**: spawns or coordinates subagents/workers/teams
- **code-changing**: edits code, implements, refactors, fixes
- **codebase-answering**: answers questions about existing code
- **long-running**: states or invites autonomous/unattended/multi-hour operation
- **destructive-capable**: the body has the model delete, reset, force-push, publish, or mutate
  shared state, or instructs it to. Read this as this section's opening line says: what the body
  has the model DO, not what a tool grant would make possible. A component that merely holds Bash
  access is not `destructive-capable`; if it were, this predicate would match everything with a
  shell and P7 would fire on all of it
- **context-surfacing**: displays token budgets, context occupancy, or remaining-window figures
- **multi-window**: spans sessions/windows via saved state, handoffs, or resumability
- **parallelism-steering**: instructs when/how to parallelize tool calls
- **user-gated**: interactive flow with genuine decision gates only the user can answer
- **ideating**: the body's deliverable is a set of proposals for the user to choose from, not the
  built thing

## Postures

### P1: Delegation criteria and caps

- **Predicate:** orchestrating.
- **Present when:** the component states when delegation is and is not warranted, or caps
  spawn/concurrency deterministically. Either satisfies. A component that fans out an audit,
  migration, or review across many files also has the orchestrator check each worker's evidence
  before accepting it and consolidate the results into one table.
- **Pointer:** main page, "Subagent orchestration"; Opus 5 subpage, "Controlling subagent
  spawning"; Opus 4.8 subpage, "Controlling subagent spawning"; Opus 5.5 subpage, "Capabilities
  relevant to prompting" (audits and migrations run with parallel subagents); correlate: Opus 5.5
  usage guide, "Ask it to split big work across subagents".

### P2: Minimal-scope guardrail

- **Predicate:** code-changing.
- **Present when:** the component bounds scope to what was asked (no unrequested features,
  abstractions, defensive code, or cleanup beyond the task).
- **Pointer:** main page,
  [Overeagerness](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices#overeagerness);
  Fable 5.1 subpage,
  [Keep changes and tests to what the task asks for](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#keep-changes-and-tests-to-what-the-task-asks-for);
  Sonnet 5.5 subpage,
  [Steer initiative and scope](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#steer-initiative-and-scope)
  (unrequested additions).

### P3: Anti-test-gaming guardrail

- **Predicate:** code-changing AND the flow involves making tests pass.
- **Present when:** the component states that the fix targets production code and general
  correctness, not the test's assertion or the specific test inputs.
- **Pointer:** main page, "Avoid focusing on passing tests and hardcoding".

### P4: Investigate-before-answering grounding

- **Predicate:** codebase-answering.
- **Present when:** the component requires reading the referenced code before claiming anything
  about it.
- **Pointer:** main page, "Minimizing hallucinations in agentic coding".

### P5: Progress-claim grounding

- **Predicate:** long-running.
- **Present when:** the component ties progress/status claims to tool-result evidence and requires
  naming unverified work as unverified.
- **Pointer:** Fable 5 subpage,
  [Ground progress claims during long runs](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5#ground-progress-claims-during-long-runs).
  On 2026-10-01 that was the only docs section covering this check: we read the Fable 5.1, Opus 5.5
  and Sonnet 5.5 subpages that day (raw markdown, no artifact stored) and none of them covers tying
  progress claims to tool-result evidence. As of: 2026-10-01. Recheck trigger: a current model's
  subpage starts covering the check (repoint there), or that Fable 5 section disappears.

### P6: Autonomy or checkpoint posture

- **Predicate:** long-running (autonomy posture) or user-gated (checkpoint posture). A
  report-only flow ending at a human gate is NOT-APPLICABLE (see SKILL.md Gotchas). A project
  CLAUDE.md or natively read AGENTS.md is long-running when the repo carries long-running
  components or its own text invites long runs.
- **Present when:** an autonomous component states its finish line (what "done" observably is, or
  that the dispatching brief must state it) and names both kinds of stop: keep going when a step
  needs no input, with status notes in the same message as the next action rather than a closing
  summary naming the next step, a question asking whether to proceed, or a menu of choices that
  block nothing; stop and ask
  only when nothing can move without the human, or before a destructive, hard-to-undo, or outward
  action. The keep-going half never licenses turning permission prompts or P7's gates off. An
  interactive one names the gates worth stopping at.
- **Pointer:** Fable 5.1 subpage,
  [Finish the whole task](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#finish-the-whole-task)
  (autonomous); Sonnet 5.5 subpage,
  [Steer initiative and scope](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#steer-initiative-and-scope)
  (carrying work through); Opus 5.5 subpage,
  [Unattended agentic runs](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#unattended-agentic-runs);
  correlate: Opus 5.5 usage guide, "Say what 'done' looks like, then let it run" and "Tell it which
  stops you want".

### P7: Destructive-action confirmation

- **Predicate:** destructive-capable.
- **Present when:** hard-to-reverse, shared-system, or destructive actions require confirmation or
  an equivalent mechanical gate, and obstacles must not be shortcut destructively. A deny-by-
  default hook or script gate satisfies this without any prose. That is evidence Phase B's
  instruction-text inventory cannot hold, so SKILL.md Phase C requires looking in three places before
  this row may be judged MISSING: settings rules, hook configuration, and **the script the component
  delegates the destructive step to**, followed and read. The script gate is the one most easily
  missed, because nothing in the component's own text announces it. This is the only row whose
  presence evidence is allowed to live outside the inventory.
- **Pointer:** main page, "Balancing autonomy and safety".

### P8: Context-budget reassurance

- **Predicate:** context-surfacing.
- **Model condition:** we treat the underlying capability as model-scoped. Components here run on
  any consumer model, so per SKILL.md Gotchas
  ("Model-conditional postures stay conditional") the proposal must be model-neutral or carry that
  model condition. Read the model list on the run's live fetch; this file keeps no copy.
  Pointer: for which models the capability covers, see
  [context windows: context awareness](https://platform.claude.com/docs/en/build-with-claude/context-windows#context-awareness).
  As of: 2026-10-01. Recheck trigger: that section's model list changes.
- **Present when:** the surfaced figure is accompanied by do-not-wrap-up-early framing (or the
  component deliberately avoids surfacing raw countdowns at all, the stronger form).
- **Pointer:** main page,
  [Context awareness and multiwindow workflows](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices#context-awareness-and-multiwindow-workflows);
  Sonnet 5.5 subpage,
  [Mid-turn user messages](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#mid-turn-user-messages-and-task-budgets)
  (countdowns after tool results).

### P9: Multi-window state guidance

- **Predicate:** multi-window, or long-running (a run long enough for compaction to summarize
  older turns).
- **Present when:** the component prescribes durable structured state (files/git) and how a fresh
  window re-grounds, rather than relying on conversational memory. For a long run this includes a
  task list in a file, ticked as items finish and extended with new ones found, read instead of
  the scrollback. An existing ledger or state file that does this satisfies it.
- **Pointer:** main page, "Workflows across multiple context windows" and "State management best
  practices"; Opus 5.5 subpage, "Unattended agentic runs"; correlate: Opus 5.5 usage guide, "Keep
  the task list in a file".

### P10: Parallel-tool-call steering

- **Predicate:** parallelism-steering.
- **Present when:** the steering distinguishes independent calls (parallelize) from dependent ones
  (sequence, never placeholder-guess parameters).
- **Pointer:** main page, "Optimize parallel tool calling".

### P11: End-of-run report leads with what the human owes

- **Predicate:** long-running.
- **Present when:** the component's final report opens with what is blocked on the human (open
  decisions, changes to approve), then what changed and what was found, for example under the
  headings "Blocked on me", "Changed", "Found". An existing report shape that puts the human's
  items first satisfies it; adapt that shape rather than adding a second one.
- **Pointer:** Opus 5.5 subpage, "Capabilities relevant to prompting" (communication); correlate:
  Opus 5.5 usage guide, "Read what it needs from you first".

### P12: No self-started review rounds at xhigh or max effort

- **Predicate:** code-changing or orchestrating, AND the component pins `xhigh` or `max` effort (its
  `effort:` frontmatter) or its text sets one of those levels for its own work. A component that
  pins nothing is NOT-APPLICABLE, whatever level a session might run it at.
- **Model condition:** the only page section behind this row is in the Sonnet 5.5 subpage, so per
  SKILL.md Gotchas the proposal carries that model's condition, for example "when running on
  Sonnet 5.5 at `xhigh` or `max`". Never propose it unconditionally.
- **Present when:** the component, for runs at `xhigh` or `max`, states where its run ends and adds
  no step of its own after that point. For the steer this checks for, see the pointer. A check the
  repository requires (a mandated fresh-context verifier, a merge gate) is part of the run, not a
  step after its end.
- **Pointer:** Sonnet 5.5 subpage,
  [Steer initiative and scope](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#steer-initiative-and-scope)
  (its paragraph on the top two effort levels).

### P13: Runnable check behind a done claim

- **Predicate:** code-changing.
- **Present when:** the component names a check that executes the change (a repository command, a
  verification skill, or a gate), makes a done claim depend on it, and has its report name the
  check and its result. For the steer this checks for, see the pointer. Handing the check to a
  named skill or gate satisfies the row. We treat this as model-neutral, so the proposal carries
  no model condition.
- **Why a new row and not P3 or P5:** P3 binds only a flow that makes tests pass and asks what the
  fix targets. P5 binds long-running components and asks about progress claims in general. This
  row binds every code-changing component and asks one thing: that "done" rests on a check that
  ran, named in the report.
- **Pointer:** Sonnet 5.5 subpage,
  [Verification on coding tasks](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#verification-on-coding-tasks).

### P14: Ideas-first on open-ended requests

- **Predicate:** ideating.
- **Present when:** in the component's text, the step that delivers its proposals is followed by a
  wait for the user's choice, and every step that writes or edits files comes after that wait. An
  explicit end of turn, a human gate, or a choose-then-proceed instruction each counts as the wait.
  We treat this as model-neutral, so the proposal carries no model condition.
- **Pointer:** Sonnet 5.5 subpage,
  [Steer initiative and scope](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#steer-initiative-and-scope)
  (open-ended requests).
