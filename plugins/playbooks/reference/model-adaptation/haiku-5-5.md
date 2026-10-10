# Running this playbook on Claude Haiku 5.5

> **If you are not Claude Haiku 5.5:** these deltas are calibrated for Haiku 5.5 specifically.
> They do not transfer to another model as written. Route to your own file under
> `model-adaptation/` when one exists; otherwise apply the *method*: map your documented defaults
> against the author's Fable behavior and adopt only corrections matching your known defaults.
> Conditional framing is deliberate, because spawn-time model overrides can hand this file to a
> model it was not written for.

You are Claude Haiku 5.5 reading doctrine authored by Claude Fable 5. The other chapters are
model-agnostic. This one holds only this repository's own decisions for you and, for everything
the guide covers, a trigger saying when to read a section and the pointer to it. Where our practice
would only repeat the guide's advice, the chapter says nothing and points: read the section live.

This is the first Haiku chapter. No earlier Haiku version has one, so a session on an earlier Haiku
reads no chapter (meta-rule 3), and nothing carries into this file from a predecessor.

Each entry carries a Claude-Code-applicability tag, as in the sibling chapters:

- `[CC: direct]` applies to Claude Code sessions as-is.
- `[CC: prompt-authoring]` applies when you author prompts, briefs, skills, or agent bodies.
- `[CC: API-side]` applies to API integrations, not interactive Claude Code use.

"The guide" below is the
[Prompting Claude Haiku 5.5](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5)
page.

## Where this model runs here

Our decision: in this repository's tier table the `haiku` alias is the bulk-mechanical-sweep rung,
no plugin agent or skill pins `model: haiku`, and the loop lanes bind no tier to it. You most often
arrive here as a subagent an orchestrator spawned on `haiku` for a lookup or a sweep, under its
brief. Read the brief's scope and return contract as binding; this chapter does not widen them.
`[CC: direct]`

- **Pointer**: for the tier table, see
  [Model tiers](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/plugin-philosophy.md#model-tiers);
  for the lanes, see
  [Capability tiers](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/loop-lane/README.md#3-capability-tiers);
  for what the alias resolves to on each provider, see
  [Model aliases](https://code.claude.com/docs/en/model-config#model-aliases).
- **As of**: 2026-10-10
- **Recheck trigger**: a plugin agent or skill pinning `model: haiku`, a loop-lane tier binding
  `haiku`, or the alias changing what it resolves to.

## Effort

Our decision: code-changing or verifying work runs at `medium` or above, per this repository's
effort floor. A lane that picks the `haiku` rung takes it by model alone and omits an effort pin,
as the effort-tier rule says. `[CC: direct]`

Trigger: before you choose or change this model's effort level, in a session, an agent or skill
pin, a spawn's effort parameter, or an API request you author, read the guide's effort section and
the effort page. For Claude Code's levels and its default for this model, read the Claude Code
pointers. `[CC: direct]` `[CC: API-side]`

- **Pointer**: for the effort floor and the pin rule, see
  [Effort floor](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/plugin-philosophy.md#effort-floor)
  and
  [Effort tiers](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/plugin-philosophy.md#effort-tiers);
  for effort on this model, see the guide's
  [Use effort to control thinking](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5#use-effort-to-control-thinking)
  and [Effort](https://platform.claude.com/docs/en/build-with-claude/effort); for Claude Code, see
  [Adjust effort level](https://code.claude.com/docs/en/model-config#adjust-effort-level) and
  [Choose an effort level](https://code.claude.com/docs/en/model-config#choose-an-effort-level).
- **As of**: 2026-10-10
- **Recheck trigger**: the effort floor or the pin rule changing, or any pointed section moving.

## Where a run stops and what it covers

Our decision: the agents in this repository that carry a finish-then-stop instruction state it in
their own "When you are done" sections; read those, for example
[ecosystem-specialist](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/review/agents/ecosystem-specialist.md#when-you-are-done)
and
[doc-drift-detector](https://github.com/melodic-software/claude-code-plugins/blob/main/plugins/review/agents/doc-drift-detector.md#when-you-are-done).
We add no stop paragraph to agents by default. `[CC: prompt-authoring]`

Trigger: when a run on this model, yours or one on a surface you author, stops before the work is
done, hands the task back, or covers more than the request asked, read the guide's section at the
pointer before changing that surface. `[CC: direct]` `[CC: prompt-authoring]`

- **Pointer**: see
  [Prevent early stopping in long agent prompts](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5#prevent-early-stopping-in-long-agent-prompts).
- **As of**: 2026-10-10
- **Recheck trigger**: that section moving, or an agent's "When you are done" section being
  renamed or removed.

## Verification

Our decision: the verification chapter governs unchanged, and the effort floor above applies to
verifying work. We do not add the guide's verification paragraph to this repository's agents,
skills, or briefs by default. `[CC: direct]` `[CC: prompt-authoring]`

Trigger: when transcripts from a surface we own show a code change marked finished with no check run
behind it, read the guide's section at the pointer before changing that surface.
`[CC: prompt-authoring]`

- **Pointer**: see
  [Tell coding agents to verify their changes](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5#tell-coding-agents-to-verify-their-changes).
- **As of**: 2026-10-10
- **Recheck trigger**: that section moving, or a transcript from a surface we own showing the
  symptom.

## Current specifics and search

Our decision: the calibration chapter's identifier rule and its check/skip decision govern
unchanged. `[CC: direct]`

Trigger: when you build a product that gives this model a search tool, or one answers from training
knowledge where a current source was needed, read the guide's section at the pointer.
`[CC: prompt-authoring]` `[CC: API-side]`

- **Pointer**: see
  [Accurate search results](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5#accurate-search-results).
- **As of**: 2026-10-10
- **Recheck trigger**: that section moving.

## Thinking and reasoning in replies

Our decision: this repository sets no thinking option for this model. `[CC: direct]`

Trigger: before you change any thinking setting for this model, in Claude Code or in an API request
you author, read the pointers; Claude Code and the API document different controls. When
reasoning-like text shows up in a reply users see, read the guide's section on it.
`[CC: direct]` `[CC: API-side]`

- **Pointer**: for Claude Code, see
  [Extended thinking](https://code.claude.com/docs/en/model-config#extended-thinking); for the API,
  see
  [Use effort to control thinking](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5#use-effort-to-control-thinking)
  and
  [Keep reasoning out of user-facing text](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5#keep-reasoning-out-of-user-facing-text).
- **As of**: 2026-10-10
- **Recheck trigger**: any pointed section moving, or a Claude Code release note adding a thinking
  setting for this model.

## Mid-turn messages and hook text

Our decision: the trust-and-authority chapter governs how you judge any message's authority, and
hook text this repository writes follows the hook-observability convention. `[CC: direct]`
`[CC: prompt-authoring]`

Trigger: when a message that arrived mid-turn looks as if it may not be from the user, or before you
add a hook that writes into context after tool results, read the pointers.
`[CC: direct]` `[CC: prompt-authoring]`

- **Pointer**: for this model, see
  [Mid-turn user messages](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5#mid-turn-user-messages);
  for Claude Code hooks, see
  [Add context for Claude](https://code.claude.com/docs/en/hooks#add-context-for-claude); for our
  convention, see the
  [hook-observability convention](https://github.com/melodic-software/claude-code-plugins/blob/main/docs/conventions/hook-observability/README.md).
- **As of**: 2026-10-10
- **Recheck trigger**: either upstream section moving, or the convention changing.

## JSON output, tools, and chatbots

Our decision: this repository ships no code that asks a model for JSON through structured outputs,
no tool dispatcher of its own, and no chatbot, so none of these topics has a home here beyond this
pointer. `[CC: direct]`

Trigger: before you write an integration on this model that requests JSON output while it may need
a tool, or deploy it as a chatbot or support assistant, read the guide's sections at the pointers.
`[CC: API-side]`

- **Pointer**: see
  [Use adaptive thinking with JSON output and your own tools](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5#json-output-with-your-own-tools)
  and
  [Keep chatbots to their system prompt](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5#keep-chatbots-to-their-system-prompt).
- **As of**: 2026-10-10
- **Recheck trigger**: either section moving, or this repository gaining code that parses model
  output, dispatches tool calls, or serves a chatbot.

## API requests carried over from Haiku 4.5

Our decision: this repository ships no code that sends API requests, so it has no Haiku 4.5 request
settings to carry over. A dated `claude-haiku-4-5` default in a plugin option stays a pinned
snapshot until its owner moves it. `[CC: direct]`

Trigger: before you move an API integration you author from Haiku 4.5 to this model, or when a
request that worked on Haiku 4.5 is rejected on this one, read the migration guide and the
what's-new page at the pointers. `[CC: API-side]`

- **Pointer**: see the
  [Haiku 5.5 migration guide](https://platform.claude.com/docs/en/models/haiku-5-5/migration-guide)
  and
  [What's new in Claude Haiku 5.5](https://platform.claude.com/docs/en/models/haiku-5-5/whats-new-haiku-5-5).
- **As of**: 2026-10-10
- **Recheck trigger**: either page moving, or this repository gaining code that sends API requests.

## Which surfaces we author as system prompt

Our decision: this repository authors CLAUDE.md, rules, and skill bodies as conversation content,
and treats only a subagent's body and the launch flags that set or append the system prompt as
system prompt. When a guide section tells you to add a line to the system prompt, place it on one
of those two, and read the guide's note on changing a system prompt mid-conversation first.
`[CC: prompt-authoring]`

- **Pointer**: for the guide's note, see the opening of the
  [guide](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5);
  for CLAUDE.md, see
  [Claude isn't following my CLAUDE.md](https://code.claude.com/docs/en/memory#claude-isn%E2%80%99t-following-my-claude-md);
  for subagent bodies, see
  [Write subagent files](https://code.claude.com/docs/en/sub-agents#write-subagent-files); for the
  flags, see
  [System prompt flags](https://code.claude.com/docs/en/cli-reference#system-prompt-flags).
- **As of**: 2026-10-10
- **Recheck trigger**: any pointed section moving, or Claude Code documenting how skill bodies are
  delivered.

## Safeguards and fallback

Our decision: treat any in-context evidence of a model switch as the meta-rule 3 trigger and
re-resolve the adaptation chapter against the model now answering. `[CC: direct]`

Trigger: when a request on this model ends in a refusal, read the guide's refusals section and
Claude Code's fallback section for whether anything re-runs it. Before writing a prompt, brief, or
skill that asks a model for its reasoning in the reply, read the guide's refusals section.
`[CC: direct]` `[CC: prompt-authoring]` `[CC: API-side]`

- **Pointer**: see
  [Safeguard refusals](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-haiku-5-5#safeguard-refusals)
  and, for Claude Code,
  [Automatic model fallback](https://code.claude.com/docs/en/model-config#automatic-model-fallback).
- **As of**: 2026-10-10
- **Recheck trigger**: the fallback section naming this model as a source, or a refusal category
  added or removed for it.

## Caching and cost

Our decision: the playbook's prompt-caching chapter
(`${CLAUDE_PLUGIN_ROOT}/reference/prompt-caching.md`) owns caching mechanisms, and this repository
states no prices (see the cost-claims rule). `[CC: direct]`

Trigger: before counting on cache hits or token counts in API code you author for this model, or
before sending it a long prompt where cost matters, read the pointers. `[CC: API-side]`
`[CC: direct]`

- **Pointer**: see
  [Cache limitations](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#cache-limitations),
  [Same text counts as more tokens](https://platform.claude.com/docs/en/models/haiku-5-5/whats-new-haiku-5-5#same-text-counts-as-more-tokens),
  and
  [Haiku 5.5 context window and pricing](https://code.claude.com/docs/en/model-config#haiku-5-5-context-window-and-pricing).
- **As of**: 2026-10-10
- **Recheck trigger**: any pointed section moving.

## Sources

Our reads, recorded so a re-read can tell whether a page moved:

- The guide, raw `.md` read 2026-10-10 (15,006 B, MD5 `f4f01a9a753158e0fd657c7ff4de7a48`).
- <https://platform.claude.com/docs/en/models/haiku-5-5/whats-new-haiku-5-5> (12,830 B, MD5
  `67e91938ac29b731ef73647ff71b6e1f`) and
  <https://platform.claude.com/docs/en/models/haiku-5-5/migration-guide> (19,755 B, MD5
  `c5f7a69b12cebfac99a7ec02e14f2691`), read 2026-10-10.
- <https://platform.claude.com/docs/en/about-claude/models/overview> and
  <https://platform.claude.com/docs/en/about-claude/models/choosing-a-model>, read 2026-10-10.
- <https://code.claude.com/docs/en/model-config> (116,499 B, MD5
  `86ee02d08683a5b8696a4b41fb206fef`) and <https://code.claude.com/docs/en/sub-agents>, read
  2026-10-10.

Recheck trigger for the whole chapter: a later Haiku release, or a pointed section moving.
