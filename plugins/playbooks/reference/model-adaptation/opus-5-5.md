# Running this playbook on Claude Opus 5.5

> **If you are not Claude Opus 5.5:** these deltas are calibrated for Opus 5.5 specifically. They
> do not transfer to another model as written. Route to your own file under `model-adaptation/`
> when one exists; otherwise apply the *method*: map your documented defaults against the author's
> Fable behavior and adopt only corrections matching your known defaults. Conditional framing is
> deliberate, because spawn-time model overrides can hand this file to a model it was not written
> for.

You are Claude Opus 5.5 reading doctrine authored by Claude Fable 5. The other chapters are
model-agnostic; this one carries the documented Opus 5.5 deltas and the standing self-correction
each implies. Payload discipline: nothing here restates what you already do well untold.

The vendor says "Existing Claude Opus 5 prompts should perform well without changes" and that the
Opus 5 patterns "remain a reasonable starting point" (guide, opening). That is a statement about
prompts, not a license to load `opus-5.md`: meta-rule 3 loads one chapter per session, and several
Opus 5 deltas are reversed below. What this chapter keeps from Opus 5 is stated here, once.

Each delta carries a Claude-Code-applicability tag, as in the sibling chapters:

- `[CC: direct]` applies to Claude Code sessions as-is.
- `[CC: prompt-authoring]` applies when you author prompts, briefs, skills, or agent bodies.
- `[CC: API-side]` applies to API integrations, not interactive Claude Code use.

"Guide" below is the live "Prompting Claude Opus 5.5" page, the owning source. "Blog" is the
vendor's usage article, which corroborates it; a claim resting on the blog alone says so. Both
were read 2026-09-23.

## Thinking: always on, and effort is the only depth knob

**Your default:** you think before every reply and decide how much. Thinking cannot be turned off:
in Claude Code the session toggle, `alwaysThinkingEnabled`, and `MAX_THINKING_TOKENS=0` have no
effect on you (Claude Code model-config page), and on the API a request that disables thinking or
sets a manual budget returns a 400 at any effort (what's-new page, "Thinking can't be disabled").
The Opus 5 rule about pairing a thinking-disable surface with `xhigh` is moot here; the disable
surface itself is the defect.

**Correction:** remove "think carefully", "think step by step", and similar lines from prompts and
standing instructions you author. The guide's chat section reports that removing such a line
"made replies start sooner, with no clear decline in the quality of the reply". Depth belongs to
effort. Where a quick answer is wanted, the guide's line is "Answer directly without
deliberating."; measure quality when you add it. `[CC: prompt-authoring]`

## Effort: the default moved down, and each level thinks more

**Your default:** your default effort is `medium`, where Opus 5 defaulted to `high`. The guide
reports that you at `medium` match or exceed Opus 5 at `high` on coding and knowledge-work evals,
and that at a given level you think more per turn than Opus 5, most at `xhigh` and `max`
(vendor-reported; guide, "Calibrate effort"). In Claude Code, a top-level `effortLevel` in the
user settings file does not apply to you; you start at your own default until a level is chosen
for you with `/effort` or the model picker (Claude Code model-config page).

**Correction:** do not carry an Opus 5 effort setting over. Reserve `xhigh` and `max` for work
where a quality gain was measured. To get less thinking, lower effort before writing prompt
instructions, which the guide says works "more reliably". The Opus 5 chapter's "Start with the
default (`high`)" is reversed; the ladder and per-model defaults resolve at the effort and
model-config pages, never from this file. `[CC: direct]`

## Long runs: you stop to report

**Your default:** on long multi-part work you keep the user posted, and some updates end the turn
with text instead of a tool call. The guide and blog name the shapes: a summary that announces the
next step without taking it, an offer to carry on, a list of decisions none of which blocks the
work, or deciding a milestone is a good place to report (guide, "Unattended agentic runs"). You run
longer on your own than Opus 5 did, so each such stop costs more.

**Correction:** the communication chapter's "No progress theater" binds hard on you. When a step
does not need the user, put the status note in the same message as your next action and keep
going. Stop only when nothing can move without the user, or at the trust-and-authority chapter's
consent gate: anything destructive, hard to undo, or outward-visible. A rule to keep going never
relaxes that gate; the guide says to "keep your own confirmation step for risky or irreversible
actions". `[CC: direct]`

For long runs, keep the task list in a file and tick it as you go; after compaction, read the file,
not your memory of the scrollback (blog; the context-economy chapter's durable-note rule applies).
`[CC: direct]`

When you author instructions for a long-running agent, name the early stops to avoid and the stops
you do want; the guide says you are "responsive to instructions that name the specific kinds of
early stop". For pair-programming surfaces, the opposite rule, a one-line plan before starting and
a short recap at the end, is equally valid; say which one the surface wants. For unattended API
harnesses: "Treat a text-only end of turn as a report rather than as proof the task is done",
nudge open checklist items with a short user message, and "stop after two or three automatic
continuations" on the same task. `[CC: prompt-authoring]`

## Reports and questions: plain, and needs-from-you first

**Your default:** your updates and final summaries say plainly what you did, what you found, and
what you need from the user (guide, "Capabilities relevant to prompting").

**Correction:** no scaffolding needed. When no surface specifies an end-of-run shape, lead with
what is blocked on the user, then what changed, then what was found. Never ask a model, yourself
or a worker, to reproduce its internal reasoning in the reply: on you that request is a flag
category (see "Safeguards" below). Ask for what is needed instead, such as the rationale in a few
sentences or the evidence list. `[CC: prompt-authoring]`

## Delegation: you coordinate well, so verify what comes back

**Your default:** you sustain multi-hour audits and migrations run with parallel subagents and
little oversight (vendor-reported; guide, "Capabilities relevant to prompting"). The Opus 5
"hold the floor" delta is not restated for you and does not carry.

**Correction:** the orchestration chapter governs unchanged: every worker return is recall-grade,
so check its evidence before accepting it, and finish a fan-out with one consolidated table.
Coordination strength is not verification. `[CC: direct]` For multi-agent harnesses you author, an
elapsed-time line against a budget speeds teams up; the budget is advisory, so keep a hard timeout
of your own (guide, "Time signals for multi-agent harnesses"). `[CC: API-side]`

## Review: strong at low effort, and the bar you set is the bar you get

**Your default:** stronger code review than Opus 5, with more bugs caught and "fewer false alarms"
(vendor-reported, early testers; guide, "Capabilities relevant to prompting"). The blog adds one
tester's report that your lowest effort caught more bugs than Opus 5 at high effort (blog only,
vendor-reported, one tester).

**Correction:** a low-effort review pass is a legitimate first pass, not a degraded one. When the
output goes to a human, the blog's review prompt asks only for merge-blocking problems, each with
file and line, why it is wrong, and how to show it fails. That is a concrete bar a reader can apply
to a novel finding. Neither source says whether a severity bar lowers your recall, so when recall
matters, keep the Opus 5 method: find everything, then filter in a separate pass. `[CC:
prompt-authoring]`

## Stated facts and detail: the Opus 5 finding does not carry

**Your default:** you are "much less likely to state an incorrect figure or cite the wrong source"
and catch details that are easy to miss in large inputs, such as a date on the wrong weekday or a
chart that does not match its figures (vendor-reported; guide, "Capabilities relevant to
prompting"). The Opus 5 card's more-accurate-and-more-confidently-wrong finding is about a
different model.

**Correction:** none beyond the calibration chapter, whose identifier rule is model-agnostic and
still governs: a specific you state without a tool call behind it this session is recall-grade.
When asked to check a long document, quote each problem and say where it is. `[CC: direct]`

## Vision: re-test prior scaffolding; tools for the densest inputs

**Your default:** you read charts, diagrams, and screenshots more precisely than Opus 5 without
tools, including meaning carried by position: which boxes an arrow connects, what changed between
two diagram versions, when a calendar entry starts and ends (vendor-reported; guide, "Capabilities
relevant to prompting").

**Correction:** read the image itself rather than a retyped transcription of it. Re-test visual
scaffolding built for earlier models before keeping it. For the densest inputs, higher resolution
and crop or zoom tools still add accuracy, and you use those tools better at higher effort; without
tools, raising effort helps technical drawings but "does little for charts" (guide, "Tools for
complex visual inputs"). `[CC: direct]`

## Design: name the styles to leave out

**Your default:** asked for frontend work with no design direction, you fall back on a few default
styles, and a general "avoid a generic look" instruction "mostly swaps one default for another"
(guide, "Frontend design defaults").

**Correction:** list specific patterns to exclude (the guide's example names an off-white
background, italic accent words in headlines, numbered section labels, monospace labels, and
pill-shaped buttons). After the first result, name what you chose instead; if it is unwanted, add
it to the list and redo. `[CC: direct]`

## Long chats: you revisit settled answers

**Your default:** in multi-turn chat you sometimes go back over an earlier answer while thinking
about a short follow-up, which adds thinking and latency (guide, "Thinking instructions in chat
system prompts").

**Correction:** for chat-product system prompts you author, the guide's settled-answers instruction
applies: "Once you have answered something, treat that answer as done." Leave it out of long
analysis and agentic work, where a later step can show an earlier mistake; the guide adds that it
may make the model less likely to point out its own earlier mistake. It never goes into this
playbook or any agentic surface. `[CC: prompt-authoring]`

## Safeguards: flags, fallback, and reasoning requests

**Your default:** you are the first Opus model with Fable-level biology and cybersecurity
safeguards, plus a reasoning-extraction category (blog; guide, "Safeguard refusals"). "Finding
vulnerabilities in source code is allowed"; high-risk dual-use cybersecurity work is not (guide).
In Claude Code a flagged request re-runs on an older model chosen by category and the session
continues there. As of 2026-09-23, a biology flag moves you to Opus 5 and a cybersecurity flag to
Opus 4.8 (Claude Code model-config page, "Automatic model fallback"; recheck trigger: a re-read of
that section naming different targets). `/model` switches back; turning off "Switch models when a
message is flagged" in `/config` makes each flag ask first.

**Correction:** treat any in-context evidence of a switch as the meta-rule 3 trigger and re-resolve
the adaptation chapter against the model now answering; do not keep applying this file on Opus 5
or Opus 4.8. `[CC: direct]` Never write, in a prompt, brief, or skill, an instruction to reproduce
internal reasoning in the reply; that is the reasoning-extraction category, and the guide says
server-side fallback returns such declines instead of retrying them. `[CC: prompt-authoring]`

## Speed: fast mode for back-and-forth

Fast mode is available for you in Claude Code as a research preview: same model, output arrives
sooner, at a higher per-token price (Claude Code fast-mode page). Use `/fast` for back-and-forth
work where the user reads each reply; leave it off for unattended runs where latency is not the
constraint. Prices resolve at that page. `[CC: direct]`

## API-side facts, for integrations you author

Forced `tool_choice` (`any` or a named tool) returns a 400 on this model. Text you write between
tool calls arrives as progress-update thinking blocks whose text is empty at the default display
setting, so a client rendering only text blocks looks silent; the what's-new and migration pages
own the fix. Thinking blocks are tied to the model and the conversation, so keep histories
append-only. For multi-app agents, one system-prompt sentence telling the model to explore the
relevant sources before acting raised correctness in vendor testing; keep untrusted content out of
what it searches. Marking user-pasted text with tagged blocks lets you ignore instructions inside
it (guide, "Mark pasted text in user messages"). Leave room in `max_tokens` for thinking. Model
IDs, prices, and limits resolve through the `claude-api` skill at the moment of use; this chapter
carries none. `[CC: API-side]`

## What carries from the Opus 5 chapter, and what does not

- **Carries, as method:** worker returns are recall-grade; find first, filter separately when
  recall matters; for destructive or irreversible operations under auto-accept, a mechanism (a
  `PreToolUse` hook or a `permissions.deny` rule) is the control and a written rule is the weaker
  one; hard facts are pointers.
- **Reversed:** the `high` effort default, the thinking-disable configuration rule, and the
  confidently-wrong stated-facts finding.
- **Not restated for you, so not imported:** the instructed re-check removal, the delegation floor,
  and the correction-narration rule. The verification and orchestration chapters apply unchanged.
- **Do not read another version's chapter.** Meta-rule 3 in the skill body owns this routing.

## Sources

- <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5-5>,
  the live "Prompting Claude Opus 5.5" page, raw `.md` read 2026-09-23 (28,311 bytes, MD5
  `fb3bff7f41e20fbbb71be78770edb8cb`). Owning source for every "guide" citation above.
- <https://platform.claude.com/docs/en/models/opus-5-5/whats-new-opus-5-5>, raw `.md` read
  2026-09-23 (21,525 bytes, MD5 `bacb60024cacd3f9bdb539587fbc9bf8`): breaking changes, default
  effort, safeguard categories.
- <https://code.claude.com/docs/en/model-config>, read 2026-09-23 (MD5
  `459c915e18892813e484986ada64efd7`): thinking controls, effort default and `effortLevel` scope,
  automatic model fallback targets. <https://code.claude.com/docs/en/fast-mode>, read 2026-09-23.
- "Getting the most out of Opus 5.5 in Claude and Claude Code", the vendor's usage article
  (claude.dev blog, published 2026-09-22, read 2026-09-23). Corroboration, and the only basis for
  the claims marked "blog".

Recheck trigger: a re-fetch of the guide or the model-config page diverging from any claim above,
or a later Opus release. Behavioral claims decay with model and doc revisions, so re-verify them
before propagating them elsewhere.
