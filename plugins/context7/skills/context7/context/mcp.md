# MCP reference (`mcp__context7__*`)

Context7 HTTP MCP server — reads the same backend as the `ctx7` CLI. This plugin does NOT ship or auto-start an MCP server; the consuming project opts in by declaring it in its own MCP configuration.

## Configuration (consumer-side, optional)

Add to the consuming project's `.mcp.json` (or user-scope MCP config) — server entries live under the top-level `mcpServers` key. Anonymous (low-rate) usage needs no headers:

```json
{
  "mcpServers": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp"
    }
  }
}
```

With an API key (higher limits), add the `CONTEXT7_API_KEY` request header (the header name Context7's server expects) — but note Claude Code **fails to parse the config** when a referenced env var is unset with no default, so only use this form once `CONTEXT7_API_KEY` is actually set in your environment:

```json
{
  "mcpServers": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp",
      "headers": { "CONTEXT7_API_KEY": "${CONTEXT7_API_KEY}" }
    }
  }
}
```

`CONTEXT7_API_KEY` is the same env var the CLI reads (see [cli.md](cli.md)). MCP sends it as a request header; CLI reads it from the environment. Both equivalent from a quota/auth perspective. Without the MCP server configured, every lookup in this skill works through the CLI path.

## Tools exposed

| Tool | Purpose | CLI equivalent |
|---|---|---|
| `mcp__context7__resolve-library-id` | Resolve library name → `/org/project` ID | `ctx7 library <name> <query>` |
| `mcp__context7__query-docs` | Fetch docs for a resolved ID | `MSYS_NO_PATHCONV=1 ctx7 docs <id> <query>` |

Both tools require a `query` argument for result ranking. Same input shape as CLI, same backend, same output substance — different transport.

## Why prefer MCP over CLI for most lookups

Empirical observation (2026-04, React + EF Core test queries):

| Dimension | Result |
|---|---|
| Default content per `query-docs` call | ~1.8× more than `ctx7 docs` at default settings |
| Output format | Clean markdown (no ANSI codes to strip) |
| Windows ceremony | None (no `MSYS_NO_PATHCONV=1` prefix) |
| Auto-discovery by the model | Tool appears in the tool list — model picks it naturally |
| Latency | ~2.1s (same as CLI — both network-bound) |

**Default route for conversational library lookups is MCP** when it is configured. CLI's advantages kick in when you want composability (pipe to grep, dump to disk, script), not when you just want the answer.

## When the MCP is unavailable

- Not configured in the consuming project (this plugin doesn't ship it)
- Network restrictions (corporate proxies, some cloud sessions)
- `mcp.context7.com` blocked by local firewall
- Connection failed at session start (check `claude mcp list`)

Fall back to CLI in those cases — same backend, different transport path. If both are blocked, check `CONTEXT7_API_KEY`, or fall back to other documentation sources and tell the user Context7 was unavailable.

## Serialization and performance

Observed behavior (not a documented guarantee): back-to-back `resolve-library-id` + `query-docs` calls complete serially (~2s each, ~4s for the pair) — no parallelism benefit.

Irrelevant in practice — you always need the `library` result before the `docs` call — so serial is correct.

## Do not re-configure via `ctx7 setup --mcp`

`ctx7 setup --mcp` rewrites MCP configuration files and can modify the consuming project's `.mcp.json`. **Do not run it from this skill.** The consumer's MCP configuration is theirs to curate; if Upstash changes their recommended MCP URL or headers in a future release, the `update` action ([update.md](update.md)) surfaces that so the consumer can port the change deliberately.
