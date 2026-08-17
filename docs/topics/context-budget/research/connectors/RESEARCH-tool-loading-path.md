---
topic: claude-ai-connectors-in-claude-code
section: tool-loading-path
abstract: Connector tools are deferred behind tool search by default — only names and server instructions enter the prefix; ENABLE_TOOL_SEARCH, alwaysLoad, gateway/provider support and CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS decide otherwise.
claims:
  - claim: "By default MCP tool definitions — connectors included — are deferred and excluded from the system-prompt prefix; only tool names and server instructions load at session start."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/mcp.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (mcp page)"
      - url: "https://code.claude.com/docs/en/costs"
        tier: 1
        pool: "Anthropic — code.claude.com docs (costs page)"
      - url: "https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool.md"
        tier: 1
        pool: "Anthropic — platform.claude.com API docs (different docs property and different authoring surface)"
  - claim: "ENABLE_TOOL_SEARCH takes exactly five forms — unset, true, auto, auto:N, false — where auto/auto:N load upfront below an N% (default 10%) context-window threshold and false loads everything upfront."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/env-vars.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (env-vars page)"
      - url: "https://code.claude.com/docs/en/agent-sdk/tool-search"
        tier: 1
        pool: "Anthropic — code.claude.com docs (agent-sdk page)"
  - claim: "A per-server alwaysLoad: true forces every tool from that server into context at session start regardless of ENABLE_TOOL_SEARCH."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/mcp.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (mcp page)"
      - url: "https://code.claude.com/docs/en/prompt-caching.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (prompt-caching page)"
  - claim: "Deferral is force-disabled — all tools load upfront — on Microsoft Foundry deployments hosted on Azure, on Google Cloud Agent Platform models earlier than the Claude 4.5 generation, when ANTHROPIC_BASE_URL points to a non-first-party host, and when CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS is set."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/agent-sdk/tool-search"
        tier: 1
        pool: "Anthropic — code.claude.com docs (agent-sdk page)"
      - url: "https://code.claude.com/docs/en/env-vars.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (env-vars page)"
      - url: "https://code.claude.com/docs/en/feature-availability.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (feature-availability page)"
produced_by: phase-1-2-3
---

# Q2 — How does a connector's tool surface reach the model?

**Answer: deferred behind tool search by default — the definitions are excluded from the
system-prompt prefix, and only names plus server instructions load at startup.** Four documented
conditions flip it back to upfront loading.

There is nothing connector-specific in this path. Connectors are subject to the *same* tool-search
mechanism as every other MCP server; the docs say tool search "applies to all registered tools."

## The default

<https://code.claude.com/docs/en/mcp.md> § *Scale with MCP tool search*, fetched 2026-08-17:

> Tool search keeps MCP context usage low by deferring tool definitions until Claude needs them.
> Only tool names and server instructions load at session start, so adding more MCP servers has
> minimal impact on your context window. Claude Code doesn't impose a fixed per-server tool cap; the
> practical limit is your context window budget.

and:

> Tool search is enabled by default. MCP tools are deferred rather than loaded into context upfront,
> and Claude uses a search tool to discover relevant ones when a task needs them. Only the tools
> Claude actually uses enter context.

<https://code.claude.com/docs/en/costs>, fetched 2026-08-17, restates it in the cost-reduction
context that matters most to the skill:

> MCP tool definitions are [deferred by default](/docs/en/mcp#scale-with-mcp-tool-search), so only
> tool names enter context until Claude uses a specific tool. Run `/context` to see what's consuming
> space.

## The API-level mechanism (the load-bearing detail)

The deepest rung reached for this claim is the platform API reference,
<https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool.md>, fetched
2026-08-17:

> Internally, the API excludes deferred tools from the system-prompt prefix. When Claude discovers a
> deferred tool through tool search, the API appends a `tool_reference` block inline in the
> conversation, then expands it into the full tool definition before passing it to Claude. The
> prefix is untouched, so prompt caching is preserved.

And a point the skill must not get wrong:

> You still send every tool's full definition in the `tools` array on every request, including the
> deferred ones. The API needs them server-side to run the search and expand `tool_reference`
> blocks.

**So "deferred" means excluded from the model's context, not omitted from the wire.** A skill that
claims disabling a connector reduces *request bytes* would be wrong; it reduces *context-window
occupancy* and, once loaded, prefix size. State it as context, not bandwidth.

## What determines which — the four documented overrides

### 1. `ENABLE_TOOL_SEARCH`

Exact value table from <https://code.claude.com/docs/en/agent-sdk/tool-search>, fetched 2026-08-17,
corroborated verbatim by the `ENABLE_TOOL_SEARCH` row in
<https://code.claude.com/docs/en/env-vars.md>:

| Value | Behavior |
|---|---|
| (unset) | Tool search on; definitions deferred. Falls back to upfront on pre-4.5 Agent Platform models, a non-first-party `ANTHROPIC_BASE_URL`, or Microsoft Foundry on Azure |
| `true` | Always on, except those same exceptions; sends the beta header through proxies |
| `auto` | Counts deferrable tool-definition tokens against the context window; **tool search activates when they reach 10%**. Below that, everything loads upfront |
| `auto:N` | Same with a custom percentage — `auto:5` activates at 5% |
| `false` | Off. All tool definitions load into context on every turn |

Note the direction carefully — it is easy to invert. Under `auto`, **small tool sets load upfront**
and deferral only kicks in past the threshold. The `mcp` page states the same thing from the other
side: "Claude Code then loads every schema upfront while the definitions it would otherwise defer
total less than 10% of the context window, and defers every one of those definitions once they reach
10%."

The threshold is combined across sources, not per-server:

> When you use `auto`, the SDK counts every definition that tool search can defer toward one
> combined threshold: each MCP tool that isn't marked `alwaysLoad`, from any server, plus the
> built-in tools that load on demand. The SDK always loads core built-in tools such as Bash, Read,
> and Edit upfront and doesn't count them toward the threshold.

### 2. `alwaysLoad` — a per-server opt out of deferral

<https://code.claude.com/docs/en/mcp.md> § *Exempt a server from deferral*, fetched 2026-08-17:

> If a server's tools should always be visible to Claude without a search step, set `alwaysLoad` to
> `true` in that server's configuration. Every tool from that server then loads into context at
> session start regardless of the `ENABLE_TOOL_SEARCH` setting.

For the skill: `alwaysLoad` is the single highest-leverage per-server context cost, because it is
the one setting that unconditionally puts a whole server's schemas in the prefix. **Whether a
claude.ai connector can carry `alwaysLoad` is unverified** — the docs show it as a `.mcp.json` field
and connectors have no local config file the user edits. See `RESEARCH-gaps-and-unverified.md`.

### 3. Provider / gateway support

From <https://code.claude.com/docs/en/agent-sdk/tool-search> and
<https://code.claude.com/docs/en/feature-availability.md>, both fetched 2026-08-17: deferral is
unavailable and everything loads upfront on Microsoft Foundry deployments hosted on Azure (rejected
server-side, `ENABLE_TOOL_SEARCH` cannot override), on Google Cloud Agent Platform models earlier
than the Claude 4.5 generation, and by default when `ANTHROPIC_BASE_URL` points at a non-first-party
host.

### 4. `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS`

From <https://code.claude.com/docs/en/env-vars.md>, fetched 2026-08-17:

> Set to `1` to strip Anthropic-specific `anthropic-beta` request headers and beta tool-schema fields
> (such as `defer_loading` and `eager_input_streaming`) from API requests. … MCP tool search is
> disabled and all MCP tools load upfront, even when you set `ENABLE_TOOL_SEARCH`. On Claude Code
> v2.1.227 or later, managed settings can keep tool search on.

**This is the trap for a context-trimming skill.** An organization that sets this variable for
gateway compatibility silently converts every connector from a ~name-sized cost into a full-schema
prefix cost, and `ENABLE_TOOL_SEARCH` will not save them. The skill should detect this variable and
report it as a context-cost multiplier.
