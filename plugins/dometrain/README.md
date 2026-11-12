# dometrain

Claude Code skills that ground an implementation in [Dometrain](https://dometrain.com)'s video
courses: when to consult the course content, the tool workflow, timestamped citations, and quota
etiquette. The skills call a Dometrain MCP server, which this plugin does not ship.

- **Pointer**: for the server's endpoint, who can use it and how to get a key, fetch
  [1. Get an API key](https://github.com/Dometrain/mcp#1-get-an-api-key) in Dometrain's repository
  live.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install dometrain@melodic-software
```

## Getting the MCP server

Register a user-scope HTTP server named `dometrain`. The skills find its tools by the `dometrain`
server segment and tool name. The command reads the key from the `DOMETRAIN_API_KEY` environment
variable:

```shell
claude mcp add-json dometrain \
  '{"type":"http","url":"https://mcp.dometrain.com/mcp","headers":{"Authorization":"Bearer ${DOMETRAIN_API_KEY}"}}' \
  --scope user
```

After setting the variable, start a new session. To resolve the key from a secret store instead,
give the server a `headersHelper` script that prints the `Authorization` header as JSON.

- **Pointer**: for the variable name Dometrain's setup exports, fetch
  [2. Install](https://github.com/Dometrain/mcp#2-install) live; for the `headersHelper` contract, fetch
  [Use dynamic headers for custom authentication](https://code.claude.com/docs/en/mcp#use-dynamic-headers-for-custom-authentication)
  live; for the `headers` expansion, fetch
  [Environment variable expansion in `.mcp.json`](https://code.claude.com/docs/en/mcp#environment-variable-expansion-in-mcp-json)
  live.

A same-named `dometrain` server defined at another scope can win over this user-scope one, so the
skills may reach a different definition than the one registered above.

- **Pointer**: for which definition wins when a server is defined in more than one place, fetch
  [Scope hierarchy and precedence](https://code.claude.com/docs/en/mcp#scope-hierarchy-and-precedence)
  live.

## Enabling

The plugin **installs disabled** (`defaultEnabled: false`). Enable it with
`claude plugin enable dometrain` or the `/plugin` interface. It has no options.

Run `/dometrain:setup` to check that the MCP tools are available. The setup skill never reads or
exposes the key and never calls a Dometrain tool during setup. See
[Setup mechanism](#setup-mechanism) below for why.

## Dometrain's own official plugin, and why this one exists too

Dometrain ships its own Claude Code plugin at
[github.com/Dometrain/mcp](https://github.com/Dometrain/mcp), an alternative to this one. This
plugin ships skills only and uses the user-scope server above.

- **Pointer**: for that plugin's install steps, fetch
  [Claude Code](https://github.com/Dometrain/mcp#claude-code) live; for what it bundles and how it
  authenticates, fetch [2. Install](https://github.com/Dometrain/mcp#2-install) live.

**Do not enable both `dometrain` plugins simultaneously.** Pick one. Whether the two collide turns
on their manifest names and on how Claude Code namespaces a plugin by name, and neither is this
plugin's to promise.

- **Pointer**: for how a plugin's `name` namespaces its components, fetch
  [`name`](https://code.claude.com/docs/en/plugins/manifest-reference#name) live, and compare the
  `name` in each plugin's `.claude-plugin/plugin.json`.

## Grounding skill

`/dometrain:grounding` carries usage guidance adapted from Dometrain's own official
`dometrain-grounding` skill: when to consult Dometrain, the tool workflow, citation format, and
quota etiquette (same source repo as above, MIT licensed). Model-invocable: Claude
proactively consults it on a covered topic without an explicit command.

## Keeping the grounding skill in sync

The grounding skill's usage guidance is vendored, not hand-copied, from Dometrain's own skill
content. `/dometrain:update` is **maintainer-only and never model-invocable**. Its default
`--check` reports whether upstream has changed; `--apply` refreshes the vendored baseline and runs
only from a clone of this repository. See
[`skills/update/context/update.md`](skills/update/context/update.md) for the full integration
protocol.

## Setup mechanism

`/dometrain:setup check` reports one of `disabled`, `connected`, or `failed or unverified`,
derived from tool-inventory presence and Claude Code's own `ToolSearch`-surfaced connection
errors, not from reading `/mcp` connection status, which no callable tool exposes to a model
turn. See [`skills/setup/SKILL.md`](skills/setup/SKILL.md) for the full mechanism.

## Attribution

This plugin's `grounding` skill content is adapted from Dometrain's own official Claude Code
plugin ([github.com/Dometrain/mcp](https://github.com/Dometrain/mcp)), MIT licensed. The
Dometrain course content served by the MCP server itself is **not** covered by that license. It
remains Dometrain's proprietary content, accessible under your Dometrain Pro subscription and
[Dometrain's terms of service](https://dometrain.com/terms/).

## Development

This plugin ships no server code and no options. There is no build step;
`claude plugin validate plugins/dometrain` is the only local check.
