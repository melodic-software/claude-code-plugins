---
description: "Looks up current library documentation, API references and code examples through Context7 (ctx7 CLI or the Context7 MCP server). Use when: 'look up the docs for X', 'how do I migrate to X v2', or whenever a question names a library, framework, SDK, CLI tool, or cloud service, including API syntax, configuration, setup, and version-migration questions. The update action checks the CLI and upstream skill content for drift. For CLI/MCP setup, auth, and Windows gotchas, run /context7:setup."
argument-hint: "[lookup <library> <query>|update]"
user-invocable: true
disable-model-invocation: false
allowed-tools:
  - "Bash(ctx7 --version*)"
metadata:
  upstream-version: upstash/context7@522c4db4fa2e1e31f1b320f09fa8c8fab376987a
  synced: 2026-10-11
  workflow-stage: research
  summary: Look up current library docs, API references, and examples via Context7
shell: bash
---

**Arguments.** `[lookup <library> <query>|update]`. A bare argument is `lookup`, e.g. /context7:lookup react "useEffect cleanup".

## Pre-computed context

Installed CLI version: !`ctx7 --version 2>/dev/null || echo "not installed (run: npm install -g ctx7@latest)"`

MCP availability: if `mcp__context7__resolve-library-id` and `mcp__context7__query-docs` are in your tool list, the MCP path is configured.

## Actions

| Action | When | Loads |
|---|---|---|
| `lookup <library> <query>` (default) | A question about a library | [context/lookup.md](context/lookup.md): query writing, result selection, version-specific IDs, common mistakes |
| `update` | CLI upgrade and upstream drift check | [context/update.md](context/update.md): merge strategy, what to preserve, baseline refresh |

Verify library behavior against Context7 before stating it; training data lags library releases. CLI install, `CONTEXT7_API_KEY` auth and MCP wiring belong to `/context7:setup`.

## Lookup

Resolve the name to a Context7 library ID, then fetch docs with that ID:

```bash
ctx7 library "<name>" "<question>"
MSYS_NO_PATHCONV=1 ctx7 docs "<libraryId>" "<question>"
```

Or through the MCP server, when configured:

```text
mcp__context7__resolve-library-id(libraryName: "...", query: "...")
mcp__context7__query-docs(libraryId: "/org/project", query: "...")
```

- Always resolve first; the docs step rejects anything but a resolved ID, unless the user supplied one in `/org/project` form.
- One concept per query; run a separate lookup per independent topic, and at most 3 lookup commands per topic. When Context7 does not cover it, answer from training knowledge and say so.
- Never put API keys, passwords or other credentials in a query: it is sent to the Context7 backend.

Both paths read the same backend. Prefer the MCP server for conversational lookups: it returns more per call (measured ratio in [context/mcp.md](context/mcp.md)), clean markdown, needs no `MSYS_NO_PATHCONV`, and is discoverable from your tool list. Use the CLI to pipe or save output (`grep`, `jq`, `> docs.md`), in scripts and loops, for `--json` extraction, or when no MCP server is configured or `mcp.context7.com` is blocked. Flags and errors: [context/cli.md](context/cli.md).

## Update

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/lookup/scripts/update.sh"        # report only
bash "${CLAUDE_PLUGIN_ROOT}/skills/lookup/scripts/update.sh" --fix  # also upgrade the CLI
```

The script reports installed vs latest `ctx7` and diffs upstream `find-docs` and `context7-cli` against the `vendor/` baselines. It exits 0 for no drift, 1 for drift and 2 when a check could not run; a `ctx7` that is not installed is reported, not counted as drift. It never rewrites this skill: the update is advisory, the user approves every port, and this skill's own additions (Windows prefix, CLI-vs-MCP guidance, action dispatch) are kept. Read `vendor/` only during `update`, never for a lookup. Protocol: [context/update.md](context/update.md).

## Spoke paths

The `context/` files write this skill's directory as `<skill-dir>`, which is `${CLAUDE_SKILL_DIR}`.
Put that path in place of the placeholder before running a command or writing it into a brief;
never hand a `${…}` token from those files to the Bash tool.

- **Pointer**: when deciding where a `${…}` reference resolves and what the Bash tool's environment
  carries, fetch
  [Where each variable resolves](https://code.claude.com/docs/en/plugins/manifest-reference#where-each-variable-resolves)
  live.
- **As of**: 2026-10-11
- **Recheck trigger**: that table adds supporting files to where a `${…}` reference resolves, or the
  Bash tool's environment starts carrying the plugin variables.

## Gotchas

- **Windows Git Bash** rewrites `ctx7 docs /org/project` into `C:/Program Files/Git/org/project`. Always prefix `ctx7 docs` with `MSYS_NO_PATHCONV=1`; `ctx7 library` is unaffected. Detail: [context/cli.md](context/cli.md).
- The CLI has no flag for content depth; for more per call, use the MCP server.
- Never run `ctx7 skills install` into `.claude/skills/`: this plugin owns the lookup surface, and a second copy of Upstash's `find-docs` fragments lookups and drifts on its own.
- This skill retrieves library docs only. Architecture decisions and other questions that need cross-checked sources go to a research workflow.
