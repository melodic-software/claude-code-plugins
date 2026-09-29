---
description: "Verify that the Dometrain MCP tools are available to the Dometrain grounding skills, without reading or exposing any API key. Use when: 'set up Dometrain', 'configure Dometrain', 'Dometrain setup', the Dometrain MCP server is unavailable, or a Dometrain tool reports an authentication error. Actions: check (read-only verification, default and only action). This plugin has no options and ships no server: the tools come from the dometrain-mcp plugin or from a user-scope dometrain server, so there is nothing an apply could write."
argument-hint: "check"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Report whether a Dometrain MCP server is reachable from this session, without reading, printing,
or writing any API key. This plugin ships skills only. The tools come from one of two supported
setups, both described in the README's
[Getting the MCP server](../../README.md#getting-the-mcp-server):

- the `dometrain-mcp` plugin, whose key lives in that plugin's `dometrain_api_key` option;
- a user-scope `dometrain` MCP server the user registered.

Both expose the same tool names under a `dometrain` server segment. This skill matches on the
server segment and tool name in the runtime inventory and never on a fixed prefix, because Claude
Code owns the prefix format and can change it. A plugin-provided server's name carries its
plugin's name before the server segment; a user-scope server's does not.

Check-only per the uniform setup contract's carve-out for a plugin with no options: `check`
(default and only action) verifies and reports. Both setups keep their credentials outside this
skill, so it never manages them.

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

1. Check whether a Dometrain tool (e.g. `list_courses`, `search_dometrain`) is present in the
   current tool inventory, matched by the `dometrain` server segment and the tool name, whether
   the name shows a plugin (`dometrain-mcp`) or none (a user-scope server). Do not inspect
   settings files, environment variables, process arguments, debug logs, credential stores, or
   any key.
2. When a Dometrain tool resolves (via direct tool-list presence or a successful `ToolSearch`
   match), report **connected**, naming the source: the `dometrain-mcp` plugin or a user-scope
   server, per the name shown. Do not
   claim the credential has valid API access beyond that. A connection-layer 401/403/429 rejection
   (per Dometrain's own README Troubleshooting section) would prevent the tool from resolving at
   all, so resolution itself is the strongest signal this skill can observe.
3. When no Dometrain tool resolves and `ToolSearch` returned no connection
   error for a `dometrain` server, report **disabled**: no supported setup is present. Name the two
   supported setups and how to get each:
   - Install and enable `dometrain-mcp` (`claude plugin enable dometrain-mcp` or the `/plugin`
     interface). Claude Code's native prompt collects the key. Do not run either command for the
     user and do not hand-edit `pluginConfigs`. For a non-interactive install (CI, a fleet
     bootstrap, a scripted machine setup), point to the headless path below.
   - Add a user-scope server per the README's
     [Adding your own server](../../README.md#adding-your-own-server). In that case the user
     installs `dometrain` alone; installing `dometrain-mcp` too produces a duplicate-server warning
     in `/plugin`.
4. When `dometrain-mcp` is enabled or a user-scope server is registered but no tool resolves,
   report **failed or unverified**:
   - If `ToolSearch` returned a connection error for the `dometrain` server, quote it verbatim.
   - Otherwise do not assert why. Claude Code does not report failed connections to Claude in a
     configuration without tool search, and this skill cannot inspect the environment to tell
     whether tool search is active. Direct the user to run `/mcp` themselves rather than claim
     knowledge it does not have.
   - The fix depends on the setup in play, and this skill cannot tell from tool absence alone
     which one the user is on. For `dometrain-mcp`, the user reconfigures the key with
     `/plugin configure dometrain-mcp@<marketplace>`, then needs `/reload-plugins` or a new
     session before rechecking. For a user-scope server, do not send the user to
     `/plugin configure`: point them to `claude mcp list` for a missing-variable warning on the
     `dometrain` entry and to the README's
     [Adding your own server](../../README.md#adding-your-own-server); a variable set after Claude
     Code started needs a new session, since Claude Code expands it from its own environment at
     connect time.

## Headless installation

For a non-interactive install such as CI, a fleet bootstrap, or a scripted machine setup, install
the skills and, when the bundled server is wanted, `dometrain-mcp` with the key seeded on its
initial install. Every step is required:

```shell
claude plugin marketplace add <source> --scope <scope>
claude plugin install dometrain@<marketplace> -s <scope>
claude plugin install dometrain-mcp@<marketplace> -s <scope> --config dometrain_api_key=<your-key>
claude plugin enable dometrain -s <scope>
claude plugin enable dometrain-mcp -s <scope>
```

If the bootstrap resolves the credential from an environment variable or a secret store instead,
skip `dometrain-mcp` entirely and register the user-scope server with
`claude mcp add-json dometrain … --scope user` per the README's
[Adding your own server](../../README.md#adding-your-own-server). The `enable` step for `dometrain`
is still required.

`<marketplace>` is the name the catalog registers under when it is added, and `<scope>` is the
scope the bootstrap chooses: `user`, `project`, or `local`. `marketplace add` and `install` default
to `user` when the flag is omitted, while `enable` auto-detects. Carry the same `<scope>` through
every command. Note the asymmetry: `marketplace add` spells it `--scope` only, while `install` and
`enable` also accept the `-s` short form. Registering at `user` while installing at `project`
leaves the marketplace declaration out of the project's checked-in settings, so a fresh clone or CI
agent carries the enabled plugin with no registered marketplace to resolve it from.

**The enable step is not optional.** Both plugins ship `defaultEnabled: false`, so they install
DISABLED. The install seeds the key but leaves the MCP server, and therefore every `dometrain`
tool, unavailable until `dometrain-mcp` is enabled ([Default
enablement](https://code.claude.com/docs/en/plugins-reference#default-enablement), which also notes
`claude plugin enable` auto-detects the scope when `-s` is omitted; passing it explicitly keeps the
sequence deterministic in CI). A bootstrap that stops after `install` looks successful and delivers
no tools.

**Rotating or clearing the key** belongs to `dometrain-mcp`: `/plugin configure
dometrain-mcp@<marketplace>` (interactive, any time). The `dometrain-mcp` README's "Rotating or
clearing the key" section carries the caveats: do not uninstall to rotate, and do not rely on
headless `--config` for a credential.

## Output

Report exactly one state: `disabled`, `connected`, or `failed or unverified`. Include the exact
next action when the state is not `connected`.

## Namespace-collision note

Dometrain ships its own official Claude Code plugin (`github.com/Dometrain/mcp`) whose
`plugin.json` `name` is also `"dometrain"`. If the user has that plugin enabled too, do not attempt
to detect the collision by comparing MCP tool-name prefixes. A true collision produces an
*identical*, not divergent, prefix, so no prefix comparison can distinguish "one plugin enabled" from
"two colliding plugins enabled." Point the user to this plugin's README collision warning instead.

## Boundaries

- Do not read, echo, log, copy, or persist any API key.
- Do not write the plugin cache, Claude Code user settings, or `pluginConfigs`, per the uniform
  setup contract (`docs/plugin-philosophy.md` "Setup is explicit and repeatable" in the
  marketplace repository).
- Do not call a Dometrain tool during setup. Resolution via tool inventory / `ToolSearch` is
  sufficient and spends no quota.
- Do not claim to have read `/mcp` connection status. No tool exposes it to a model turn.
