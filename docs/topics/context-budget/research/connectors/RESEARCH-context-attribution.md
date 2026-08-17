---
topic: claude-ai-connectors-in-claude-code
section: context-attribution
abstract: /context has no connectors row — connectors are folded into the "MCP tools" category (or "MCP tools (deferred)"), with a per-tool breakdown keyed by server under "### MCP Tools" in /context all.
claims:
  - claim: "/context reports categories System prompt, System tools, MCP tools, MCP tools (deferred), System tools (deferred), Custom agents, Memory files, Skills, Messages, Free space, Autocompact buffer — there is no separate Connectors category."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/bin/claude.exe (v2.1.232, strings, offsets ~588427-588442 and ~623489)"
        tier: 0
        pool: "Anthropic — shipped Claude Code binary (implementation artifact)"
      - url: "https://code.claude.com/docs/en/context-window"
        tier: 1
        pool: "Anthropic — code.claude.com docs (context-window page)"
  - claim: "The MCP tools row in /context carries a /mcp action hint and an on-demand marker, and distinguishes Loaded from Available tools."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/bin/claude.exe (v2.1.232, strings, offset ~623489)"
        tier: 0
        pool: "Anthropic — shipped Claude Code binary (implementation artifact)"
  - claim: "/context all expands into per-item tables including '### MCP Tools' with columns Tool | Server | Tokens, which is where a connector is identifiable by its server name."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/bin/claude.exe (v2.1.232, strings, offset ~577380)"
        tier: 0
        pool: "Anthropic — shipped Claude Code binary (implementation artifact)"
      - url: "https://code.claude.com/docs/en/commands.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (commands page)"
  - claim: "/usage, separately from /context, attributes recent usage to individual MCP servers as a percentage of total."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/costs"
        tier: 1
        pool: "Anthropic — code.claude.com docs (costs page)"
produced_by: phase-2-4
---

# Q3 — What does `/context` attribute connectors to?

**Answer: the `MCP tools` category — or `MCP tools (deferred)` when they are deferred, which is the
default. There is no `Connectors` row.** A connector is only distinguishable at the `/context all`
level, by its server name in the per-tool table.

## Tier-0 evidence from the shipped binary

The strongest evidence here is not documentation: it is the category labels in the installed
Claude Code v2.1.232 binary at
`node_modules/@anthropic-ai/claude-code/bin/claude.exe`, read 2026-08-17. The `/context` renderer's
label block sits at string offset ~588427 as a contiguous cluster:

```
System prompt
promptBorder
System tools
inactive
MCP tools
cyan_FOR_SUBAGENTS_ONLY
MCP tools (deferred)
System tools (deferred)
Custom agents
permission
Memory files
claude
Skills
warning
auto
Messages
purple_FOR_SUBAGENTS_ONLY
```

Immediately above it are the destructuring-error strings that name the renderer's own token fields,
which is independent confirmation this is the `/context` computation and not an unrelated table:

```
Cannot destructure property 'systemPromptTokens' …
Cannot destructure property 'claudeMdTokens' …
Cannot destructure property 'builtInToolTokens' …
Cannot destructure property 'mcpToolTokens' …
Cannot destructure property 'agentTokens' …
Cannot destructure property 'slashCommandTokens' …
```

**`mcpToolTokens` is the field a connector's cost lands in.** There is no `connectorTokens` field
and no `Connectors` label anywhere in the binary — a targeted search for the exact string
`Connectors` as a standalone label returned zero matches, while `MCP tools` returned matches in both
`/context` code regions.

A second cluster at ~623489 shows the row's presentation:

```
MCP tools
 /mcp
 (loaded on-demand)
tool
Loaded
tree
Available
Custom agents
 .claude/agents/
agent
Memory files
 /memory
file
Skills
 /skills
skill
/context all to expand
```

So the `MCP tools` row renders with `/mcp` as its remediation hint, marks deferred definitions
`(loaded on-demand)`, and reports `Loaded` versus `Available` counts. The trailing
`/context all to expand` is the documented drill-down.

## The `/context all` breakdown

At string offset ~577380 the binary carries the expanded markdown template:

```
### Estimated usage by category
| Category | Tokens | Percentage |
…
| Free space |
| Autocompact buffer |
### MCP Tools
| Tool | Server | Tokens |
### Custom Agents
| Agent Type | Source | Tokens |
### Memory Files
| Type | Path | Tokens |
### Skills
| Skill | Source | Tokens |
```

**This is the skill's inventory hook.** `### MCP Tools` has a `Server` column, so a connector is
identifiable there by its display name (`claude.ai Slack`, etc.) or, in transcripts, by the
normalized `mcp__claude_ai_<connector>__` prefix. There is no connector-specific column.

## Documentation corroboration

<https://code.claude.com/docs/en/commands.md>, fetched 2026-08-17, on the command itself:

> `/context [all]` — Visualize current context usage as a colored grid. Shows optimization
> suggestions for context-heavy tools, memory bloat, and capacity warnings.

<https://code.claude.com/docs/en/context-window>, fetched 2026-08-17, carries an interactive
simulation whose auto-loaded startup entry is labelled **`MCP tools (deferred)`**, matching the
binary label exactly, described as:

> MCP tool names listed so Claude knows what is available. By default, full schemas stay deferred
> and Claude loads specific ones on demand via tool search when a task needs them. Set
> `ENABLE_TOOL_SEARCH=auto` to load schemas upfront when they fit within 10% of the context window,
> or `ENABLE_TOOL_SEARCH=false` to load everything.

**Caveat the skill must respect:** that page's token figures (e.g. 120 tokens for deferred MCP
tools) are explicitly illustrative, not measurements. The page states: "The visualization uses
representative numbers. To see your actual context usage at any point, run `/context` for a live
breakdown by category." **Do not quote 120 tokens as a real connector cost.**

## The other attribution surface — `/usage`

<https://code.claude.com/docs/en/costs>, fetched 2026-08-17, describes a *different* per-server
attribution that the skill may find more useful than `/context` for judging whether a connector earns
its keep:

> **Attribution**: recent usage attributed to skills, subagents, plugins, and individual MCP servers,
> each shown as a percentage of the total. An MCP server's share counts only the requests that
> consumed one of its tool results. Before v2.1.222, after one call to an MCP server, Claude Code
> attributed every subsequent request to that server, overstating its share.

`/context` answers "what is this connector costing me right now"; `/usage` answers "is this
connector being used at all". Both are per-MCP-server, neither is per-connector-as-a-class.
