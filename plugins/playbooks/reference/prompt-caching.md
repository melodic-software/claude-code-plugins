# Prompt caching and API cost, for integrations you author

Practices for code that calls the Claude API directly: request assembly, cache hygiene, and the
cost levers around them. Claude Code sessions get most of this from the harness; these rows bite
when your code builds the request itself (an Agent SDK fleet, a service calling the Messages API,
an eval harness). Session-side counterparts are cross-referenced at the end.

Every claim below was verified against the named live page on 2026-09-09. Shared recheck trigger:
a re-fetch of the named page diverging from the row, or an API release note touching prompt
caching, effort, batching, or the Admin API. Beta rows name their beta explicitly; a beta header
is part of the request contract, not decoration. Current prices and model lists resolve through
the pricing page or the bundled `claude-api` skill at the moment of use; this chapter carries
mechanisms, not numbers.

## Prefix stability

Cache reads require byte-identical prefix segments, and the cache is per-model. Anything volatile
in the prefix (a timestamp or request ID in the system prompt, tool definitions that reorder
themselves) breaks every request's cache behind it. Tool definitions render at the top of the
assembled prompt, so a tool-definition change invalidates everything.
(Basis: `platform.claude.com/docs/en/build-with-claude/prompt-caching#structuring-your-prompt`.)

Lay the request out stable-first: tool definitions and system prompt ahead, the growing
conversation behind. Keep volatile values out of the prefix or move them into the newest message.

## Deferred tools

Declare rarely used tools with `defer_loading`: they stay out of the cached prefix and append
into the conversation via tool search only when looked up, so the prefix is untouched and caching
is preserved.
(Basis: `docs/en/agents-and-tools/tool-use/tool-use-with-prompt-caching#defer-loading-and-cache-preservation`.)

## Mid-conversation system messages

Certain models accept a system instruction as a message mid-conversation instead of an edit to
the system prompt, which preserves the cached prefix. GA on six models (Fable 5.1, Mythos 5.1,
Fable 5, Mythos 5, Opus 4.8, Opus 5); not available on Sonnet 5. Turn-scoped system messages are
a separate beta.
(Basis: `docs/en/build-with-claude/mid-conversation-system-messages`.)

## Effort and the cache

Top-level effort renders into the prompt ahead of content, so it is part of the cached prefix and
changing it recomputes the request. Per-message effort changes preserve the cache, as a beta on
Fable 5.1, Mythos 5.1, and Opus 5 only; other models, Fable 5 included, return a 400 for the
per-message form. Batch model or effort changes into moments the cache is already broken, such as
compaction, since those rewrite most of the conversation anyway.
(Basis: `docs/en/build-with-claude/effort#change-effort-mid-conversation-beta`; the
compaction-moment practice is corroborated by Cognition's devin-fusion post, 2026-06-29.)

## Breakpoints and pre-warming

Automatic caching moves the cache point forward to the last cacheable block as the conversation
grows, so long-lived conversations do not strand their breakpoint at the start.
(Basis: `docs/en/build-with-claude/prompt-caching#automatic-caching`.)

To cut first-request latency, pre-warm: send the assembled prefix with `max_tokens: 0` and an
explicit cache breakpoint, using the same effort as real traffic, while the user is still typing.
The request writes the cache without generating. The pre-warm form is rejected with streaming,
extended thinking, structured outputs, forced `tool_choice`, and batches.
(Basis: the prompt-caching page and the bundled `claude-api` skill's caching reference.)

## TTL

The default cache TTL is short and counts from the START of the request, so an agent that blocks
on tool calls or subagents longer than the TTL loses the parent cache before the result returns.
The longer TTL tier costs a higher write multiplier and pays for itself on long-blocking loops.
Current TTL values and write multipliers resolve from the pricing and prompt-caching pages.
(Basis: `docs/en/build-with-claude/prompt-caching#ttl-support` and `docs/en/about-claude/pricing`.)

## Diagnosing misses

The cache diagnostics API (beta) reports why requests missed: `messages_changed`,
`system_changed`, `tools_changed`, `model_changed`, and where two requests diverged. Monitor the
hit rate; a miss reason names the layer of the request to stabilize.
(Basis: `docs/en/build-with-claude/cache-diagnostics`.)

The vendor also describes a Claude Console request-comparison view for the same data; that half
is unverified here (no fetched doc describes it). Treat it as unconfirmed until a Console-side
check or a docs page settles it.

## Cost levers beyond caching

- **Batch unattended work.** The Batch API discounts input and output, and the discount stacks
  with cache multipliers. Anything that does not need an interactive response is a candidate.
  (Basis: `docs/en/build-with-claude/batch-processing` and the pricing page's batch table.)
- **Profile before trimming.** The Usage and Cost Admin API reports where an organization's
  tokens go; an application without an Admin key can log each response's `usage` object instead.
  (Basis: `docs/en/manage-claude/usage-cost-api`.)
- **Bound output where the task allows.** Constraining an agent's output length is an
  API-request cost lever. It is scope-disjoint from instruction-surface hygiene: a numeric
  output ceiling written into a skill body is an anti-pattern the prompt-audit discipline
  removes, and nothing here licenses one. The lever lives in request configuration and
  task-shaped output constraints, not in standing instruction text.
- **Automation.** When the bundled `claude-api` skill resolves in your session, its
  `cost-optimize` subcommand profiles spend and proposes these levers against an application,
  measuring against an eval when one exists. Wrap or point to it rather than rebuilding the audit;
  it proposes rather than silently applies. The routing between that surface and this playbook is
  the `## Boundary` section in the fable-5 skill body.

## Session-side counterparts

Claude Code owns request assembly in a session, so the session-side versions of these rows live
elsewhere: effort-change cache cost and per-message steering in `docs/plugin-philosophy.md`
under Effort tiers, subagent cache TTL mechanics in the fable-5 pack's
`context/orchestration.md`, session cache-health observability in the `claude-ops` observability
skill, and the byte-identical-prefix rule as it reaches shared-prefix fleets in the
`docs-hygiene` extract-ssot skill's anti-patterns reference.
