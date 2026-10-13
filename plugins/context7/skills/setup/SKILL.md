---
description: "Check or configure Context7 for lookups: the ctx7 CLI, CONTEXT7_API_KEY auth and the Context7 MCP server, with a CLI install on request."
argument-hint: "[check|apply] [install-cli]"
user-invocable: true
disable-model-invocation: true
allowed-tools:
  - "Bash(ctx7 --version*)"
  - "Bash(npm view ctx7 version*)"
shell: bash
---

## Pre-computed context

Installed CLI version: !`ctx7 --version 2>/dev/null || echo "not installed"`

Latest published CLI version: !`npm view ctx7 version 2>/dev/null || echo "unknown (npm registry unreachable)"`

MCP availability: if `mcp__context7__resolve-library-id` and `mcp__context7__query-docs` are in your tool list, the Context7 MCP server is configured.

## Actions

`/context7:lookup` works through either of two paths: the **CLI** (`ctx7` via npm) or the
**Context7 MCP server** (configured by the consuming project). An optional `CONTEXT7_API_KEY` raises
rate limits for both.

- No argument or `check`: run the check.
- `apply`: run the check, then the guidance-only remediations (auth, MCP).
- `apply install-cli`: also install or upgrade the global `ctx7`.

Never prompt; the action given is the whole instruction. Every action is safe to rerun.

## `check` (read-only)

Report a PASS/FAIL/INFO table from the pre-computed context, with one remediation line per FAIL. Do
not install, edit config, or write anything.

1. **CLI path**. Installed and matching the latest published version is PASS. Installed but behind
   is INFO, remediation `apply install-cli`. Absent is INFO when the MCP path is live, otherwise
   it counts against step 3.
2. **MCP path**. Present in your tool list is PASS; absent is INFO. The CLI alone is sufficient.
3. **At least one path**. FAIL only when neither the CLI nor the MCP server resolves, since every
   lookup would then be blocked. Remediation: `apply install-cli`, or add the MCP server (routed in
   `apply`).
4. **Auth**. INFO: whether `CONTEXT7_API_KEY` is set (`[ -n "$CONTEXT7_API_KEY" ]`). Report
   presence only; never print the value. Anonymous use works at low rates, so absence is never a
   FAIL.
5. **Windows Git Bash**. INFO: prefix CLI `ctx7 docs /org/project "..."` calls with
   `MSYS_NO_PATHCONV=1` (a no-op elsewhere, so always safe), or the ID gets path-mangled. Detail:
   `${CLAUDE_PLUGIN_ROOT}/skills/lookup/context/cli.md`.

## `apply`

Run `check`, then resolve each finding. With both paths working, report "already configured" and
change nothing. State each change before making it, and re-detect before claiming it.

1. **CLI, only with `apply install-cli`**, and only when `check` found `ctx7` missing or behind:

   ```bash
   npm install -g ctx7@latest
   ```

   Without a global install, `npx ctx7@latest <command>` works per call; version floor and flags:
   `${CLAUDE_PLUGIN_ROOT}/skills/lookup/context/cli.md`. Re-read the CLI version afterwards and
   report what it shows, never the install command's exit code alone.

2. **Auth, guidance only.** Tell the user to set the key in their own shell profile or secret
   store, in preference to `ctx7 login`:

   ```bash
   export CONTEXT7_API_KEY="<your-key>"
   ```

   It takes effect in a fresh session; report presence only and leave verification to that
   session. The `ctx7 login` caveat: `${CLAUDE_PLUGIN_ROOT}/skills/lookup/context/cli.md`.

3. **MCP, guidance only.** If the user wants the MCP path, point them to add a `context7` server
   entry to their own MCP configuration; do not edit their `.mcp.json` for them. The JSON (anonymous and API-key forms) and the
   unset-env-var caveat: `${CLAUDE_PLUGIN_ROOT}/skills/lookup/context/mcp.md`.

4. **Verify.** Re-read the CLI version and your tool list; declare setup complete only when at
   least one path is live.

## Output

What was already in place, what changed, what was skipped, and which lookup paths now work (CLI,
MCP, or both).

## Boundaries

- Never run `ctx7 setup` or `ctx7 skills install`: they install a parallel skill that fragments
  this plugin's lookup surface.
- Never run `ctx7 setup --mcp` or edit the user's `.mcp.json` without their consent: their MCP
  configuration is theirs.
- Never write `CONTEXT7_API_KEY` into the repository, Claude Code settings or any config file, and
  never print it.
- Never write the plugin cache, Claude Code user settings or `pluginConfigs`: the cache is
  replaced on the next plugin update, and machine-wide Claude Code state belongs to the user.
- Library lookups belong to `/context7:lookup`.
