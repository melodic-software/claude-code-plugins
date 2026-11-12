---
description: "Verify that the Dometrain MCP tools are available to the Dometrain grounding skills, without reading or exposing any API key. Use when: 'set up Dometrain', 'configure Dometrain', 'Dometrain setup', the Dometrain MCP server is unavailable, or a Dometrain tool reports an authentication error. Actions: check (read-only verification, default and only action). This plugin has no options and ships no server: the tools come from a user-scope dometrain server, so there is nothing an apply could write."
argument-hint: "[check]"
user-invocable: true
disable-model-invocation: true
---

## Purpose

Report whether a Dometrain MCP server is reachable from this session, without reading, printing,
or writing any API key. This plugin ships skills only. The tools come from a user-scope
`dometrain` MCP server the user registered, per the README's
[Getting the MCP server](../../README.md#getting-the-mcp-server).

That server exposes its tools under a `dometrain` server segment. This skill matches on the
server segment and tool name in the runtime inventory and never on a fixed prefix, because Claude
Code owns the prefix format and can change it.

Check-only per the uniform setup contract's carve-out for a plugin with no options: `check`
(default and only action) verifies and reports. The server keeps its credential outside this
skill, so it never manages it.

**Mechanism note (why this skill does not read `/mcp`):** `/mcp` is a human-run interactive
command. No tool exposes its output to a model turn. The one model-visible signal for a failed
remote server is the connection error Claude Code itself reports to Claude, which this skill reads
when it is present and never assumes when it is absent. This skill is built around that
constraint, not around reading `/mcp` connection status directly.

- **Pointer**: when deciding what a missing Dometrain tool can tell this skill, fetch
  [How Claude learns that a server failed](https://code.claude.com/docs/en/mcp#how-claude-learns-that-a-server-failed)
  live.

## Task

1. Check whether a Dometrain tool (e.g. `list_courses`, `search_dometrain`) is present in the
   current tool inventory, matched by the `dometrain` server segment and the tool name. Do not inspect
   settings files, environment variables, process arguments, debug logs, credential stores, or
   any key.
2. When a Dometrain tool resolves (via direct tool-list presence or a successful `ToolSearch`
   match), report **connected**. Do not claim the credential has valid API access beyond that:
   resolution is the strongest signal this skill can observe. For which rejections Dometrain's
   server returns and what each means, fetch
   [Troubleshooting](https://github.com/Dometrain/mcp#troubleshooting) live.
3. When no Dometrain tool resolves and `ToolSearch` returned no connection
   error for a `dometrain` server, report **disabled**: no server is present. Point to the
   README's [Getting the MCP server](../../README.md#getting-the-mcp-server) for registering a
   user-scope server. Do not run the command for the user. For a non-interactive install (CI, a
   fleet bootstrap, a scripted machine setup), point to the headless path below.
4. When a user-scope server is registered but no tool resolves, report **failed or unverified**:
   - If `ToolSearch` returned a connection error for the `dometrain` server, quote it verbatim.
   - Otherwise do not assert why. Whether a failed connection reaches this turn depends on
     configuration this skill cannot inspect (see the mechanism note's pointer in
     [Purpose](#purpose)).
     Direct the user to run `/mcp` themselves rather than claim knowledge it does not have.
   - Do not send the user to `/plugin configure`: point them to `claude mcp list` for a
     missing-variable warning on the `dometrain` entry and to the README's
     [Getting the MCP server](../../README.md#getting-the-mcp-server), and tell them to start a
     new session after setting the variable. For how Claude Code expands it, fetch
     [Environment variable expansion in `.mcp.json`](https://code.claude.com/docs/en/mcp#environment-variable-expansion-in-mcp-json)
     live.

## Headless installation

For a non-interactive install such as CI, a fleet bootstrap, or a scripted machine setup, install
and enable the skills, then register the user-scope server per the README's
[Getting the MCP server](../../README.md#getting-the-mcp-server). Every step is required. At
`user` scope, on a CLI that supports `--marketplace` on `install`, add the marketplace and install
in one step:

```shell
claude plugin install dometrain --marketplace <source> -s user
claude plugin enable dometrain -s user
```

At `project` or `local` scope, or on an older CLI, keep the two-step form, so the marketplace is
registered in the same scope as the install:

```shell
claude plugin marketplace add <source> --scope <scope>
claude plugin install dometrain@<marketplace> -s <scope>
claude plugin enable dometrain -s <scope>
```

- **Pointer**: when choosing between the two forms, fetch
  [Plugin commands reference: plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
  (the `--marketplace` row and its minimum version) and
  [Add a marketplace and install in one command](https://code.claude.com/docs/en/plugins/install#add-a-marketplace-and-install-in-one-command)
  (which scope the added marketplace lands in) live.

`<marketplace>` is the name the catalog registers under when it is added, and `<scope>` is the
scope the bootstrap chooses: `user`, `project`, or `local`. Pass the scope explicitly on every
command and carry the same `<scope>` through all of them.

- **Pointer**: when a command's scope default or flag spelling matters, fetch
  [plugin marketplace add](https://code.claude.com/docs/en/plugins/cli-reference#plugin-marketplace-add),
  [plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install) and
  [plugin enable](https://code.claude.com/docs/en/plugins/cli-reference#plugin-enable) live.

Registering at `user` while installing at `project`
leaves the marketplace declaration out of the project's checked-in settings, so a fresh clone or CI
agent carries the enabled plugin with no registered marketplace to resolve it from.

**The enable step is not optional.** This plugin's marketplace entry sets `defaultEnabled: false`,
so a bootstrap never ends at `install`. Pass `-s` to
[`claude plugin enable`](https://code.claude.com/docs/en/plugins/cli-reference#plugin-enable)
explicitly, so the sequence stays deterministic in CI.

- **Pointer**: for what `defaultEnabled: false` means for a fresh install, fetch
  [`defaultEnabled`](https://code.claude.com/docs/en/plugins/manifest-reference#defaultenabled)
  live.

## Output

Report exactly one state: `disabled`, `connected`, or `failed or unverified`. Include the exact
next action when the state is not `connected`.

## Namespace-collision note

Dometrain ships its own Claude Code plugin (`github.com/Dometrain/mcp`). If the user has that
plugin enabled too, do not attempt to detect a collision by comparing MCP tool-name prefixes: the
prefix cannot tell one enabled plugin from two that collide. Point the user to this plugin's README
collision warning instead.

- **Pointer**: for that plugin's manifest `name`, read `.claude-plugin/plugin.json` in
  [Dometrain's repository](https://github.com/Dometrain/mcp) live.

## Boundaries

- Do not read, echo, log, copy, or persist any API key.
- Do not write the plugin cache, Claude Code user settings, or `pluginConfigs`, per the uniform
  setup contract (`docs/plugin-philosophy.md` "Setup is explicit and repeatable" in the
  marketplace repository).
- Do not call a Dometrain tool during setup. Resolution via tool inventory / `ToolSearch` is
  sufficient and spends no quota.
- Do not claim to have read `/mcp` connection status. No tool exposes it to a model turn.
