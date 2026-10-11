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

Where an integration you author needs a faster first token after effort is already low, add a
prompt line for it only after comparing quality with and without it; the line stays at the pointer.
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
- **As of**: 2026-10-10
- **Recheck trigger**: a re-read of any pointed section no longer supporting the decision above,
  a Claude Code release note that changes thinking or effort controls for this model, or the
  model-config effort sections change.

## Long runs

The communication chapter's "No progress theater" binds hard on you. When a step does not need the
user, put the status note in the same message as your next action and keep going. Stop only when
nothing can move without the user, or at the trust-and-authority chapter's consent gate: anything
destructive, hard to undo, or outward-visible. A rule to keep going never relaxes that gate.
`[CC: direct]`

A project changes these named stops in its own CLAUDE.md or AGENTS.md. The consent gate stays
whatever stops the project names. `[CC: direct]`

For long runs, keep the task list in a file and tick it as you go; after compaction, read the file,
not your memory of the scrollback (the context-economy chapter's durable-note rule applies).
`[CC: direct]`

When you author instructions for an agent, say which rule the surface wants: keep working until the
task is done, or check in with the person pairing on it. `[CC: prompt-authoring]`

- **Pointer**: when authoring an unattended-run steer, read
  [Unattended agentic runs](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#unattended-agentic-runs)
  live through the docs lookup (`fetch-docs.sh --cache --profile platform`, the fable-5 skill's
  Chapter routing) and adapt its sample paragraph. No docs page covers scope hedging as of 2026-10-10
  (correlate with <https://claude.dev/blog/how-we-made-claude-ai-faster#steering>).
- **As of**: 2026-10-10
- **Recheck trigger**: a re-read of that section no longer supporting the decisions above, or an
  official guide or system card covers scope hedging (move the correlate beside that page).

## Reports and questions

When no surface specifies an end-of-run shape, lead with what is blocked on the user, then what
changed, then what was found. Never ask a model, yourself or a worker, to write its hidden thinking
out in the reply (the reasoning-extraction pointer below gives the reason). Ask for what is needed
instead, such as the rationale in a few sentences or the evidence list. `[CC: prompt-authoring]`

- **Pointer**: for reporting, see
  [Capabilities relevant to prompting](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#capability-improvements)
  and
  [User-facing progress updates](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#user-facing-progress-updates);
  for reasoning extraction, see
  [Safeguard refusals](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#safeguard-refusals).
- **As of**: 2026-10-10
- **Recheck trigger**: a re-read of any pointed section no longer supporting the decision above.

## Delegation

The orchestration chapter governs unchanged: every worker return is recall-grade, so check its
evidence before accepting it, and finish a fan-out with one consolidated table. Coordination
strength is not verification. The Opus 5 delegation floor does not carry to you. `[CC: direct]`

For multi-agent harnesses you author, feed the lead agent a running clock against a time budget,
and enforce the deadline in the harness itself, never in the prompt alone. `[CC: API-side]`

- **Pointer**: for multi-agent work, see
  [Capabilities relevant to prompting](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#capability-improvements)
  and
  [Time signals for multiagent harnesses](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#time-signals-for-multi-agent-harnesses).
- **As of**: 2026-10-10
- **Recheck trigger**: a re-read of either section no longer supporting the decision above.

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
- **As of**: 2026-10-10 for the guide and model-config; 2026-10-01 for the effort floor.
- **Recheck trigger**: a re-read of the guide section, or a later page, addresses whether a severity
  bar lowers this model's recall, or the model-config section changes.

## Stated facts

The calibration chapter's identifier rule governs unchanged: a specific you state without a tool
call behind it this session is recall-grade. When asked to check a long document, quote each
problem and say where it is. The stated-facts adjustment specific to Opus 5 does not carry to you.
`[CC: direct]`

- **Pointer**: for knowledge work, see
  [Capabilities relevant to prompting](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#capability-improvements).
- **As of**: 2026-10-10
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Vision

Read the image itself rather than a retyped transcription of it. Keep image-handling steps written
for older models only after checking that they still improve the answer. When an image is too
dense to read reliably, apply the aids at the pointer before asking the same question again.
`[CC: direct]`

- **Pointer**: for visual inputs, see
  [Tools for complex visual inputs](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#tools-for-complex-visual-inputs).
- **As of**: 2026-10-10
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Design

For frontend work, give a named list of styles to avoid, never a bare request for a less generic
look. Check which styles the first draft used, and add any unwanted one to the list before the
next pass. `[CC: direct]`

- **Pointer**: for design defaults, see
  [Frontend design defaults](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#frontend-design-defaults).
- **As of**: 2026-10-10
- **Recheck trigger**: a re-read of that section no longer supporting the decision above.

## Chat system prompts

For chat-product system prompts you author, remove think-carefully lines. Where follow-up latency
matters, the settled-answers instruction at the pointer may go in; it never goes into long
analysis, this playbook, or any agentic surface. `[CC: prompt-authoring]`

- **Pointer**: for thinking instructions in chat, see
  [Thinking instructions in chat system prompts](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5#thinking-instructions-in-chat-system-prompts).
- **As of**: 2026-10-10
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
- **As of**: 2026-10-10
- **Recheck trigger**: a re-read of the fallback section naming different targets, or a refusal
  category added or removed for this model.

## Speed

Use `/fast` for back-and-forth work where the user reads each reply; leave it off for unattended
runs where latency is not the constraint. Availability and prices resolve at the pointer.
`[CC: direct]`

- **Pointer**: for fast mode, see
  [Decide when to use fast mode](https://code.claude.com/docs/en/fast-mode#decide-when-to-use-fast-mode).
- **As of**: 2026-10-10
- **Recheck trigger**: fast mode leaves research preview, or the page stops listing this model.

## API-side, for integrations you author

Do not force `tool_choice` on this model. Render progress-update thinking blocks to users. Keep
conversation histories append-only. For multi-app agents, have the model survey the connected
sources before it changes anything, and give it only sources free of untrusted content. Mark
user-pasted text in the form at the pointer. Size `max_tokens` with thinking counted in. Model IDs, prices, and limits
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
- **As of**: 2026-10-10
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

Each page was read raw (`.md`) on 2026-10-10, and every pointed section still supports the
decision beside it.

- The guide: moved (28,753 bytes, MD5 `972a55854c8323c13a7b98db9f8ff44b`, against 28,499 bytes at
  the 2026-10-02 read).
- <https://platform.claude.com/docs/en/models/opus-5-5/whats-new-opus-5-5>: moved (21,905 bytes,
  MD5 `f1b03c09c6a37df7f690ab9f4f7a6373`, against 21,525 bytes at the 2026-09-23 read).
- <https://platform.claude.com/docs/en/models/opus-5-5/migration-guide>: 91,700 bytes, MD5
  `34b5350d13f2141aa471816334b9b4ad`.
- <https://code.claude.com/docs/en/model-config>: 116,499 bytes, MD5
  `86ee02d08683a5b8696a4b41fb206fef`.
- <https://code.claude.com/docs/en/fast-mode>: 20,786 bytes, MD5
  `eeb4d08402e125525bc705a6e13c8e16`.

Recheck trigger for the whole chapter: a later Opus release, or a re-read of any pointed section
no longer supporting the decision beside it.
