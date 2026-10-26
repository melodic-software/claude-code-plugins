# Request assembly, prompt caching and API cost, for integrations you author

Practices for code that calls the Claude API directly: how the `messages` array is assembled and
carried across turns, cache hygiene, model and effort choice, and the cost levers around them.
Claude Code sessions get most of this from the harness; these rows bite when your code builds the
request itself (an Agent SDK fleet, a service calling the Messages API, an eval harness).
Session-side counterparts are cross-referenced at the end.

Each section is our practice, followed by a pointer to the page section that explains why and
holds the current specifics. Beta features name their beta explicitly; a beta header is part of
the request contract, not decoration. Current prices, model IDs, limits and TTL values resolve
through the pricing page or the bundled `claude-api` skill at the moment of use; this chapter
carries practices, not numbers, and it is the routing surface the fable-5 skill's Boundary section
names for API-side mechanisms. The pages behind the pointers were re-read 2026-10-26 through the
docs lookup at the raw `.md` channel, every pointed heading present; each section below carries
its own recheck trigger.

## Conversation history

Treat the conversation history as append-only: an assistant turn is echoed back whole, its
thinking blocks with it, and nothing before the newest message is rewritten between requests,
the top-level system prompt and the tool list included. A change of instructions rides in a
system entry inside `messages`, a reminder that should expire in a turn-scoped one, and trimming
is delegated to the server's compaction or context editing rather than done by hand. On a model
switch, send the thinking blocks on unchanged and let the API decide what the new model can
read. On models that retain prior-turn thinking, count it in the token and cost estimate.

- **Pointer**: for append-only history on the current frontier model, see
  [Keep the conversation history append-only](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5-1#keep-the-conversation-history-append-only);
  for the prefix check, its account scope, and which models read whose blocks, see
  [Preserved thinking](https://platform.claude.com/docs/en/build-with-claude/thinking#preserved-thinking);
  for retention by model and the billing it implies, see
  [Thinking block preservation by model](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-block-preservation-by-model)
  and [Thinking and the context window](https://platform.claude.com/docs/en/build-with-claude/thinking#thinking-and-the-context-window).
- **As of**: 2026-10-26
- **Recheck trigger**: a re-read of a pointed section no longer supporting the practice above, or
  an API release note touching this topic.

## Forced tool use

We do not force `tool_choice` in integrations we author. Where a call must happen, `auto` with a
prompt instruction, strict tool use for schema-valid inputs, or structured outputs for a fixed
shape takes its place. The page's per-model table says which models reject a forced choice; an
older integration that still forces one is moved to those alternatives, not kept where the table
happens to allow it.

- **Pointer**: for which models reject a forced choice and what to use instead, see
  [Forcing tool use](https://platform.claude.com/docs/en/agents-and-tools/tool-use/define-tools#forcing-tool-use)
  and
  [Response prefill and forced tool use](https://platform.claude.com/docs/en/build-with-claude/thinking#response-prefill-and-forced-tool-use).
- **As of**: 2026-10-26
- **Recheck trigger**: a re-read of either section no longer supporting the practice above, or
  an API release note touching this topic.

## Prefix stability

Lay the request out stable-first: tool definitions and system prompt ahead, the growing
conversation behind. Keep volatile values, such as a timestamp or a request ID, out of the prefix
or move them into the newest message, and keep tool definitions in a fixed order. Do not switch
models mid-conversation where the cache matters.

- **Pointer**: for the prefix order, see
  [Structuring your prompt](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#structuring-your-prompt);
  for model changes and the cache, see
  [Cache miss reason types](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics#cache-miss-reason-types).
- **As of**: 2026-10-26
- **Recheck trigger**: a re-read of a pointed section no longer supporting the practice above, or
  an API release note touching this topic.

## Deferred tools

Declare rarely used tools with `defer_loading`, so the cached prefix does not carry them until a
search loads them.

- **Pointer**: for deferred loading and the cache, see
  [defer_loading and cache preservation](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-use-with-prompt-caching#defer-loading-and-cache-preservation).
- **As of**: 2026-10-26
- **Recheck trigger**: a re-read of a pointed section no longer supporting the practice above, or
  an API release note touching this topic.

## Mid-conversation system messages

To change instructions partway through a session on a model that supports it, append a
mid-conversation system message rather than rewriting the original one, so the cached prefix
survives. Check the page's model list before relying on it; on a model it excludes, the
instruction goes in the request's `system` parameter from the first turn, and a later change to
that parameter is accepted as the cache restart and, on a model that binds thinking to the prefix,
the thinking-block invalidation that "Conversation history" describes. Turn-scoped system messages
are a separate beta.

- **Pointer**: for availability and placement, see
  [When to use a mid-conversation system message](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#when-to-use-a-mid-conversation-system-message),
  [Limitations](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#limitations)
  (anchors checked 2026-10-26), and
  [Combining with prompt caching](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#combining-with-prompt-caching).
- **As of**: 2026-10-26
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
  [Change effort mid-conversation](https://platform.claude.com/docs/en/build-with-claude/effort#change-effort-mid-conversation-beta)
  (correlate with Cognition's devin-fusion post, 2026-06-29, for the compaction-moment practice);
  for a Claude Code session, see
  [Changing effort level](https://code.claude.com/docs/en/prompt-caching#changing-effort-level).
- **As of**: 2026-10-26
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
- **As of**: 2026-10-26
- **Recheck trigger**: a re-read of a pointed section no longer supporting the practice above, or
  an API release note touching this topic.

## TTL

Pick a cache TTL longer than the longest wait between an agent's requests, including tool and
subagent time and the time the previous response took to stream. Use the longer TTL tier for loops
with long waits when the extra write cost pays for itself.

- **Pointer**: for TTL values and how they count, see
  [TTL support](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#ttl-support)
  and [1-hour cache duration](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#1-hour-cache-duration);
  for write multipliers, see
  [Prompt caching pricing](https://platform.claude.com/docs/en/about-claude/pricing#prompt-caching).
- **As of**: 2026-10-26
- **Recheck trigger**: a re-read of a pointed section no longer supporting the practice above, or
  an API release note touching this topic.

## Diagnosing misses

Monitor the cache hit rate, and when requests miss, use the cache diagnostics API to find the layer
of the request to stabilize. Read the page for its availability by platform and whether a beta
header is needed before wiring it in.

A Claude Console request-comparison view for the same data is unconfirmed: no docs page we fetched
covers it. Treat it as unconfirmed until a Console-side check or a docs page settles it
(correlate with <https://claude.com/blog/reducing-cost-and-improving-performance-with-claude-platform>).

- **Pointer**: for miss reasons and availability, see
  [How cache diagnostics works](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics#how-cache-diagnostics-works) and
  [Cache miss reason types](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics#cache-miss-reason-types).
- **As of**: 2026-10-26
- **Recheck trigger**: a re-read of a pointed section no longer supporting the practice above, or
  an API release note touching this topic.

## Effort against model choice

Before working an older or smaller model harder, test the current frontier model at lower effort,
and sweep model and effort together on your own evals rather than raising effort first. Run each
setting in its own session, because a top-level effort change breaks the cache (see "Effort and
the cache"). Read a flat score curve across effort levels on a non-saturated eval as a task that
higher effort does not help. Prices and effort availability resolve through the `claude-api` skill
at the moment of use.

- **Pointer**: for trading effort against model choice, see
  [Tune effort](https://platform.claude.com/docs/en/about-claude/models/optimizing-for-cost-and-intelligence#tune-effort)
  (correlate with <https://claude.com/blog/reducing-cost-and-improving-performance-with-claude-platform>,
  whose benchmark comparison is vendor-reported and unreproduced).
- **As of**: 2026-10-26
- **Recheck trigger**: a re-read of that section no longer supporting the practice above.

## Cost levers beyond caching

- **Batch unattended work.** Send anything that does not need an interactive response through the
  Batch API. Pointer: for batch pricing and how it stacks with caching, see
  [Batch processing pricing](https://platform.claude.com/docs/en/about-claude/pricing#batch-processing)
  and
  [Using prompt caching with Message Batches](https://platform.claude.com/docs/en/build-with-claude/batch-processing#using-prompt-caching-with-message-batches).
  As of: 2026-10-26. Recheck trigger: a re-read of either section no longer supporting this row.
- **Profile before trimming.** Use the Usage and Cost Admin API to see where an organization's
  tokens go; an application without an Admin key logs each response's `usage` object instead.
  Pointer: for the Admin API, see
  [Which API do you need](https://platform.claude.com/docs/en/manage-claude/usage-cost-api#which-api-do-you-need).
  As of: 2026-10-26. Recheck trigger: a re-read of that section no longer supporting this row,
  or an API release note touching this topic.
- **Bound output where the task allows.** Constraining an agent's output length is an
  API-request cost lever. It is scope-disjoint from instruction-surface hygiene: a numeric
  output ceiling written into a skill body is an anti-pattern the prompt-audit discipline
  removes, and nothing here licenses one. The lever lives in request configuration and
  task-shaped output constraints, not in standing instruction text.
- **Automation.** When the bundled `claude-api` skill resolves in this session, its
  `cost-optimize` subcommand profiles spend and proposes these levers against an application,
  measuring against an eval when one exists. Wrap or point to it rather than rebuilding the audit;
  it proposes rather than silently applies. The routing between that surface and this playbook is
  the `## Boundary` section in the fable-5 skill body.

## Session-side counterparts

Claude Code owns request assembly in a session, so the session-side versions of these rows live
elsewhere: effort-change cache cost and per-message steering in `docs/plugin-philosophy.md`
under Effort tiers, subagent cache TTL mechanics in the fable-5 pack's
`context/orchestration.md`, session cache-health observability in the `harness-ops` observability
skill, and the byte-identical-prefix rule as it reaches shared-prefix fleets in the
`docs-hygiene` extract-ssot skill's anti-patterns reference.

What a Claude Code session itself does to the cache, and why its usage climbs as it runs, are on
[Actions that invalidate the cache](https://code.claude.com/docs/en/prompt-caching#actions-that-invalidate-the-cache) and [Manage costs: Why usage climbs in a long session](https://code.claude.com/docs/en/costs#why-usage-climbs-in-a-long-session)
(checked 2026-10-26; recheck when either section moves).
