# Prompt caching and API cost, for integrations you author

Practices for code that calls the Claude API directly: request assembly, cache hygiene, and the
cost levers around them. Claude Code sessions get most of this from the harness; these rows bite
when your code builds the request itself (an Agent SDK fleet, a service calling the Messages API,
an eval harness). Session-side counterparts are cross-referenced at the end.

Each section is our practice, followed by a pointer to the page section that explains why and
holds the current specifics. Beta features name their beta explicitly; a beta header is part of
the request contract, not decoration. Current prices, model lists, and TTL values resolve through
the pricing page or the bundled `claude-api` skill at the moment of use; this chapter carries
practices, not numbers. The pages behind the pointers were read 2026-09-28, two identical fetches
of each.

## Prefix stability

Lay the request out stable-first: tool definitions and system prompt ahead, the growing
conversation behind. Keep volatile values, such as a timestamp or a request ID, out of the prefix
or move them into the newest message, and keep tool definitions in a fixed order. Do not switch
models mid-conversation where the cache matters.

- **Pointer**: for the prefix order, see
  [Structuring your prompt](https://platform.claude.com/docs/en/build-with-claude/prompt-caching#structuring-your-prompt);
  for model changes and the cache, see
  [Cache miss reason types](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics#cache-miss-reason-types).
- **As of**: 2026-09-28
- **Recheck trigger**: a re-read of a pointed section no longer supporting the practice above, or
  an API release note touching this topic.

## Deferred tools

Declare rarely used tools with `defer_loading`, so the cached prefix does not carry them until a
search loads them.

- **Pointer**: for deferred loading and the cache, see
  [defer_loading and cache preservation](https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-use-with-prompt-caching#defer-loading-and-cache-preservation).
- **As of**: 2026-09-28
- **Recheck trigger**: a re-read of a pointed section no longer supporting the practice above, or
  an API release note touching this topic.

## Mid-conversation system messages

To change instructions partway through a session on a model that supports it, append a
mid-conversation system message rather than rewriting the original one, so the cached prefix
survives. Check the page's model list before relying on it; on a model it excludes, fall back to
the request's `system` parameter. Turn-scoped system messages are a separate beta.

- **Pointer**: for availability and placement, see
  [Mid-conversation system messages and tool changes](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages)
  and
  [Combining with prompt caching](https://platform.claude.com/docs/en/build-with-claude/mid-conversation-system-messages#combining-with-prompt-caching).
- **As of**: 2026-09-28
- **Recheck trigger**: a re-read of a pointed section no longer supporting the practice above, or
  an API release note touching this topic.

## Effort and the cache

Treat a top-level effort change as a cache break. Where the model supports per-message effort,
change effort per message instead; on a model the beta excludes, the per-message form is an error.
Batch model or effort changes into moments the cache is already broken, such as compaction, since
those rewrite most of the conversation anyway.

- **Pointer**: for per-message effort and its model list, see
  [Change effort mid-conversation](https://platform.claude.com/docs/en/build-with-claude/effort#change-effort-mid-conversation-beta)
  (correlate with Cognition's devin-fusion post, 2026-06-29, for the compaction-moment practice).
- **As of**: 2026-09-28
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
- **As of**: 2026-09-28
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
- **As of**: 2026-09-28
- **Recheck trigger**: a re-read of a pointed section no longer supporting the practice above, or
  an API release note touching this topic.

## Diagnosing misses

Monitor the cache hit rate, and when requests miss, use the cache diagnostics API to find the layer
of the request to stabilize. Read the page for its availability by platform and whether a beta
header is still needed; our 2026-09-28 read found it generally available on the Claude API with the
old beta header no longer required.

A Claude Console request-comparison view for the same data is unconfirmed: no docs page we fetched
covers it. Treat it as unconfirmed until a Console-side check or a docs page settles it
(correlate with <https://claude.com/blog/reducing-cost-and-improving-performance-with-claude-platform>).

- **Pointer**: for miss reasons and availability, see
  [Cache diagnostics](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics) and
  [Cache miss reason types](https://platform.claude.com/docs/en/build-with-claude/cache-diagnostics#cache-miss-reason-types).
- **As of**: 2026-09-28
- **Recheck trigger**: a re-read of a pointed section no longer supporting the practice above, or
  an API release note touching this topic.

## Cost levers beyond caching

- **Batch unattended work.** Send anything that does not need an interactive response through the
  Batch API. Pointer: for batch pricing and how it stacks with caching, see
  [Batch processing pricing](https://platform.claude.com/docs/en/about-claude/pricing#batch-processing)
  and
  [Using prompt caching with Message Batches](https://platform.claude.com/docs/en/build-with-claude/batch-processing#using-prompt-caching-with-message-batches).
  As of: 2026-09-28. Recheck trigger: a re-read of either section no longer supporting this row.
- **Profile before trimming.** Use the Usage and Cost Admin API to see where an organization's
  tokens go; an application without an Admin key logs each response's `usage` object instead.
  Pointer: for the Admin API, see
  [Usage and Cost API](https://platform.claude.com/docs/en/manage-claude/usage-cost-api). As of:
  2026-09-28. Recheck trigger: a re-read of that page no longer supporting this row.
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
