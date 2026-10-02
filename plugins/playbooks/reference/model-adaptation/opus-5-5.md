# Running this playbook on Claude Opus 5.5

> **If you are not Claude Opus 5.5:** these deltas are calibrated for Opus 5.5 specifically. They
> do not transfer to another model as written. Route to your own file under `model-adaptation/`
> when one exists; otherwise apply the *method*: map your documented defaults against the author's
> Fable behavior and adopt only corrections matching your known defaults. Conditional framing is
> deliberate, because spawn-time model overrides can hand this file to a model it was not written
> for.

You are Claude Opus 5.5 reading doctrine authored by Claude Fable 5. The other chapters are
model-agnostic; this one states what this playbook does differently when you run it. Each section
is our decision, followed by a pointer to the upstream section behind it. Read the pointer when you
need the specific: this file restates none of it.

Do not load `opus-5.md` beside this chapter. Meta-rule 3 loads one chapter per session, and the
Opus 5 rules this playbook keeps for you are restated below, once, in "What carries from the Opus 5
chapter".

Each delta carries a Claude-Code-applicability tag, as in the sibling chapters:

- `[CC: direct]` applies to Claude Code sessions as-is.
- `[CC: prompt-authoring]` applies when you author prompts, briefs, skills, or agent bodies.
- `[CC: API-side]` applies to API integrations, not interactive Claude Code use.

"The guide" below is the
[Prompting Claude Opus 5.5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5)
page.

## Thinking and effort

Effort is the only depth control this playbook uses on you. Remove "think carefully", "think step
by step", and similar lines from prompts and standing instructions you author. Treat any
thinking-disable setting aimed at you, in Claude Code settings or in an API request, as a defect to
remove rather than a lever. `[CC: prompt-authoring]`

Do not carry an Opus 5 effort setting over. Start from your own default, use `xhigh` or `max` only
with a measured quality gain to justify it, and lower effort before writing prompt instructions
when you want less thinking. In Claude Code, set your level with `/effort` or the model picker
rather than relying on a top-level `effortLevel` in user settings. The default, the ladder, and the
per-model levels resolve at the pointers, never from this file. `[CC: direct]`

Where an integration you author needs a faster first token after effort is already low, the guide
carries a tested line for it; read it there and compare quality before and after adding it.
`[CC: prompt-authoring]`

- **Pointer**: for effort calibration, see the guide's
  [Calibrate effort](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#calibrate-effort)
  and
  [Prompts written for thinking disabled](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#prompts-written-for-thinking-disabled);
  for thinking controls on the API, see
  [Thinking can't be disabled](https://platform.claude.com/docs/en/models/opus-5-5/whats-new-opus-5-5#thinking-cant-be-disabled);
  for Claude Code's controls, see
  [Extended thinking](https://code.claude.com/docs/en/model-config#extended-thinking) and
  [Adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level); for what
  a higher level adds to verifying work, see
  [Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level)
  (correlate with <https://claude.dev/blog/spending-your-effort>).
- **As of**: 2026-09-23 for the guide and the what's-new page; 2026-10-01 for model-config.
- **Recheck trigger**: a re-read of any pointed section no longer supporting the decision above,
  a Claude Code release note that changes thinking or effort controls for this model, or the
  model-config effort sections change.

## Long runs

The communication chapter's "No progress theater" binds hard on you. When a step does not need the
user, put the status note in the same message as your next action and keep going. Stop only when
nothing can move without the user, or at the trust-and-authority chapter's consent gate: anything
destructive, hard to undo, or outward-visible. A rule to keep going never relaxes that gate.
`[CC: direct]`

For long runs, keep the task list in a file and tick it as you go; after compaction, read the file,
not your memory of the scrollback (the context-economy chapter's durable-note rule applies).
`[CC: direct]`

When you author instructions for a long-running agent, start from the guide's early-stop addition
at the pointer; the example stays on the live page. For pair-programming surfaces, the opposite
rule, announcing the plan up front and summarizing at the close, is equally valid; say which one
the surface wants. In an unattended API harness you author, a turn ending in plain text does not
count as done: the harness sends the still-open checklist items back, up to the continuation limit
the guide sets. `[CC: prompt-authoring]`

- **Pointer**: for early stops in long runs, see
  [Unattended agentic runs](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#unattended-agentic-runs).
- **As of**: 2026-09-23
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Reports and questions

When no surface specifies an end-of-run shape, lead with what is blocked on the user, then what
changed, then what was found. Never ask a model, yourself or a worker, to write its hidden thinking
out in the reply: on you that request is a refusal category (see "Safeguards and fallback"
below). Ask for what is needed instead, such as the rationale in a few sentences or the evidence
list. `[CC: prompt-authoring]`

- **Pointer**: for reporting, see
  [Capabilities relevant to prompting](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#capability-improvements)
  and
  [User-facing progress updates](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#user-facing-progress-updates);
  for reasoning extraction, see
  [Safeguard refusals](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#safeguard-refusals).
- **As of**: 2026-09-23
- **Recheck trigger**: a re-read of any pointed section no longer supporting the decision above.

## Delegation

The orchestration chapter governs unchanged: every worker return is recall-grade, so check its
evidence before accepting it, and finish a fan-out with one consolidated table. Coordination
strength is not verification. The Opus 5 delegation floor does not carry to you. `[CC: direct]`

For multi-agent harnesses you author, feed the lead agent a running clock against a time budget,
and enforce the deadline in the harness, since the model treats the budget as guidance.
`[CC: API-side]`

- **Pointer**: for multi-agent work, see
  [Capabilities relevant to prompting](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#capability-improvements)
  and
  [Time signals for multiagent harnesses](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#time-signals-for-multi-agent-harnesses).
- **As of**: 2026-09-23
- **Recheck trigger**: a re-read of either section no longer supporting the decision above.

## Scope boldness

When the work's guardrails are strong, tell the model to be bolder, and name the guardrails in the
same instruction: the review every change passes, the tests that run before it merges, the flag
that turns it off. Where the guardrails are weak, leave the default alone. Boldness never relaxes
the trust-and-authority chapter's consent gate. Unverified on Opus 5.5. `[CC: prompt-authoring]`

- **Pointer**: no docs page covered scope hedging as of the date below. The post's model is not
  Opus 5.5 (correlate with <https://claude.dev/blog/how-we-made-claude-ai-faster>).
- **As of**: 2026-09-23
- **Recheck trigger**: a docs page starts covering scope hedging or estimate padding (move the
  pointer there), or the post's model is identified.

## Review

Run every review pass, the first included, at `medium` effort or above, per this repository's
effort floor. When the output goes to a human, give the reviewer a concrete bar a reader can apply
to a novel finding. When recall matters, keep the Opus 5 method: find everything, then filter in a
separate pass. `[CC: prompt-authoring]`

- **Pointer**: for review, see
  [Capabilities relevant to prompting](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#capability-improvements);
  for the effort floor, see
  [Effort floor](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/plugin-philosophy.md#effort-floor);
  for what a higher level adds to verifying work, see
  [Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level)
  (correlate with <https://claude.dev/blog/spending-your-effort>).
- **As of**: 2026-09-23 for the guide; 2026-10-01 for the effort floor and model-config.
- **Recheck trigger**: a re-read of the guide section, or a later page, addresses whether a severity
  bar lowers this model's recall, or the model-config section changes.

## Stated facts

The calibration chapter's identifier rule governs unchanged: a specific you state without a tool
call behind it this session is recall-grade. When asked to check a long document, quote each
problem and say where it is. The Opus 5 card's stated-facts finding is about a different model and
does not carry. `[CC: direct]`

- **Pointer**: for knowledge work, see
  [Capabilities relevant to prompting](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#capability-improvements).
- **As of**: 2026-09-23
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Vision

Read the image itself rather than a retyped transcription of it. Keep image-handling steps written
for older models only after checking that they still improve the answer. When an image is too
dense to read reliably, give it more pixels, let the model crop it, and raise effort.
`[CC: direct]`

- **Pointer**: for visual inputs, see
  [Tools for complex visual inputs](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#tools-for-complex-visual-inputs).
- **As of**: 2026-09-23
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Design

For frontend work, give a named list of styles to avoid; a request for a "less generic" look is
not enough. The guide's example list stays on the live page. Check which styles the first draft
fell back on, and add any unwanted one to the list before the next pass. `[CC: direct]`

- **Pointer**: for design defaults, see
  [Frontend design defaults](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#frontend-design-defaults).
- **As of**: 2026-09-23
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Chat system prompts

For chat-product system prompts you author, remove think-carefully lines, and use the guide's
settled-answers instruction where follow-up latency matters; read it at the pointer. Leave it out
of long analysis and agentic work, where revisiting earlier output is the point. It never goes
into this playbook or any agentic surface. `[CC: prompt-authoring]`

- **Pointer**: for thinking instructions in chat, see
  [Thinking instructions in chat system prompts](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#thinking-instructions-in-chat-system-prompts).
- **As of**: 2026-09-23
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Safeguards and fallback

Treat any in-context evidence of a model switch as the meta-rule 3 trigger and re-resolve the
adaptation chapter against the model now answering; do not keep applying this file after a switch.
To return to this model, or to be asked before each switch, use the controls the two fallback
pointers below name. `[CC: direct]` Never write, in a prompt, brief, or skill, an instruction asking for
hidden thinking in the reply. `[CC: prompt-authoring]`

- **Pointer**: for Claude Code's fallback, see
  [Automatic model fallback](https://code.claude.com/docs/en/model-config#automatic-model-fallback)
  and [Ask before switching](https://code.claude.com/docs/en/model-config#ask-before-switching);
  for the refusal categories, see
  [Safeguard refusals](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#safeguard-refusals)
  and
  [Refusals and fallback](https://platform.claude.com/docs/en/models/opus-5-5/whats-new-opus-5-5#refusals-and-fallback).
- **As of**: 2026-10-01 for model-config; 2026-09-23 for the guide and the what's-new page.
- **Recheck trigger**: a re-read of the fallback section naming different targets, or a refusal
  category added or removed for this model.

## Speed

Use `/fast` for back-and-forth work where the user reads each reply; leave it off for unattended
runs where latency is not the constraint. Availability and prices resolve at the pointer.
`[CC: direct]`

- **Pointer**: for fast mode, see
  [Decide when to use fast mode](https://code.claude.com/docs/en/fast-mode#decide-when-to-use-fast-mode).
- **As of**: 2026-10-01
- **Recheck trigger**: fast mode leaves research preview, or the page stops listing this model.

## API-side, for integrations you author

Do not force `tool_choice` on this model. Show progress-update thinking blocks to users, or a
text-only client looks frozen during tool work. Keep conversation histories append-only. For
multi-app agents, have the model survey the connected sources before it changes anything, and give
it only sources free of untrusted content. Mark user-pasted text with tagged blocks, in
the form the guide gives. Size `max_tokens` with thinking counted in. Model IDs, prices, and limits
resolve through the `claude-api` skill at the moment of use; this chapter carries none.
`[CC: API-side]`

- **Pointer**: for the breaking changes, see
  [Forced tool use is not supported](https://platform.claude.com/docs/en/models/opus-5-5/whats-new-opus-5-5#forced-tool-use-is-not-supported),
  [Thinking blocks are tied to the model and the conversation](https://platform.claude.com/docs/en/models/opus-5-5/whats-new-opus-5-5#thinking-blocks-are-tied-to-the-model-that-produced-them),
  and
  [Text between tool calls is returned in thinking blocks](https://platform.claude.com/docs/en/models/opus-5-5/migration-guide#text-between-tool-calls);
  for the prompting patterns, see
  [Explore context in multi-app workflows](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#explore-context-in-multi-app-workflows),
  [Mark pasted text in user messages](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#mark-pasted-text-in-user-messages),
  and
  [Calibrate effort](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#calibrate-effort).
- **As of**: 2026-09-23
- **Recheck trigger**: a re-read of any pointed section no longer supporting the decision above.

## What carries from the Opus 5 chapter, and what does not

- **Carries, as method:** worker returns are recall-grade; find first, filter separately when
  recall matters; for destructive or irreversible operations under auto-accept, a mechanism (a
  `PreToolUse` hook or a `permissions.deny` rule) is the control and a written rule is the weaker
  one; hard facts are pointers.
- **Reversed:** the `high` effort default, the thinking-disable configuration rule, and the
  stated-facts finding.
- **Not imported:** the instructed re-check removal, the delegation floor, and the
  correction-narration rule. The verification and orchestration chapters apply unchanged.
- **Do not read another version's chapter.** Meta-rule 3 in the skill body owns this routing.

## Sources

Our reads, recorded so a re-read can tell whether a page moved:

- The guide, raw `.md` read 2026-09-23 (28,311 bytes, MD5 `fb3bff7f41e20fbbb71be78770edb8cb`).
- <https://platform.claude.com/docs/en/models/opus-5-5/whats-new-opus-5-5>, raw `.md` read
  2026-09-23 (21,525 bytes, MD5 `bacb60024cacd3f9bdb539587fbc9bf8`).
- <https://code.claude.com/docs/en/model-config> and <https://code.claude.com/docs/en/fast-mode>,
  re-read 2026-10-01.

Recheck trigger for the whole chapter: a later Opus release, or a re-read of any pointed section
no longer supporting the decision beside it.
