# dometrain

Claude Code skills that ground an implementation in [Dometrain](https://dometrain.com)'s video
courses: when to consult the course content, the tool workflow, timestamped citations, and quota
etiquette. The skills call a Dometrain MCP server, which this plugin does not ship. Dometrain's
hosted server (`https://mcp.dometrain.com/mcp`) is closed-source and requires an active
[Dometrain Pro](https://dometrain.com/dometrain-pro/) subscription.

## Getting the MCP server

Two supported setups. Pick one:

| Your setup | Install | Result |
|---|---|---|
| No Dometrain MCP server yet | `dometrain` and [`dometrain-mcp`](../dometrain-mcp) | Zero setup beyond entering the key |
| Your own user-scope `dometrain` server | `dometrain` only | Skills use your server; no duplicate-server warning |

The skills find the tools by the `dometrain` server segment and tool name, so they work whether
`dometrain-mcp` supplies the server or you configured your own.

Claude Code matches plugin servers to already-configured servers by endpoint, so installing
`dometrain-mcp` next to your own server at the same URL produces a duplicate-server warning in
`/plugin`. Install only `dometrain` in that case.

### Adding your own server

Register a user-scope HTTP server named `dometrain`. To read the key from `DOMETRAIN_API_KEY`, the
variable Dometrain's own plugin reads:

```shell
claude mcp add-json dometrain \
  '{"type":"http","url":"https://mcp.dometrain.com/mcp","headers":{"Authorization":"Bearer ${DOMETRAIN_API_KEY}"}}' \
  --scope user
```

The [`dometrain-mcp` README](../dometrain-mcp/README.md#using-your-own-server-instead) has this
recipe with its caveats and a `vault-exec` recipe for machines that resolve keys from a secret
store.

## Enabling

The plugin **installs disabled** (`defaultEnabled: false`). Enable it with
`claude plugin enable dometrain` or the `/plugin` interface. It has no options.

Run `/dometrain:setup` to check that the MCP tools are available. The setup skill never reads or
exposes the key and never calls a Dometrain tool during setup. See
[Setup mechanism](#setup-mechanism) below for why.

## Upgrading from 0.4.x

Before 0.5.0 this plugin bundled the server and the `dometrain_api_key` option. Both moved to
`dometrain-mcp`. To keep the bundled server, install `dometrain-mcp` and enter the key again there:
Claude Code does not carry `pluginConfigs` between plugins. A user-scope `dometrain` server needs
no change. Permission rules written against `mcp__plugin_dometrain_dometrain__*` need the new
prefix, `mcp__plugin_dometrain-mcp_dometrain__*`.

## Dometrain's own official plugin, and why this one exists too

Dometrain ships its own official Claude Code plugin and marketplace at
[github.com/Dometrain/mcp](https://github.com/Dometrain/mcp) (MIT licensed), installable via:

```shell
claude plugin marketplace add dometrain/mcp
claude plugin install dometrain@dometrain
```

That plugin's `.mcp.json` authenticates via a shell environment variable
(`${DOMETRAIN_API_KEY}`). This marketplace's `dometrain-mcp` offers the key entered once through
Claude Code's **native masked `userConfig` prompt**, stored in secure credential storage, with no
shell environment variable to export.

**Do not enable both `dometrain` plugins simultaneously.** Both share the identical plugin name
(`"dometrain"`) in their respective `plugin.json` manifests. Install identity is
marketplace-scoped (`dometrain@<marketplace>` and `dometrain@dometrain` are distinct,
coexistable install identities), but skill and MCP-tool namespacing is driven by `plugin.json`
`name` alone, and Claude Code's behavior for two enabled plugins sharing an
identical name is genuinely undocumented. Pick one.

## Grounding skill

`/dometrain:grounding` carries usage guidance adapted from Dometrain's own official
`dometrain-grounding` skill: when to consult Dometrain, the tool workflow, citation format, and
quota etiquette (same source repo as above, MIT licensed). Model-invocable: Claude
proactively consults it on a covered topic without an explicit command.

## Keeping the grounding skill in sync

The grounding skill's usage guidance is vendored, not hand-copied, from Dometrain's own skill
content. `/dometrain:sync` is **maintainer-only, never model-invocable, and report-only for
consumers**. It checks whether upstream has changed. See
[`skills/sync/context/update.md`](skills/sync/context/update.md) for the full integration
protocol; only a maintainer working in a clone of this repository refreshes the baseline.

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
