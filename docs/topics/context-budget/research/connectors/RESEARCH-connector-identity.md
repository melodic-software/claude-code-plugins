---
topic: claude-ai-connectors-in-claude-code
section: connector-identity
abstract: A connector is an MCP server whose config lives in the user's claude.ai account rather than in Claude Code — same mechanism, different configuration source and a distinct internal transport type.
claims:
  - claim: "Anthropic's own glossary defines a connector as an MCP server added to your claude.ai account rather than configured in Claude Code."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/glossary.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (glossary page)"
      - url: "https://code.claude.com/docs/en/desktop.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (desktop page)"
      - url: "https://code.claude.com/docs/en/mcp.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (mcp page)"
  - claim: "Connectors occupy the lowest rung (5th) of the same single MCP scope-precedence hierarchy as local, project, user and plugin servers, and are deduplicated against them by endpoint."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/mcp.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs"
  - claim: "Connector tools are namespaced mcp__claude_ai_<connector>__<tool>, distinguishing them from plain MCP servers (mcp__<server>__) and plugin servers (mcp__plugin_<plugin>_<server>__)."
    confidence: HIGH
    tiers: [0, 2]
    sources:
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/bin/claude.exe (v2.1.232, strings)"
        tier: 0
        pool: "Anthropic — shipped Claude Code binary (implementation artifact)"
      - url: "https://github.com/anthropics/claude-code/issues/84301"
        tier: 2
        pool: "Community — GitHub issue reporters (independent of Anthropic docs authoring)"
  - claim: "Connectors carry a distinct internal transport/config type 'claudeai-proxy' and an mcpsrv_-prefixed base58 server id, so they are not byte-identical to a .mcp.json entry even though they resolve to the same MCP tool surface."
    confidence: MEDIUM
    tiers: [0]
    sources:
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/bin/claude.exe (v2.1.232, strings)"
        tier: 0
        pool: "Anthropic — shipped Claude Code binary (implementation artifact)"
produced_by: phase-1-2-3
---

# Q1 — What is a connector, versus an MCP server in `.mcp.json`?

**Answer: the same mechanism, a different configuration source — plus one distinct internal transport type.**
They are not two parallel systems. A connector is an MCP server; what differs is *where its
configuration lives* and *how it is authenticated and delivered*.

## The first-party definitions

Anthropic's Claude Code glossary, fetched 2026-08-17 from
<https://code.claude.com/docs/en/glossary.md>:

> ### Connector
>
> An MCP server added to your claude.ai account rather than configured in Claude
> Code. When you sign in to Claude Code with that account, your connectors appear in `/mcp`
> alongside the servers you added locally. Organizations can also provision connectors and set
> per-tool controls on them.

The same page's `MCP server` entry enumerates connectors as one of four ways to add a server:

> You add servers with `claude mcp add`, in `.mcp.json`, through a plugin, or as a
> claude.ai connector.

The desktop page, fetched 2026-08-17 from <https://code.claude.com/docs/en/desktop.md>, states it
even more directly:

> Connectors are [MCP servers](/docs/en/mcp) with a graphical setup flow.

## They share one precedence hierarchy

From <https://code.claude.com/docs/en/mcp.md>, fetched 2026-08-17 — this is the decisive structural
evidence that there is one mechanism, not two:

> When the same server is defined in more than one place, Claude Code connects to it once, using the
> definition from the highest-precedence source. The entire server entry from that source is used;
> fields are not merged across scopes.
>
> 1. Local scope
> 2. Project scope
> 3. User scope
> 4. [Plugin-provided servers](/docs/en/plugins)
> 5. claude.ai connectors
>
> The three scopes match duplicates by name. Plugins and connectors match by endpoint, so one that
> points at the same URL or command as a server above is treated as a duplicate.

A `.mcp.json` entry and a connector can therefore *collide with each other*, which is only possible
because they are the same kind of object. The same page confirms the resolution:

> A server you've added in Claude Code takes precedence over a
> claude.ai connector that points at the same URL. When this happens, `/mcp` lists the connector as
> hidden and shows how to remove the duplicate if you'd rather use the connector.

## Where they genuinely differ

Four differences are real and matter to a context-trimming skill:

| Axis | `.mcp.json` server | claude.ai connector |
|---|---|---|
| Config source | A file in the repo / user dir | The user's claude.ai account, fetched at startup |
| Precedence rung | 1-3 (local / project / user) | 5 — lowest |
| Dedup key | Name | Endpoint |
| Tool namespace | `mcp__<server>__<tool>` | `mcp__claude_ai_<connector>__<tool>` |
| Loading condition | Always (subject to approval) | Only when a claude.ai subscription login is the active auth method |
| Internal type | `stdio` / `http` / `sse` / `ws` | `claudeai-proxy` |

The tool-namespace claim is Tier 0 from the shipped v2.1.232 binary. Its bundled guidance states
verbatim:

> MCP tools are named `mcp__<server>__<tool>` … plugin servers keyed `plugin:<plugin>:<server>`
> appear as `mcp__plugin_<plugin>_<server>__`, and claude.ai connectors as
> `mcp__claude_ai_<connector>__` — match transcripts against the normalized form, but always issue
> disables with the original configured name/key.

That last clause is directly actionable for the skill: **inventory by the normalized
`mcp__claude_ai_*` form, but issue disables using the original configured display name.**

The `claudeai-proxy` type appears in the same binary in a routine-listing helper that filters
`r.config.type !== "claudeai-proxy"` and decodes `mcpsrv_`-prefixed base58 ids into UUIDs. This is
MEDIUM rather than HIGH confidence: it is unambiguous in the implementation but has no documentation
counterpart I could reach, and it is internal, not a stable public contract.

## The gating condition — connectors are conditional, `.mcp.json` servers are not

From <https://code.claude.com/docs/en/mcp.md>, fetched 2026-08-17:

> Connectors from claude.ai are fetched only when your active
> [authentication method](/docs/en/authentication#authentication-precedence) is a claude.ai
> subscription login. They aren't loaded, even if you previously ran `/login`, when:
>
> - `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, or `apiKeyHelper` is active
> - A third-party provider such as Amazon Bedrock or Google Cloud's Agent Platform is active
> - `ANTHROPIC_PROFILE`, the federation variables, or an active Anthropic profile supplies the credential
> - `CLAUDE_CODE_OAUTH_TOKEN` holds a token from `claude setup-token`, which can only make model requests

Corroborated by <https://code.claude.com/docs/en/feature-availability.md>, fetched 2026-08-17:

> **MCP servers**: [connectors from claude.ai](/docs/en/mcp#use-mcp-servers-from-claude-ai) load
> only when your claude.ai subscription is the active authentication method.

**Consequence for the skill:** on an API-key or Bedrock/Vertex session there are *no* connectors to
trim, and the skill should say so rather than reporting a zero. Auth method is the first thing to
check.
