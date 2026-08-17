---
topic: tool-definitions-prefix-pruning
section: deferral-mechanism
abstract: "Tool search is on by default and MCP tools are deferred by default; deferral withholds a definition from the system-prompt prefix but the full schema is still transmitted in the request's tools array on every turn."
claims:
  - claim: "Claude Code's MCP page states MCP tools are deferred by default, verbatim: 'Tool search is enabled by default. MCP tools are deferred rather than loaded into context upfront.'"
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search"
        tier: 1
        pool: "Anthropic / code.claude.com"
      - url: "https://code.claude.com/docs/en/costs#reduce-token-usage"
        tier: 1
        pool: "Anthropic / code.claude.com"
      - url: "https://code.claude.com/docs/en/agent-sdk/tool-search"
        tier: 1
        pool: "Anthropic / code.claude.com"
  - claim: "What the model sees for a deferred tool is its NAME (plus server instructions, and an optional one-line searchHint) — not its description or input schema."
    confidence: HIGH
    tiers: [1, 0]
    sources:
      - url: "https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search"
        tier: 1
        pool: "Anthropic / code.claude.com"
      - url: "https://code.claude.com/docs/en/agent-sdk/typescript"
        tier: 1
        pool: "Anthropic / code.claude.com"
      - url: "session deferred-tool system reminder, Claude Code 2.1.232, captured 2026-08-17"
        tier: 0
        pool: "direct tool output (this session)"
  - claim: "At the API level, defer_loading controls context entry, NOT what is sent: every deferred tool's full definition is still sent in the tools array on every request."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool#deferred-tool-loading"
        tier: 1
        pool: "Anthropic / platform.claude.com"
  - claim: "The API excludes deferred tools from the system-prompt prefix and appends discovered tools inline as tool_reference blocks, leaving the cached prefix untouched."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool"
        tier: 1
        pool: "Anthropic / platform.claude.com"
      - url: "https://platform.claude.com/docs/en/agents-and-tools/tool-use/manage-tool-context"
        tier: 1
        pool: "Anthropic / platform.claude.com"
produced_by: phase-1-2
---

# How deferred tool loading works

## The MCP-page statement, verified and quoted

The topic asked to verify that the MCP page says MCP tools are deferred by default. **It does.**
`https://code.claude.com/docs/en/mcp#scale-with-mcp-tool-search` (fetched 2026-08-17, page `lastmod`
`2026-08-13T23:54:06.784Z`), section *Scale with MCP tool search*:

> Tool search keeps MCP context usage low by deferring tool definitions until Claude needs them.
> **Only tool names and server instructions load at session start**, so adding more MCP servers has
> minimal impact on your context window. Claude Code doesn't impose a fixed per-server tool cap; the
> practical limit is your context window budget.

and, under *How it works*:

> **Tool search is enabled by default. MCP tools are deferred rather than loaded into context
> upfront**, and Claude uses a search tool to discover relevant ones when a task needs them. Only the
> tools Claude actually uses enter context. From your perspective, MCP tools work exactly as before.

Corroborated on a second first-party page, `https://code.claude.com/docs/en/costs#reduce-token-usage`
(fetched 2026-08-17):

> MCP tool definitions are deferred by default, so **only tool names enter context** until Claude
> uses a specific tool. Run `/context` to see what's consuming space.

## What triggers deferral

Deferral is the **default**, not an opt-in. From
`https://code.claude.com/docs/en/agent-sdk/tool-search` (fetched 2026-08-17):

> Tool search is on by default, with the exceptions listed in Configure tool search.

> When it is active, **tool definitions are withheld from the context window.** The agent receives a
> summary of available tools and searches for relevant ones when the task requires a capability not
> already loaded. **Up to five of the most relevant tools are loaded into context by default**, where
> they stay available for subsequent turns. If the conversation is long enough that the SDK compacts
> earlier messages to free space, previously discovered tools may be removed, and the agent searches
> again as needed.

Scope: "Tool search applies to all registered tools, whether they come from remote MCP servers or
custom SDK MCP servers." Built-ins are partly exempt — "The SDK always loads core built-in tools such
as Bash, Read, and Edit upfront and doesn't count them toward the threshold" — but, as
`RESEARCH-tool-inventory.md` records, that exempt set is never enumerated, and this session observed
12 built-in tools sitting in the deferred bucket.

**Documented conditions that turn deferral OFF** (all from the same page and the MCP page):

| Condition | Effect |
|---|---|
| Model on the SDK's unsupported-model list | Definitions loaded upfront; `ENABLE_TOOL_SEARCH` cannot override |
| Google Cloud Agent Platform, models earlier than the Claude 4.5 generation | Upfront; `ENABLE_TOOL_SEARCH=true` cannot override |
| Microsoft Foundry deployment hosted on Azure | Server-side rejection forces upfront; cannot override |
| `ANTHROPIC_BASE_URL` at a non-first-party host | Deferral off by default (most proxies don't forward `tool_reference`); overridable with `ENABLE_TOOL_SEARCH` |
| `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS` set | Tool search off; `ENABLE_TOOL_SEARCH` cannot override (managed settings can, on v2.1.227+) |

Model support requires `tool_reference` blocks: Sonnet 4.5, Haiku 4.5, Opus 4.5 and later
(`https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool#model-compatibility`,
fetched 2026-08-17, which lists Fable 5, Mythos 5, Opus 5, Opus 4.8/4.7/4.6, Sonnet 4.6/4.5,
Haiku 4.5, Opus 4.5).

## What the model sees for a deferred tool: name only

Three independent first-party statements agree, and this session's own surface is a fourth:

1. MCP page: "Only tool names and server instructions load at session start."
2. Costs page: "only tool names enter context until Claude uses a specific tool."
3. TypeScript SDK reference (`https://code.claude.com/docs/en/agent-sdk/typescript`, fetched
   2026-08-17) documents an optional per-tool `extras.searchHint`: "a one-line capability phrase
   **shown in the deferred-tool list** when tool search is active." So the deferred-tool list is
   names, optionally each with a one-line hint — never the description or `input_schema`.
4. **Tier 0, this session:** the deferred-tool system reminder lists 77 bare names under "Their
   schemas are NOT loaded — calling them directly will fail with `InputValidationError`." Calling
   `ToolSearch` with `select:WebFetch,WebSearch` returned the full JSONSchema definitions inline.

The search itself matches on more than the model can see: "Both tool search variants (`regex` and
`bm25`) search tool names, descriptions, argument names, and argument descriptions" — that indexing
runs server-side against definitions the model has not been shown.

## The load-bearing subtlety: deferred ≠ not sent

**This is the finding that most changes what the skill can honestly promise.** From
`https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool#deferred-tool-loading`
(fetched 2026-08-17):

> `defer_loading` controls what enters the context window, not what you send in the request:
>
> - **You still send every tool's full definition in the `tools` array on every request, including
>   the deferred ones.** The API needs them server-side to run the search and expand `tool_reference`
>   blocks.
> - Tools without `defer_loading` load into context immediately.
> - Tools with `defer_loading: true` load only when Claude discovers them through search.
> - Never set `defer_loading: true` on the tool search tool itself.
> - Keep your 3–5 most frequently used tools non-deferred so Claude can call them without searching
>   first.

and:

> **Internally, the API excludes deferred tools from the system-prompt prefix.** When Claude
> discovers a deferred tool through tool search, the API appends a `tool_reference` block inline in
> the conversation, then expands it into the full tool definition before passing it to Claude. **The
> prefix is untouched, so prompt caching is preserved.**

So there are three distinct places a definition can be, and the skill should name them separately:

| Place | Deferred tool | Bare-name-denied tool |
|---|---|---|
| HTTP request body (`tools` array) | **present** | **absent** |
| System-prompt prefix the model reads | absent | absent |
| Billed input tokens | see below | not billed |

Billing: "Tool search isn't metered as a separate server tool. The response's `usage.server_tool_use`
object has no tool search field, and **the tool definitions that search loads into context count as
input tokens like any other tool definition**." Anthropic does not state on that page whether the
*undiscovered* deferred definitions in the `tools` array are billed as input tokens. Claude Code's
own `/context` does attribute a non-zero `System tools (deferred)` bucket (17.8k in this session),
which is consistent with them being sent and counted locally. **Whether the API bills for
undiscovered deferred definitions is UNVERIFIED** — see the gap in `RESEARCH-fetch-log.md`.

## Why this matters to a trimming skill

Deferral is a **context-window** optimization with a **prompt-cache-preserving** design, not a
payload-size optimization. Anthropic quantifies the win as context, not bytes: "Tool search typically
reduces this by over 85 percent, loading only the 3–5 tools Claude needs for a given request", against
a baseline where "A typical multiserver setup (GitHub, Slack, Sentry, Grafana, and Splunk) can consume
~55k tokens in definitions before Claude does any work"
(`tool-search-tool`, fetched 2026-08-17).

A skill that reports "you saved N tokens by deferring" is measuring the context window. A skill that
reports "you removed N tokens from the request" needs the permission-layer removal documented in
`RESEARCH-permission-pruning.md`.
