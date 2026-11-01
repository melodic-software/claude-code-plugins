# Prompt caching and API cost, for integrations you author

Practices for code that calls the Claude API directly: request assembly, cache hygiene, and the
cost levers around them. Claude Code sessions get most of this from the harness; these rows bite
when your code builds the request itself (an Agent SDK fleet, a service calling the Messages API,
an eval harness). Session-side counterparts are cross-referenced at the end.

Each section is our practice, followed by a pointer to the page section that explains why and
holds the current specifics. Beta features name their beta explicitly; a beta header is part of
the request contract, not decoration. Current prices, model lists, and TTL values resolve through
the pricing page or the bundled `claude-api` skill at the moment of use; this chapter carries
practices, not numbers. The pages behind the pointers were re-read whole on 2026-11-01 through
the docs lookup; each section below carries its own recheck trigger.

## Prefix stability

Lay the request out stable-first: tool definitions and system prompt ahead, the growing
conversation behind. Keep volatile values, such as a timestamp or a request ID, out of the prefix
or move them into the newest message, and keep tool definitions in a fixed order. Do not switch
models mid-conversation where the cache matters.

- **Pointer**: for the prefix order, see
  [Structuring your prompt](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#structuring-your-prompt);
  for model changes and the cache, see
  [Cache miss reason types](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics#cache-miss-reason-types).
- **As of**: 2026-11-01
- **Recheck trigger**: a re-read of a pointed section no longer supporting the practice above, or
  an API release note touching this topic.

## Deferred tools

Declare rarely used tools with `defer_loading`, so the cached prefix does not carry them until a
search loads them.

- **Pointer**: for deferred loading and the cache, see
  [defer_loading and cache preservation](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-use-with-prompt-caching#defer-loading-and-cache-preservation).
- **As of**: 2026-11-01
- **Recheck trigger**: a re-read of a pointed section no longer supporting the practice above, or
  an API release note touching this topic.

## Mid-conversation system messages

To change instructions partway through a session on a model that supports it, append a
mid-conversation system message rather than rewriting the original one, so the cached prefix
survives. Check the model and platform list in the page's opening note before relying on it; on a
model it excludes, fall back to the request's `system` parameter. Turn-scoped system messages and
mid-conversation tool changes are each a separate beta, named in that same note.

- **Pointer**: for the model list and the betas, see the note above the first heading of
  [Mid-conversation system messages](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages)
  (the page gives that note no anchor of its own);
  for the cache rationale and placement, see
  [When to use a mid-conversation system message](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#when-to-use-a-mid-conversation-system-message),
  [Limitations](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#limitations), and
  [Combining with prompt caching](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#combining-with-prompt-caching).
- **As of**: 2026-11-01
- **Recheck trigger**: a re-read of a pointed section no longer supporting the practice above, or
  an API release note touching this topic.

## Effort and the cache

Treat a top-level effort change as a cache break. Where the model supports per-message effort,
change effort per message instead, after checking the pointed section's model list.
Batch model or effort changes into moments the cache is already broken, such as compaction, since
those rewrite most of the conversation anyway.

This section covers requests you send through the API; for what an effort change in a Claude Code
session does to the cache, read Claude Code's own page instead of applying this section.

- **Pointer**: for per-message effort and its model list, see
  [Change effort mid-conversation](https://platform.claude.com/docs/en/build-with-claude/effort#change-effort-mid-conversation)
  and its "Per-message effort (beta)" subsection (correlate with Cognition's devin-fusion post,
  2026-06-29, for the compaction-moment practice, which no docs page covers as of 2026-11-01);
  for a Claude Code session, see
  [Changing effort level](https://code.claude.com/docs/en/prompt-caching#changing-effort-level).
- **As of**: 2026-11-01
- **Recheck trigger**: a re-read of a pointed section no longer supporting the practice above, or
  an API release note touching this topic.

## Breakpoints and pre-warming

Use automatic caching for long-lived conversations, so the cache point follows the conversation
instead of staying at its start.

To cut first-request latency, pre-warm: send the assembled prefix with an explicit cache
breakpoint and no generated output, using the same effort as real traffic, while the user is still
typing. Check the page's limitations before combining pre-warming with another request feature.

- **Pointer**: for automatic caching, see
  [Automatic caching](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#automatic-caching);
  for pre-warming and its limitations, see
  [Pre-warming the cache](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#pre-warming-the-cache)
  and the bundled `claude-api` skill's caching reference.
- **As of**: 2026-11-01
- **Recheck trigger**: a re-read of a pointed section no longer supporting the practice above, or
  an API release note touching this topic.

## TTL

Pick a cache TTL longer than the longest wait between an agent's requests, including tool and
subagent time and the time the previous response took to stream. Use the longer TTL tier for loops
with long waits when the extra write cost pays for itself.

- **Pointer**: for how the lifetime is measured, see
  [How prompt caching works](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#how-prompt-caching-works);
  for the TTL values, see
  [TTL support](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#ttl-support)
  and [1-hour cache duration](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#1-hour-cache-duration);
  for write multipliers, see
  [Prompt caching pricing](https://platform.claude.com/docs/en/about-claude/pricing#prompt-caching).
- **As of**: 2026-11-01
- **Recheck trigger**: a re-read of a pointed section no longer supporting the practice above, or
  an API release note touching this topic.

## Diagnosing misses

Monitor the cache hit rate, and when requests miss, use the cache diagnostics API to find the layer
of the request to stabilize. Read the page's limitations for its availability by platform and its
retention window before wiring it in.

A Claude Console request-comparison view for the same data: no docs page covers one as of
2026-11-01 (correlate with
<https://claude.com/blog/reducing-cost-and-improving-performance-with-claude-platform>); recheck
trigger: a docs page covering a Console view of cache diagnostics, at which point the pointer
moves there.

- **Pointer**: for the mechanism, miss reasons, and availability, see
  [How cache diagnostics works](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics#how-cache-diagnostics-works),
  [Cache miss reason types](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics#cache-miss-reason-types), and
  [Limitations](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics#limitations).
- **As of**: 2026-11-01
- **Recheck trigger**: a re-read of a pointed section no longer supporting the practice above, or
  an API release note touching this topic.

## Cost levers beyond caching

- **Batch unattended work.** Send anything that does not need an interactive response through the
  Batch API. Pointer: for batch pricing, see
  [Batch processing pricing](https://platform.claude.com/docs/en/about-claude/pricing#batch-processing);
  for how the batch discount stacks with caching, see
  [Using prompt caching with Message Batches](https://platform.claude.com/docs/en/build-with-claude/batch-processing#using-prompt-caching-with-message-batches).
  As of: 2026-11-01. Recheck trigger: a re-read of either section no longer supporting this row.
- **Profile before trimming.** Use the organization's usage and cost API to see where its tokens
  go, picking the API the page recommends for the organization's product; an application without
  an Admin key logs each response's `usage` object instead. Pointer: for which API to use, see
  [Which API do you need](https://platform.claude.com/docs/en/manage-claude/usage-cost-api#which-api-do-you-need).
  As of: 2026-11-01. Recheck trigger: a re-read of that section no longer supporting this row,
  or an API release note touching this topic.
- **Bound output where the task allows.** Constraining an agent's output length is an
  API-request cost lever. It is scope-disjoint from instruction-surface hygiene: a numeric
  output ceiling written into a skill body is an anti-pattern the prompt-audit discipline
  removes, and nothing here licenses one. The lever lives in request configuration and
  task-shaped output constraints, not in standing instruction text. When one request asks for a
  long deliverable at a high effort level, size `max_tokens` for the thinking and the reply
  together and steer the request with the note at the pointer rather than a ceiling in a
  standing instruction. Pointer: for long outputs at the top effort levels, see
  [Leave room for long outputs at xhigh and max effort](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#leave-room-for-long-outputs-at-xhigh-and-max-effort).
  As of: 2026-11-01. Recheck trigger: a re-read of that section no longer supporting this row.
- **Automation.** When the bundled `claude-api` skill resolves in this session, its
  `cost-optimize` subcommand profiles spend and proposes these levers against an application,
  measuring against an eval when one exists. Wrap or point to it rather than rebuilding the audit;
  it proposes rather than silently applies. The routing between that surface and this playbook is
  the `## Boundary` section in the fable-5 skill body.

## Request assembly

Practices for the `messages` array itself, where our code builds it. Which models each practice
binds on resolves at the pointers, never here; the practice is written so one request body works
across models.

- **Keep the history append-only.** Send every assistant turn back exactly as returned, thinking
  blocks included, and add new messages only at the end. A reminder that holds for one turn goes
  in as a turn-scoped system message, or as a text block beside that turn's tool results, and
  every earlier copy stays where it was sent. A new instruction or a tool change goes in as a
  mid-conversation system message; the top-level `system` and `tools` fields are frozen at
  session start. Trimming belongs to the server (compaction, context editing); a client-side
  compaction keeps nothing of the old transcript except its summary. We treat any edit to an
  earlier turn as a cache break and as the loss of every later thinking block; which models
  enforce the second resolves at the Preserved thinking pointer.
- **Force a tool only on a model whose row accepts it.** Where the forcing-tool-use table rejects
  `any` and `tool`, name the tool in the prompt under `auto`, use strict tool use for schema-valid
  arguments, or structured outputs for a fixed JSON shape.
- **Pass thinking blocks back unchanged across a model switch**, and let the API decide which
  blocks the target reads; strip none yourself. What a dropped block costs, and whether a stripped
  one errors, resolve at the preservation pointer.
- **Budget prior-turn thinking** in token and cost estimates on the models that keep every turn's
  thinking in context.
- **Sweep model and effort together** before working an older model harder: test the newer model
  at a lower effort level on your own evals first, and read a flat cost-against-quality curve across
  effort levels as a task that more effort does not help.

- **Pointer**: for append-only history, see
  [Keep the conversation history append-only](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#keep-the-conversation-history-append-only)
  and [Preserved thinking](https://platform.claude.com/docs/en/build-with-claude/thinking#preserved-thinking);
  for which models reject forced tool use and what to use instead, see
  [Forcing tool use](https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools#forcing-tool-use)
  and
  [Response prefill and forced tool use](https://platform.claude.com/docs/en/build-with-claude/thinking#response-prefill-and-forced-tool-use);
  for which models keep prior thinking and read which blocks, see
  [Thinking block preservation by model](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-block-preservation-by-model);
  for trading effort against model choice, see
  [Tune effort](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence#tune-effort)
  (correlate with <https://claude.com/blog/reducing-cost-and-improving-performance-with-claude-platform>,
  whose benchmark comparison is vendor-reported and unreproduced).
- **As of**: 2026-11-01
- **Recheck trigger**: a re-read of any pointed section no longer supporting the practice beside
  it, or a model release that changes a row in either table.

## Session-side counterparts

Claude Code owns request assembly in a session, so the session-side versions of these rows live
elsewhere: effort-change cache cost and per-message steering in `docs/plugin-philosophy.md`
under Effort tiers, subagent cache TTL mechanics in the fable-5 pack's
`context/orchestration.md`, session cache-health observability in the `harness-ops` observability
skill, and the byte-identical-prefix rule as it reaches shared-prefix fleets in the
`docs-hygiene` extract-ssot skill's anti-patterns reference.

What a Claude Code session itself does to the cache, and why its usage climbs as it runs, are on
[Actions that invalidate the cache](https://code.claude.com/docs/en/prompt-caching#actions-that-invalidate-the-cache) and [Manage costs: Why usage climbs in a long session](https://code.claude.com/docs/en/costs#why-usage-climbs-in-a-long-session)
(as of 2026-11-01; recheck when either section moves).
