# Running this playbook on Claude Sonnet 5.5

> **If you are not Claude Sonnet 5.5:** these deltas are calibrated for Sonnet 5.5 specifically.
> They do not transfer to another model as written. Route to your own file under
> `model-adaptation/` when one exists; otherwise apply the *method*: map your documented defaults
> against the author's Fable behavior and adopt only corrections matching your known defaults.
> Conditional framing is deliberate, because spawn-time model overrides can hand this file to a
> model it was not written for.

You are Claude Sonnet 5.5 reading doctrine authored by Claude Fable 5. The other chapters are
model-agnostic. This one holds only this repository's own decisions for you and, for everything
the guide covers, a trigger saying when to read a section and the pointer to it. Where our practice
would only repeat the guide's advice, the chapter says nothing and points: read the section live.

Do not load `sonnet-5.md` beside this chapter. Meta-rule 3 loads one chapter per session, and the
Sonnet 5 rules this playbook keeps for you are listed once, in "What carries from the Sonnet 5
chapter". The exception is a fallback: if the session moves to Sonnet 5, meta-rule 3 re-resolves
and `sonnet-5.md` replaces this file (see "Safeguards and fallback").

Each entry carries a Claude-Code-applicability tag, as in the sibling chapters:

- `[CC: direct]` applies to Claude Code sessions as-is.
- `[CC: prompt-authoring]` applies when you author prompts, briefs, skills, or agent bodies.
- `[CC: API-side]` applies to API integrations, not interactive Claude Code use.

"The guide" below is the
[Prompting Claude Sonnet 5.5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5)
page.

## Effort

Our decision: code-changing or verifying work runs at `medium` or above, per this repository's
effort floor. `[CC: direct]`

Trigger: before you choose or change this model's effort level, in a session, an agent or skill
pin, or an API request you author, read the guide's effort section and the effort page's levels for
this model. For Claude Code's levels, its default for this model, and the cache effect of a
mid-session change, read the Claude Code pointers. `[CC: direct]`

- **Pointer**: for the effort floor, see
  [Effort floor](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/plugin-philosophy.md#effort-floor);
  for effort on this model, see the guide's
  [Calibrate effort](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#calibrate-effort)
  and
  [Recommended effort levels for Claude Sonnet 5.5](https://platform.claude.com/docs/en/build-with-claude/effort#recommended-effort-levels-for-claude-sonnet-5-5);
  for Claude Code, see
  [Adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level),
  [Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level),
  and
  [Changing effort level](https://code.claude.com/docs/en/prompt-caching#changing-effort-level).
- **As of**: 2026-10-01
- **Recheck trigger**: the effort floor changing, or any pointed section moving.

## Where a run stops and what it covers

Our decision: the agents in this repository that carry a finish-then-stop instruction state it in
their own "When you are done" sections; read those, for example
[ecosystem-specialist](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/review/agents/ecosystem-specialist.md#when-you-are-done)
and
[doc-drift-detector](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/review/agents/doc-drift-detector.md#when-you-are-done).
`[CC: prompt-authoring]`

Trigger: when a run on this model, yours or one on a surface you author, stops at a point the
request did not intend or covers more or less than the request asked, read the guide's section at
the pointer. `[CC: direct]` `[CC: prompt-authoring]`

- **Pointer**: see
  [Steer initiative and scope](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#steer-initiative-and-scope).
- **As of**: 2026-10-01
- **Recheck trigger**: that section moving, or an agent's "When you are done" section being
  renamed or removed.

## Review at the top effort levels

Our decision: at `xhigh` or `max`, posture P12 governs; read it at the link. `[CC: direct]`

Trigger: before you plan how many subagents a run may spawn, read Claude Code's subagent limits at
the pointers. `[CC: direct]`

- **Pointer**: for the posture, see
  [P12: No self-started review rounds at xhigh or max effort](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/claude-config/skills/audit-prompting-postures/reference/postures.md#p12-no-self-started-review-rounds-at-xhigh-or-max-effort);
  for the guide, see
  [Steer initiative and scope](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#steer-initiative-and-scope);
  for Claude Code's limits, see
  [Let subagents spawn their own subagents](https://code.claude.com/docs/en/sub-agents#let-subagents-spawn-their-own-subagents)
  and
  [Concurrent subagent limit](https://code.claude.com/docs/en/sub-agents#concurrent-subagent-limit).
- **As of**: 2026-10-01
- **Recheck trigger**: P12 changing, or any pointed section moving.

## Verification

Our decision: the verification chapter governs unchanged, and the effort floor above applies to
verifying work. We do not add the guide's verification paragraph to this repository's agents,
skills, or briefs by default. `[CC: direct]` `[CC: prompt-authoring]`

Trigger: when transcripts from a surface we own show a code change marked finished with no check run
behind it, read the guide's section at the pointer before changing that surface.
`[CC: prompt-authoring]`

- **Pointer**: see
  [Verification on coding tasks](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#verification-on-coding-tasks).
- **As of**: 2026-10-01
- **Recheck trigger**: that section moving, or a transcript from a surface we own showing the
  symptom.

## Thinking

Our decision: the Sonnet 5 chapter's thinking guidance does not carry to you. `[CC: direct]`

Trigger: before you change any thinking setting for this model, in Claude Code or in an API request
you author, read the pointers. `[CC: direct]` `[CC: API-side]`

- **Pointer**: for Claude Code, see
  [Extended thinking](https://code.claude.com/docs/en/model-config#extended-thinking); for the API,
  see
  [Running without up-front thinking](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#running-without-up-front-thinking)
  and
  [Turn off up-front thinking](https://platform.claude.com/docs/en/models/sonnet-5-5/whats-new-sonnet-5-5#turn-off-up-front-thinking).
- **As of**: 2026-10-01
- **Recheck trigger**: any pointed section moving, or a Claude Code release note adding a thinking
  setting for this model.

## Progress updates

Our decision: the Sonnet 5 chapter's progress-update rule does not carry to you, and this
repository builds no quiet-turn reminder of its own. `[CC: prompt-authoring]`

Trigger: when updates from this model, on a surface you author or in a client that renders its
responses, come too rarely, too late, or not at all, read the guide's section at the pointer.
`[CC: prompt-authoring]` `[CC: API-side]`

- **Pointer**: see
  [User-facing progress updates](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#user-facing-progress-updates).
- **As of**: 2026-10-01
- **Recheck trigger**: that section moving.

## Mid-turn messages and hook text

Our decision: the trust-and-authority chapter governs how you judge any message's authority, and
hook text this repository writes follows the hook-observability convention. `[CC: direct]`
`[CC: prompt-authoring]`

Trigger: when a message that arrived mid-turn looks as if it may not be from the user, or before you
add a hook that writes into context after tool results, read the pointers.
`[CC: direct]` `[CC: prompt-authoring]`

- **Pointer**: for this model, see
  [Mid-turn user messages](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#mid-turn-user-messages-and-task-budgets);
  for Claude Code hooks, see
  [Add context for Claude](https://code.claude.com/docs/en/hooks#add-context-for-claude); for our
  convention, see the
  [hook-observability convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/hook-observability/README.md).
- **As of**: 2026-10-01
- **Recheck trigger**: either upstream section moving, or the convention changing.

## Current specifics

Our decision: the calibration chapter's identifier rule and its check/skip decision govern
unchanged. `[CC: direct]`

Trigger: when a product you author answers from training knowledge where a current source was
needed, read the guide's section at the pointer. `[CC: prompt-authoring]`

- **Pointer**: see
  [Tool use in chat and knowledge work](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#tool-use-in-chat-and-knowledge-work).
- **As of**: 2026-10-01
- **Recheck trigger**: that section moving.

## JSON output and tool-call handling

Our decision: this repository ships no code that parses model text into JSON and no tool dispatcher
of its own, so neither topic has a home here beyond this pointer. `[CC: direct]`

Trigger: before you write an integration that asks this model for JSON or runs its own tool loop,
read the guide's sections at the pointers. `[CC: API-side]`

- **Pointer**: see
  [Reasoning tasks with JSON output](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#reasoning-tasks-with-json-output)
  and
  [Tolerant tool-call handling](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#tolerant-tool-call-handling).
- **As of**: 2026-10-01
- **Recheck trigger**: either section moving, or this repository gaining code that parses model
  output or dispatches tool calls.

## API requests carried over from Sonnet 5

Our decision: this repository ships no code that sends API requests, so it has no Sonnet 5 request
settings to carry over. `[CC: direct]`

Trigger: before you move an API integration you author from Sonnet 5 to this model, or when a
request that worked on Sonnet 5 is rejected on this one, read the migration guide at the pointer.
`[CC: API-side]`

- **Pointer**: see the
  [Sonnet 5.5 migration guide](https://platform.claude.com/docs/en/models/sonnet-5-5/migration-guide).
- **As of**: 2026-10-01
- **Recheck trigger**: that page moving, or this repository gaining code that sends API requests.

## Dense images

Trigger: before you answer from a dense chart, a technical drawing, or another image whose answer
depends on fine detail, or build a harness that feeds such images to a model, read the playbook's
[reading-dense-images.md](../../skills/fable-5/context/reading-dense-images.md) note and the guide's
section at the pointer. `[CC: direct]` `[CC: API-side]`

- **Pointer**: see
  [Tools for complex visual inputs](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#tools-for-complex-visual-inputs).
- **As of**: 2026-10-01
- **Recheck trigger**: that section moving.

## Which surfaces we author as system prompt

Our decision: this repository authors CLAUDE.md, rules, and skill bodies as conversation content,
and treats only a subagent's body and the launch flags that set or append the system prompt as
system prompt. When a guide section tells you to add a line to the system prompt, place it on one
of those two. `[CC: prompt-authoring]`

- **Pointer**: for CLAUDE.md, see
  [Claude isn't following my CLAUDE.md](https://code.claude.com/docs/en/memory#claude-isn%E2%80%99t-following-my-claude-md);
  for subagent bodies, see
  [Write subagent files](https://code.claude.com/docs/en/sub-agents#write-subagent-files); for the
  flags, see
  [System prompt flags](https://code.claude.com/docs/en/cli-reference#system-prompt-flags).
- **As of**: 2026-10-01
- **Recheck trigger**: any pointed section moving, or Claude Code documenting how skill bodies are
  delivered.

## Safeguards and fallback

Our decision: treat any in-context evidence of a model switch as the meta-rule 3 trigger and
re-resolve the adaptation chapter against the model now answering. `[CC: direct]`

Trigger: for which flagged requests move this session to which model, how to return, and how to be
asked before a switch, read Claude Code's pointers. Before writing a prompt, brief, or skill that
asks a model for its reasoning in the reply, read the guide's refusals section.
`[CC: direct]` `[CC: prompt-authoring]`

- **Pointer**: for Claude Code, see
  [Automatic model fallback](https://code.claude.com/docs/en/model-config#automatic-model-fallback)
  and [Ask before switching](https://code.claude.com/docs/en/model-config#ask-before-switching);
  for the refusal categories, see
  [Safeguard refusals](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5-5#safeguard-refusals)
  and
  [Refusals, fallback, and billing](https://platform.claude.com/docs/en/models/sonnet-5-5/whats-new-sonnet-5-5#refusals-fallback-and-billing).
- **As of**: 2026-10-01
- **Recheck trigger**: the fallback section naming different targets for this model, or a refusal
  category added or removed for it.

## Caching and speed

Our decision: the `fast` capability tier in this repository's loop-lane convention is a tier name,
unrelated to Claude Code's fast mode. The playbook's prompt-caching chapter
(`${CLAUDE_PLUGIN_ROOT}/reference/prompt-caching.md`) owns caching mechanisms. `[CC: direct]`

Trigger: before counting on cache hits in API code you author for this model, read the cache
limitations at the pointer; for which models fast mode supports, read the fast mode page.
`[CC: API-side]` `[CC: direct]`

- **Pointer**: see
  [Cache limitations](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#cache-limitations),
  [Speed up responses with fast mode](https://code.claude.com/docs/en/fast-mode), and, for the
  tier,
  [Capability tiers](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/loop-lane/README.md#3-capability-tiers).
- **As of**: 2026-10-01
- **Recheck trigger**: any pointed section moving, or fast mode leaving research preview.

## Disagreements between pages

Each entry names two pages that disagree; neither position is restated here. Until they agree we
follow the docs page over a post, the model's prompting guide on model behavior, and Claude Code's
docs on Claude Code delivery.

- **Priority Tier availability for this model.** The
  [Supported models](https://platform.claude.com/docs/en/api/service-tiers#supported-models)
  section of the service tiers page and the launch post's model table disagree
  (correlate with <https://claude.dev/blog/building-with-claude-sonnet-5-5#model-details>).
- **Whether up-front thinking can be turned off on this model.**
  [Turn off up-front thinking](https://platform.claude.com/docs/en/models/sonnet-5-5/whats-new-sonnet-5-5#turn-off-up-front-thinking)
  and Claude Code's [Extended thinking](https://code.claude.com/docs/en/model-config#extended-thinking)
  section disagree.
- **Which model to start with.** The models overview's
  [Compare models](https://platform.claude.com/docs/en/models/overview#latest-models-comparison)
  section and the launch post's model-choice table disagree
  (correlate with <https://claude.dev/blog/building-with-claude-sonnet-5-5#choosing-between-sonnet-55-and-opus-55>).

- **As of**: 2026-10-01
- **Recheck trigger**: any section named above changing, or a docs page replacing the post on
  either topic.

## What carries from the Sonnet 5 chapter, and what does not

- **Carries, as method:** the Sonnet 5 chapter's scope, review-findings, and response-length
  decisions, as that chapter states them.
- **Does not carry:** its Effort, Thinking, and Progress updates sections; this chapter's sections
  of the same names replace them.
- **Do not read another version's chapter** except after a fallback. Meta-rule 3 in the skill body
  owns this routing.

## Sources

Our reads, recorded so a re-read can tell whether a page moved:

- The guide, raw `.md` read 2026-10-01 (27,412 B, MD5 `2bcb67cc9f72b68e8823f197034c06d6`).
- <https://platform.claude.com/docs/en/models/sonnet-5-5/whats-new-sonnet-5-5>,
  <https://platform.claude.com/docs/en/api/service-tiers>, and
  <https://platform.claude.com/docs/en/models/overview>, read 2026-10-01.
- <https://code.claude.com/docs/en/model-config>, <https://code.claude.com/docs/en/sub-agents>,
  <https://code.claude.com/docs/en/prompt-caching>, and
  <https://code.claude.com/docs/en/fast-mode>, read 2026-10-01.

Recheck trigger for the whole chapter: a later Sonnet release, or a pointed section moving.
