---
description: "Verify the Dometrain plugin without reading or exposing its API key. Use when: 'set up Dometrain', 'configure Dometrain', 'Dometrain setup', the Dometrain MCP server is unavailable, or a Dometrain tool reports an authentication error. Actions: check (read-only verification, default and only action — this plugin's entire configuration is native userConfig, so there is nothing an apply could write)."
argument-hint: "check"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Guide the user through Claude Code's native configuration flow and report whether the remote
Dometrain MCP server is reachable, without reading, printing, or writing the sensitive
`dometrain_api_key`. Claude Code prompts for the required key when the plugin is enabled and owns
its secure credential storage.

Check-only per the uniform setup contract's userConfig-only carve-out: this plugin's entire
configuration surface is the native sensitive `userConfig` key, so `check` (default and only
action) verifies and reports, and reconfiguration routes through Claude Code's native flow.

**Mechanism note (why this skill does not read `/mcp`):** `/mcp` is a human-run interactive
command. No tool exposes its output to a model turn. The one real, model-visible signal for a
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
   key was supplied. Do not claim the key has valid API access beyond that. A connection-layer
   401/403/429 rejection (per Dometrain's own README Troubleshooting section) would prevent the
   tool from resolving at all, so resolution itself is the strongest signal this skill can observe.
4. When the plugin is enabled but no `dometrain`-scoped tool resolves, report **failed or
   unverified**:
   - If `ToolSearch` returned a connection error for the `dometrain` server, quote it verbatim.
   - Otherwise do not assert why: Claude Code does not report failed connections to Claude in a
     configuration without tool search (custom `ANTHROPIC_BASE_URL`, `ENABLE_TOOL_SEARCH=false`, or
     a model that doesn't support tool search), and on Amazon Bedrock, Google Cloud's Agent
     Platform, and Microsoft Foundry, and this skill cannot inspect the environment to tell which
     is in effect. Direct the user to run `/mcp` themselves rather than claim knowledge it doesn't
     have.
   - After the user reconfigures the key, require `/reload-plugins` or a new session before
     rechecking tool availability.

## Headless installation

For a non-interactive install such as CI, a fleet bootstrap, or a scripted machine setup, seed the key
on the initial install instead of the interactive `/plugin` prompt. Three steps, all required:

```shell
claude plugin marketplace add <source> --scope <scope>
claude plugin install dometrain@<marketplace> -s <scope> --config dometrain_api_key=<your-key>
claude plugin enable dometrain -s <scope>
```

Both placeholders are bootstrap inputs, not lookups: before the first install there is no record
to read them from. `<marketplace>` is the name the catalog registers under when it is added, and
`<scope>` is the scope the bootstrap chooses: `user`, `project`, or `local`. `marketplace add`
and `install` default to `user` when the flag is omitted, while `enable` auto-detects. Carry the
same `<scope>` through all three. Note the asymmetry: `marketplace add` spells it `--scope` only,
while `install` and `enable` also accept the `-s` short form. Registering at `user` while
installing at `project` leaves the marketplace declaration out of the project's checked-in
settings, so a fresh clone or CI agent carries the enabled plugin with no registered marketplace
to resolve it from.

**The enable step is not optional.** This plugin ships `defaultEnabled: false`, so it installs
DISABLED. The install seeds the key but leaves the MCP server, and therefore every `dometrain`
tool, unavailable until it is enabled ([Default enablement](https://code.claude.com/docs/en/plugins-reference#default-enablement),
which also notes `claude plugin enable` auto-detects the scope when `-s` is omitted; passing it
explicitly keeps the sequence deterministic in CI). A bootstrap that stops after `install` looks
successful and delivers no tools.

**Rotating or clearing the key:** `/plugin configure dometrain@<marketplace>` (interactive, any
time) is the recommended rotation path regardless. It masks input, where a key passed on the
command line lands in shell history and the process table.

The older claim that `--config` is ignored once the plugin is installed was never
version-stamped, and on Claude Code 2.1.240 a plain `claude plugin install … --config` was
observed to write the value of an already-installed plugin for a **non-sensitive** option at
`user` scope. Whether that holds for a `sensitive` option such as `dometrain_api_key` has not
been verified, so do not rely on it for a credential. Do **not** uninstall to rotate either:
uninstalling drops this plugin's entire stored `pluginConfigs` entry, resetting every option in
the README's Options reference table to its manifest default, and it can drop the
`enabledPlugins` entry as well. A `defaultEnabled: false` plugin reinstalls DISABLED, so a
rotation that ends at `install` completes with no tools available.

Full detail, including the command-line-exposure caveat, is in the README's
[Rotating or clearing the key](../../README.md#rotating-or-clearing-the-key) section.

## Output

Report exactly one state: `disabled`, `connected`, or `failed or unverified`. Include the exact
next action when the state is not `connected`.

Sensitive values use the macOS Keychain, or `~/.claude/.credentials.json` on platforms where no
supported keychain is available. Never read or reveal either location's contents.

## Namespace-collision note

Dometrain ships its own official Claude Code plugin (`github.com/Dometrain/mcp`) whose
`plugin.json` `name` is also `"dometrain"`. If the user has that plugin enabled too, do not attempt
to detect the collision by comparing MCP tool-name prefixes. A true collision produces an
*identical*, not divergent, prefix, so no prefix comparison can distinguish "one plugin enabled" from
"two colliding plugins enabled." Point the user to this plugin's README collision warning instead.

## Boundaries

- Do not read, echo, log, copy, or persist the API key.
- Do not write the plugin cache, Claude Code user settings, or `pluginConfigs`, per the uniform
  setup contract (`docs/PLUGIN-PHILOSOPHY.md` "Setup is explicit and repeatable" in the
  marketplace repository).
- Do not call a Dometrain tool during setup. Resolution via tool inventory / `ToolSearch` is
  sufficient and spends no quota.
- Do not claim to have read `/mcp` connection status. No tool exposes it to a model turn.
