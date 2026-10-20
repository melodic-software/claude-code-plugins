# dometrain

Claude Code skills that ground an implementation in [Dometrain](https://dometrain.com)'s video
courses: when to consult the course content, the tool workflow, timestamped citations, and quota
etiquette. The skills call a Dometrain MCP server, which this plugin does not ship. Dometrain's
hosted server (`https://mcp.dometrain.com/mcp`) is closed-source and requires an active
[Dometrain Pro](https://dometrain.com/dometrain-pro/) subscription.

## Getting the MCP server

Register a user-scope HTTP server named `dometrain`. The skills find its tools by the `dometrain`
server segment and tool name. To read the key from `DOMETRAIN_API_KEY`, the variable Dometrain's own
plugin reads:

```shell
claude mcp add-json dometrain \
  '{"type":"http","url":"https://mcp.dometrain.com/mcp","headers":{"Authorization":"Bearer ${DOMETRAIN_API_KEY}"}}' \
  --scope user
```

Claude Code expands the variable from its own environment at connect time, so a variable set after
it started needs a new session. To resolve the key from a secret store instead, give the server a
`headersHelper` script that prints the `Authorization` header as JSON.

- **Pointer**: for the `headers` expansion and `headersHelper` contract, fetch
  [MCP server configuration](https://code.claude.com/docs/en/mcp) live.
- **As of**: 2026-10-20
- **Recheck trigger**: that page changes how `headers` variables expand or how `headersHelper`
  runs.

## Enabling

The plugin **installs disabled** (`defaultEnabled: false`). Enable it with
`claude plugin enable dometrain` or the `/plugin` interface. It has no options.

Run `/dometrain:setup` to check that the MCP tools are available. The setup skill never reads or
exposes the key and never calls a Dometrain tool during setup. See
[Setup mechanism](#setup-mechanism) below for why.

## Dometrain's own official plugin, and why this one exists too

Dometrain ships its own official Claude Code plugin and marketplace at
[github.com/Dometrain/mcp](https://github.com/Dometrain/mcp) (MIT licensed), installable in one
step on a CLI that supports `--marketplace` on `install`:

```shell
claude plugin install dometrain --marketplace dometrain/mcp
```

On an older CLI, add the marketplace first:

```shell
claude plugin marketplace add dometrain/mcp
claude plugin install dometrain@dometrain
```

- **Pointer**: when checking whether your CLI takes the one-step form, fetch
  [Plugin commands reference: plugin install](https://code.claude.com/docs/en/plugins/cli-reference#plugin-install)
  live.
- **As of**: 2026-10-10
- **Recheck trigger**: the `--marketplace` row of `plugin install` changes.

That plugin bundles the server and authenticates through the `DOMETRAIN_API_KEY` shell variable.
This plugin ships skills only and uses the user-scope server above.

**Do not enable both `dometrain` plugins simultaneously.** Both share the identical plugin name
(`"dometrain"`) in their respective `plugin.json` manifests. Install identity is
marketplace-scoped (`dometrain@<marketplace>` and `dometrain@dometrain` are distinct,
coexistable install identities), but skill and MCP-tool namespacing is driven by `plugin.json`
`name` alone, and Claude Code's behavior for two enabled plugins sharing an
identical name is undocumented. Pick one.

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
