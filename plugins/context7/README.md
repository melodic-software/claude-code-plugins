# context7

A Claude Code plugin for looking up **current library documentation, API
references, and code examples** via [Context7](https://context7.com) — so
answers about libraries, frameworks, SDKs, and cloud services come from live
docs instead of stale training data.

Invoke it with `/context7:context7` (or let Claude invoke it automatically when
a question names a library):

```text
/context7:context7 react "useEffect cleanup"
/context7:context7 configure
/context7:context7 update
```

## What it does

- **`lookup <library> <query>`** (default) — the two-step Context7 workflow:
  resolve the library name to a `/org/project` ID, then query its docs. Works
  through the `ctx7` CLI, or through the Context7 MCP server when the consuming
  project has one configured (same backend, ~1.8× more content per call).
- **`configure`** — CLI install, `CONTEXT7_API_KEY` auth, and the Windows Git
  Bash `MSYS_NO_PATHCONV=1` gotcha.
- **`update`** — checks the installed `ctx7` CLI against the latest npm release
  (`--fix` upgrades it) and diffs Upstash's upstream reference skills against
  the plugin's bundled `vendor/` baselines, reporting anything new for manual
  review. It never auto-rewrites the skill.

## Requirements

- **`ctx7` CLI** (`npm install -g ctx7@latest`) for the CLI path — or a
  Context7 MCP server configured in the consuming project for the MCP path.
  Either alone is enough; the skill picks whichever is available.
- **`CONTEXT7_API_KEY`** (optional) — anonymous usage works at low rates; an
  API key raises limits. Set it as an environment variable; never commit it.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install context7@melodic-software
```

## Configuration

This plugin has no `userConfig` and ships **no MCP server** — it never opens a
network surface by itself beyond the lookups you ask for. Two optional
consumer-side settings:

- `CONTEXT7_API_KEY` environment variable — higher rate limits for both CLI
  and MCP paths.
- A `context7` entry in your own MCP configuration if you want the MCP path —
  the skill documents the exact snippet and degrades cleanly to the CLI when
  it is absent.

## Data egress note

Lookup queries (your library question text) are sent to the Context7 backend
(`context7.com` / `mcp.context7.com`). Don't put secrets in queries. The
`ctx7` CLI also sends anonymous usage telemetry by default — set
`CTX7_TELEMETRY_DISABLED=1` to opt out. The `update` action additionally
fetches two public files from `raw.githubusercontent.com` (Upstash's
reference skills) and reads the npm registry for the latest `ctx7` version —
read-only, nothing uploaded.

## License

MIT (SPDX-License-Identifier: MIT). See the LICENSE file at the root of the
melodic-software/claude-code-plugins repository.
