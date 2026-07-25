---
name: setup
description: "Verify the Dometrain plugin without reading or exposing its API key. Use when: 'set up Dometrain', 'configure Dometrain', 'Dometrain setup', the Dometrain MCP server is unavailable, or a Dometrain tool reports an authentication error. Actions: check (read-only verification, default and only action — this plugin's entire configuration is native userConfig, so there is nothing an apply could write)."
argument-hint: "check"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Guide the user through Claude Code's native configuration flow and report whether the remote
Dometrain MCP server is reachable — without reading, printing, or writing the sensitive
`dometrain_api_key`. Claude Code prompts for the required key when the plugin is enabled and owns
its secure credential storage.

Check-only per the uniform setup contract's userConfig-only carve-out: this plugin's entire
configuration surface is the native sensitive `userConfig` key, so `check` (default and only
action) verifies and reports, and reconfiguration routes through Claude Code's native flow.

**Mechanism note (why this skill does not read `/mcp`):** `/mcp` is a human-run interactive
command — no tool exposes its output to a model turn. The one real, model-visible signal for a
failed remote server is Claude Code's own `ToolSearch`-surfaced connection error: "When a
configured server fails to connect, Claude Code tells Claude which server failed and its
connection error, including in `ToolSearch` results that find no matching tool... Requires tool
search, which is enabled by default. In configurations without tool search... Claude Code doesn't
report failed server connections to Claude." (<https://code.claude.com/docs/en/mcp>). This skill
is built around that constraint, not around reading `/mcp` connection status directly.

Official contracts:

- <https://code.claude.com/docs/en/plugins-reference#user-configuration>
- <https://code.claude.com/docs/en/plugins-reference#default-enablement>
- <https://code.claude.com/docs/en/mcp>

## Task

1. Check whether the `dometrain` plugin is enabled and whether its scoped MCP tools (e.g.
   `list_courses`, `search_dometrain`) are present in the current tool inventory. Do not inspect
   settings files, environment variables, process arguments, debug logs, credential stores, or the
   key itself.
2. When the plugin is disabled (no `dometrain`-scoped tool was ever attempted), direct the user to
   enable it through the `/plugin` interface or `claude plugin enable dometrain`. Claude Code's
   native prompt collects the required key. Do not run either command for the user and do not
   hand-edit `pluginConfigs`. For a non-interactive install (CI, a fleet bootstrap, a scripted
   machine setup), point to the headless path below instead.
3. When the plugin is enabled and a `dometrain`-scoped tool resolves (via direct tool-list
   presence or a successful `ToolSearch` match), report **connected**: the server started and the
   key was supplied. Do not claim the key has valid API access beyond that — a connection-layer
   401/403/429 rejection (per Dometrain's own README Troubleshooting section) would prevent the
   tool from resolving at all, so resolution itself is the strongest signal this skill can observe.
4. When the plugin is enabled but no `dometrain`-scoped tool resolves, report **failed or
   unverified**:
   - If `ToolSearch` returned a connection error for the `dometrain` server, quote it verbatim.
   - If this environment has tool search disabled (custom `ANTHROPIC_BASE_URL`,
     `ENABLE_TOOL_SEARCH=false`, Bedrock, GCP Agent Platform, or a non-tool-search model), say so
     explicitly and direct the user to run `/mcp` themselves — Claude Code does not report failed
     connections to Claude in that configuration, and this skill must not claim knowledge it
     doesn't have.
   - After the user reconfigures the key, require `/reload-plugins` or a new session before
     rechecking tool availability.

## Headless installation

For a non-interactive install — CI, a fleet bootstrap, a scripted machine setup — seed the key
on the initial install instead of the interactive `/plugin` prompt:

```shell
claude plugin install dometrain@melodic-software --config dometrain_api_key=<your-key>
```

**Fresh-install-only:** `--config` seeds a value only on a fresh install. Re-running it against
an already-installed `dometrain` does not update the stored key. To rotate or clear the key
later, use `/plugin configure dometrain` (interactive, any time) or uninstall then reinstall with
a new `--config` value (headless) — never re-run `install --config` against an existing install
expecting it to take effect. Full detail, including the command-line-exposure caveat, is in the
README's [Rotating or clearing the key](../../README.md#rotating-or-clearing-the-key) section.

## Output

Report exactly one state: `disabled`, `connected`, or `failed or unverified`. Include the exact
next action when the state is not `connected`.

Sensitive values use the macOS Keychain, or `~/.claude/.credentials.json` on platforms where no
supported keychain is available. Never read or reveal either location's contents.

## Namespace-collision note

Dometrain ships its own official Claude Code plugin (`github.com/Dometrain/mcp`) whose
`plugin.json` `name` is also `"dometrain"`. If the user has that plugin enabled too, do not attempt
to detect the collision by comparing MCP tool-name prefixes — a true collision produces an
*identical*, not divergent, prefix, so no prefix comparison can distinguish "one plugin enabled" from
"two colliding plugins enabled." Point the user to this plugin's README collision warning instead.

## Boundaries

- Do not read, echo, log, copy, or persist the API key.
- Do not edit Claude Code settings or `pluginConfigs`.
- Do not call a Dometrain tool during setup — resolution via tool inventory / `ToolSearch` is
  sufficient and spends no quota.
- Do not claim to have read `/mcp` connection status — no tool exposes it to a model turn.
