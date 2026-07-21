---
name: setup
description: "Verify or configure Context7 for this plugin's lookups — check the ctx7 CLI, CONTEXT7_API_KEY auth, and the Context7 MCP server, then install/upgrade the CLI on request. Use when: 'set up context7', 'configure context7', 'is context7 working', 'context7 setup', 'install ctx7', 'context7 auth', 'add the Context7 MCP server'. Actions: check (read-only verification, default) | apply (resolve what check found) | apply install-cli (also install/upgrade the ctx7 CLI)."
argument-hint: "check | apply [install-cli]"
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

MCP availability: check your own tool list — if `mcp__context7__resolve-library-id` / `mcp__context7__query-docs` are present, the Context7 MCP server is already configured.

## Purpose

Bring the local environment to a working state for `/context7:lookup`. Two independent paths,
either alone sufficient: the **CLI** (`ctx7` via npm) and the **Context7 MCP server** (configured
by the consuming project). An optional `CONTEXT7_API_KEY` raises rate limits for both.

Check-centric per the uniform contract: `check` inspects and reports, `apply` resolves what
`check` found, and the CLI install is a distinct opt-in subaction. Idempotent and transparent:
safe to rerun. Report what is already in place before touching anything, and when both paths are
already working, confirm the verified state and make no changes.

Action routing: no argument or `check` runs the check; `apply` runs the check first, then the
guidance-only remediations (auth, MCP routing); `apply install-cli` additionally authorizes the
global `ctx7` install/upgrade below. All actions are non-interactive when the action is given —
never prompt.

## `check` (read-only)

Work top-down from the pre-computed context and report a PASS/FAIL/INFO table with one
remediation line per FAIL. Do not install, edit config, or write anything.

1. **CLI path** — from the pre-computed block: is `ctx7` installed, and does it match the latest
   published version? A working, current CLI is PASS. Installed-but-behind is INFO with
   remediation `apply install-cli`. Absent is INFO only when the MCP path is live (below);
   otherwise it is a FAIL of the "at least one path works" requirement.
2. **MCP path** — is the Context7 MCP server present in your tool list? Present is PASS; absent is
   INFO (the MCP interface is optional — the CLI alone is sufficient).
3. **At least one path** — FAIL only when neither the CLI nor the MCP server resolves; every
   lookup would then be blocked. Remediation: `apply install-cli`, or add the MCP server (routed
   in `apply`).
4. **Auth** — INFO: report whether `CONTEXT7_API_KEY` is present in the environment
   (`[ -n "$CONTEXT7_API_KEY" ]`). Report presence only — never print or echo the value.
   Anonymous usage works at low rates, so absence is never a FAIL.
5. **Windows Git Bash** — INFO: CLI `ctx7 docs /org/project "..."` calls must be prefixed with
   `MSYS_NO_PATHCONV=1` (a no-op on macOS/Linux — safe to always include), or the `/org/project`
   ID gets path-mangled. Full explanation:
   `${CLAUDE_PLUGIN_ROOT}/skills/lookup/context/cli.md`.

## `apply` (idempotent)

Run `check`, then resolve each finding. Re-running after both paths are working changes nothing
and reports "already configured". State each change before making it, and re-detect before
claiming it.

1. **`apply install-cli` — install or upgrade the CLI.** Only with this subaction, and only when
   `check` found `ctx7` missing or behind latest:

   ```bash
   npm install -g ctx7@latest
   ```

   No global install available? `npx ctx7@latest <command>` works per-invocation. Version floor,
   npx trade-offs, and the full command/flag reference:
   `${CLAUDE_PLUGIN_ROOT}/skills/lookup/context/cli.md`. After installing, re-read the CLI version
   and report the observed result — never claim upgraded on the install command's exit code alone.

2. **Auth (optional, both paths) — guidance only.** For higher limits, direct the user to set
   `CONTEXT7_API_KEY` in their own shell profile / secret store:

   ```bash
   export CONTEXT7_API_KEY="<your-key>"
   ```

   Prefer this over `ctx7 login`. Never write the key into the repository, Claude Code settings,
   or an MCP config file, and never print its value. An environment-variable change takes effect
   in a fresh session; report its presence only and defer verification to that fresh session.
   Rationale and the `ctx7 login` caveat: `${CLAUDE_PLUGIN_ROOT}/skills/lookup/context/cli.md`.

3. **MCP path (optional) — guidance only.** If the user wants the MCP interface (cleaner output,
   ~1.8× more content per call, no Windows ceremony), route them to add a `context7` server entry
   to *their own* MCP configuration. The exact JSON — anonymous and API-key forms, plus the
   "unset env var breaks config parsing" caveat — lives in
   `${CLAUDE_PLUGIN_ROOT}/skills/lookup/context/mcp.md`. Do not edit their `.mcp.json` for them.

4. **Verify.** Re-read the CLI version and your tool list. Confirm at least one path (CLI or MCP)
   is live before declaring setup complete.

## Output

Report what was already in place, what changed, what was skipped, and which lookup path(s) are now
available (CLI, MCP, or both). If nothing needed changing, say the environment was already ready.

## Boundaries

- Do not run `ctx7 setup` or `ctx7 skills install` — this plugin owns the lookup surface; those
  install a parallel skill that fragments and clobbers it (detail in the CLI and update references).
- Do not run `ctx7 setup --mcp` or edit the consumer's `.mcp.json` without consent — their MCP
  configuration is theirs to curate.
- Do not write `CONTEXT7_API_KEY` into the repository, Claude Code settings, or any config file, and
  never print its value; the key belongs in the environment or a secret store.
- Do not write the plugin cache, Claude Code user settings, or `pluginConfigs`.
- Do not perform library lookups — that is `/context7:lookup`.
