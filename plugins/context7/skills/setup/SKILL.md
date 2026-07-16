---
name: setup
description: "Set up Context7 for this plugin's lookups — install or verify the ctx7 CLI, wire CONTEXT7_API_KEY auth, optionally add the Context7 MCP server, and confirm the Windows Git Bash gotcha. Use when: 'set up context7', 'configure context7', 'context7 setup', 'install ctx7', 'context7 auth', 'add the Context7 MCP server'."
argument-hint: "(no arguments — interactive, idempotent setup)"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(ctx7 --version*)"
  - "Bash(npm view ctx7 version*)"
---

## Pre-computed context

Installed CLI version: !`ctx7 --version 2>/dev/null || echo "not installed"`

Latest published CLI version: !`npm view ctx7 version 2>/dev/null || echo "unknown (npm registry unreachable)"`

MCP availability: check your own tool list — if `mcp__context7__resolve-library-id` / `mcp__context7__query-docs` are present, the Context7 MCP server is already configured.

## Purpose

Bring the local environment to a working state for `/context7:lookup`. Two independent paths, either
alone sufficient: the **CLI** (`ctx7` via npm) and the **Context7 MCP server** (configured by the
consuming project). An optional `CONTEXT7_API_KEY` raises rate limits for both.

Idempotent and transparent: safe to rerun. Report what is already in place before touching anything,
change only what is missing, and when both paths are already working, confirm the verified state and
make no changes — do not prompt.

## Task

Work top-down from the pre-computed context. State each finding before acting on it.

1. **Assess state.** From the pre-computed block: is `ctx7` installed, and does it match the latest
   published version? Is the MCP server present in your tool list? Report both plainly. If at least
   one path is already working and current, there is nothing required — say so and skip to Output.

2. **CLI path.** If `ctx7` is missing or behind latest, install/upgrade it:

   ```bash
   npm install -g ctx7@latest
   ```

   No global install available? `npx ctx7@latest <command>` works per-invocation. Version floor,
   npx trade-offs, and the full command/flag reference:
   `${CLAUDE_PLUGIN_ROOT}/skills/lookup/context/cli.md`. If already current, skip and say so.

3. **Auth (optional, both paths).** Anonymous usage works at low rates. For higher limits, set the
   `CONTEXT7_API_KEY` environment variable in the user's own shell profile / secret store:

   ```bash
   export CONTEXT7_API_KEY="<your-key>"
   ```

   Prefer this over `ctx7 login`. Never write the key into the repository, Claude Code settings, or
   an MCP config file. Rationale and the `ctx7 login` caveat:
   `${CLAUDE_PLUGIN_ROOT}/skills/lookup/context/cli.md`.

4. **MCP path (optional).** If the user wants the MCP interface (cleaner output, ~1.8× more content
   per call, no Windows ceremony), add a `context7` server entry to *their own* MCP configuration.
   The exact JSON — anonymous and API-key forms, plus the "unset env var breaks config parsing"
   caveat — lives in `${CLAUDE_PLUGIN_ROOT}/skills/lookup/context/mcp.md`. Route the user there; do
   not edit their `.mcp.json` for them without consent.

5. **Windows Git Bash.** Confirm the user knows that CLI `ctx7 docs /org/project "..."` calls must be
   prefixed with `MSYS_NO_PATHCONV=1` (a no-op on macOS/Linux — safe to always include), or the
   `/org/project` ID gets path-mangled. Full explanation:
   `${CLAUDE_PLUGIN_ROOT}/skills/lookup/context/cli.md`.

6. **Verify.** Re-read the CLI version and your tool list. Confirm at least one path (CLI or MCP) is
   live before declaring setup complete. Do not claim a change until re-detection observes it.

## Output

Report what was already in place, what changed, what was skipped, and which lookup path(s) are now
available (CLI, MCP, or both). If nothing needed changing, say the environment was already ready.

## Boundaries

- Do not run `ctx7 setup` or `ctx7 skills install` — this plugin owns the lookup surface; those
  install a parallel skill that fragments and clobbers it (detail in the CLI and update references).
- Do not run `ctx7 setup --mcp` or edit the consumer's `.mcp.json` without consent — their MCP
  configuration is theirs to curate.
- Do not write `CONTEXT7_API_KEY` into the repository, Claude Code settings, or any config file; the
  key belongs in the environment or a secret store.
- Do not perform library lookups — that is `/context7:lookup`.
