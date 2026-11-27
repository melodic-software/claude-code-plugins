# MCP reference (`mcp__context7__*`)

Context7 HTTP MCP server, reading the same backend as the `ctx7` CLI. This plugin does not ship or auto-start an MCP server; the consuming project opts in by declaring it in its own MCP configuration.

> Server URL and header facts verified 2026-11-27 against `ctx7` 0.13.1 source
> (`packages/cli/src/setup/agents.ts` at `upstash/context7@17839096`) and
> [Context7 MCP Clients](https://context7.com/docs/resources/all-clients) (no stable auth-header
> section anchor; checked 2026-11-27). **Recheck trigger**: `ctx7` ships a new minor release (the
> `update` action reports it) or Context7's MCP Clients docs change the server URL or auth header.

- **Pointer**: when deciding where the entry goes and how a `${VAR}` in it expands, fetch
  [MCP installation scopes](https://code.claude.com/docs/en/mcp#mcp-installation-scopes),
  [Environment variable expansion in `.mcp.json`](https://code.claude.com/docs/en/mcp#environment-variable-expansion-in-mcp-json)
  and [Unset variables without a default](https://code.claude.com/docs/en/mcp#unset-variables-without-a-default)
  live.

## Configuration (consumer-side, optional)

Add to the consuming project's `.mcp.json` (or user-scope MCP config). Anonymous (low-rate) usage needs no headers:

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

With an API key (higher limits), add the `Authorization: Bearer` request header. Use this form only once `CONTEXT7_API_KEY` is set in your environment, or add a `${VAR:-default}` fallback, so the server never starts with a header value you did not intend. What an unset variable does is in the Unset variables without a default pointer at the top of this file, which sits under no section heading:

```json
{
  "mcpServers": {
    "context7": {
      "type": "http",
      "url": "https://mcp.context7.com/mcp",
      "headers": { "Authorization": "Bearer ${CONTEXT7_API_KEY}" }
    }
  }
}
```

`CONTEXT7_API_KEY` is the same env var the CLI reads (see [cli.md](cli.md)). MCP sends it as a request header; CLI reads it from the environment. Both equivalent from a quota/auth perspective. Without the MCP server configured, every lookup in this skill works through the CLI path.

## Tools exposed

| Tool | CLI equivalent |
|---|---|
| `mcp__context7__resolve-library-id` | `ctx7 library <name> <query>` |
| `mcp__context7__query-docs` | `MSYS_NO_PATHCONV=1 ctx7 docs <id> <query>` |

Same input shape as CLI, same backend, and same output substance. Only the transport differs.

- **Pointer**: for what each tool does and the arguments it takes, fetch
  [Context7: MCP Tools](https://github.com/upstash/context7#mcp-tools) live.

## Why prefer MCP over CLI for most lookups

| Dimension | Result |
|---|---|
| Output format | Clean markdown (no ANSI codes to strip) |
| Windows ceremony | None (no `MSYS_NO_PATHCONV=1` prefix) |
| Auto-discovery by the model | Tool appears in the tool list, so the model picks it naturally |

**Default route for conversational library lookups is MCP** when it is configured. CLI's advantages kick in when you want composability (pipe to grep, dump to disk, script), not when you just want the answer.

## When the MCP is unavailable

- Not configured in the consuming project (this plugin doesn't ship it)
- Network restrictions (corporate proxies, some cloud sessions)
- `mcp.context7.com` blocked by local firewall
- Connection failed at session start (check `claude mcp list`)

Fall back to CLI in those cases. Same backend, different transport path. If both are blocked, check `CONTEXT7_API_KEY`, or fall back to other documentation sources and tell the user Context7 was unavailable.

## Do not re-configure via `ctx7 setup --mcp`

`ctx7 setup --mcp` rewrites MCP configuration files and can modify the consuming project's `.mcp.json`. **Do not run it from this skill.** The consumer's MCP configuration is theirs to curate; if Upstash changes their recommended MCP URL or headers in a future release, the `update` action ([update.md](update.md)) surfaces that so the consumer can port the change deliberately.
