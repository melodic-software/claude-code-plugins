---
topic: claude-ai-connectors-in-claude-code
section: prompt-cache
abstract: Official and specific — deferred connector tools never enter the cached prefix so connect/disconnect is cache-safe, but any connector whose tools load upfront invalidates the entire cache on every change.
claims:
  - claim: "Tool definitions sit in the system-prompt layer, so the cache invalidates when the set of loaded tool definitions changes between turns."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/prompt-caching.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (prompt-caching page)"
      - url: "https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool.md"
        tier: 1
        pool: "Anthropic — platform.claude.com API docs"
  - claim: "When tools are deferred (the default), a server connecting, disconnecting or changing its tool list only appends content and does not disturb the cached prefix."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/prompt-caching.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (prompt-caching page)"
      - url: "https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool.md"
        tier: 1
        pool: "Anthropic — platform.claude.com API docs"
  - claim: "When tools are loaded into the prefix, any change to them invalidates the whole cache, and this can happen with no user action via process exit, session expiry, automatic reconnection, or a dynamic tool update."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/prompt-caching.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (prompt-caching page)"
  - claim: "A deny rule matching only MCP tools, such as \"mcp__*\", removes those tools but leaves the cache intact when they are deferred, because deferred definitions were never in the cached prefix."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/prompt-caching.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (prompt-caching page)"
produced_by: phase-2-4
---

# Q6 — Anything official about connectors and prompt-cache invalidation?

**Yes — there is a dedicated, unusually specific section, and it is conditional on the deferral state
from Q2.** This is the best-documented of the six questions.

## The layer model

<https://code.claude.com/docs/en/prompt-caching.md>, fetched 2026-08-17:

| Layer | Content | Changes when |
|---|---|---|
| System prompt | Core instructions, **tool definitions**, output style | The set of loaded tool definitions changes, or Claude Code is upgraded |
| Project context | CLAUDE.md, auto memory, unscoped rules | Session starts, or after `/clear` or `/compact` |
| Conversation | Your messages, Claude's responses, tool results | Every turn |

> A change to the conversation layer leaves the system prompt and project context cached. A change to
> the system prompt invalidates everything, because all later content now sits behind a different
> prefix.

## The connector-relevant section, verbatim

Same page, § *Connecting or disconnecting an MCP server* — this governs connectors, which are MCP
servers:

> Tool definitions sit in the system prompt layer, so the cache invalidates when the set of tool
> definitions in the request changes between turns. Toggling the [advisor tool](/docs/en/advisor) is
> an exception: its definition sits after the cache breakpoint, so enabling or disabling `/advisor`
> keeps the cached prefix intact. Whether an [MCP server](/docs/en/mcp) change does this depends on
> whether its tools are deferred by [tool search](/docs/en/mcp#scale-with-mcp-tool-search) or loaded
> into the prefix:
>
> - **Deferred tools**, the default on supported models: a server connecting, disconnecting, or
>   changing its tool list only appends new content and doesn't disturb anything already cached.
> - **Tools loaded into the prefix**: any change to them invalidates the cache. This happens when
>   tool search is unavailable or disabled, such as on Google Cloud's Agent Platform models earlier
>   than the Claude 4.5 generation, with a custom `ANTHROPIC_BASE_URL` gateway, or on a Microsoft
>   Foundry deployment hosted on Azure once Claude Code detects that the deployment rejects tool
>   search. It also happens for a server or tool marked `alwaysLoad`, and for definitions kept
>   upfront by threshold-based loading.
>
> When tools load into the prefix, the most common cause of an invalidation is a server connecting or
> disconnecting mid-session, which can happen without any action on your part: a stdio server's
> process exits, an HTTP session expires, or a server reconnects automatically after a transient
> failure. A connected server can also push a dynamic tool update that changes its tool list.
>
> Editing your MCP config does not by itself change the cache. The new config takes effect only after
> a restart, which is when the server connects or disconnects.

## The API-level reason it is cache-safe when deferred

<https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool.md>, fetched
2026-08-17 — an independent docs property confirming the mechanism rather than just the outcome:

> Internally, the API excludes deferred tools from the system-prompt prefix. When Claude discovers a
> deferred tool through tool search, the API appends a `tool_reference` block inline in the
> conversation, then expands it into the full tool definition before passing it to Claude. **The
> prefix is untouched, so prompt caching is preserved.**

## The permission-rule interaction

Directly relevant to a trimming skill that might reach for deny rules:

> Adding a bare tool name like `Bash` or `WebFetch` as a deny rule removes that tool from Claude's
> context entirely. Built-in tool definitions load into the system prompt layer, so adding or
> removing one of these rules mid-session invalidates the cache. …
>
> Only a deny rule that matches in the tool-name position has this effect: a bare tool name, the
> equivalent `Bash(*)` form, or a tool-name glob like `"*"`. **A glob that matches only MCP tools,
> such as `"mcp__*"`, removes those tools the same way but leaves the cache intact when the matched
> tools are deferred, the default, since deferred definitions were never in the cached prefix.**
> Scoped deny rules like `Bash(rm *)`, and all allow and ask rules, don't change which tools Claude
> sees.

**This gives the skill a genuinely cheap connector-suppression primitive**: an `mcp__claude_ai_*`
deny rule removes connector tools from Claude's view without a cache penalty in the default deferred
configuration — and unlike `disableClaudeAiConnectors`, deny rules are explicitly in the set of keys
that reload live. It suppresses the *tools*, not the connection, so it does not stop the startup
fetch. It is a context-surface control, not a network control. **The exact glob behavior against the
`mcp__claude_ai_<connector>__` namespace is not separately documented and I did not verify it
empirically** — see `RESEARCH-gaps-and-unverified.md`.

## Also cache-relevant

- **Plugin-provided MCP servers** follow the identical rule: "the cache survives when the server's
  tools are deferred, and the next request re-reads the entire conversation when they load into the
  prefix."
- **Upgrades**: "A new Claude Code version typically updates the system prompt or tool definitions,
  so the first request after an upgrade rebuilds the cache from the top."
- **Cache lifetime** (from <https://code.claude.com/docs/en/costs>): one hour on a subscription,
  dropping to five minutes once drawing on usage credits; five minutes on API key or cloud provider.
  `ENABLE_PROMPT_CACHING_1H=1` keeps the one-hour lifetime while on usage credits.

## Bottom line for the skill

In the **default** configuration, connectors are close to cache-neutral: their definitions are never
in the prefix, so connecting, disconnecting, and disabling them do not invalidate anything. The
cache story only becomes expensive in exactly the configurations where connectors also become
context-expensive — `alwaysLoad`, `ENABLE_TOOL_SEARCH=false`, `auto` below threshold, gateway
`ANTHROPIC_BASE_URL`, `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS`, Foundry-on-Azure, pre-4.5 Agent
Platform. **The same switch controls both costs**, which is the cleanest thing the skill can tell a
user.
