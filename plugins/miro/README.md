# miro

A Claude Code plugin that bundles a local Miro MCP server, giving Claude tools to
create and manage boards, sticky notes, shapes, frames, connectors, and tags for
EventStorming, brainstorming, and diagramming workflows.

This is the marketplace's first plugin to ship its own MCP server. The server is a
single self-contained Node artifact (`dist/index.min.js`) invoked over local `stdio`, so
enabling the plugin adds the Miro tools with no separate install, no registry token,
and no `npx` dependency (a bundled `node <server>` sidesteps the Windows bare-`npx`
spawn bug, [anthropics/claude-code#58510](https://github.com/anthropics/claude-code/issues/58510)).

## Enabling and configuration

The plugin **installs disabled** (`defaultEnabled: false`) — a bundled MCP server that
connects to an external, credentialed service is opt-in, not on by default. Enable it
with `claude plugin enable miro` or the `/plugin` interface, and provide a token:

| Option | Storage | Purpose |
|---|---|---|
| `miro_api_token` | Claude Code secure credential storage (never `settings.json`) | Miro REST API token. Required — the server exits at startup without it. |

Get a token from <https://miro.com/app/settings/user-profile/apps>. Claude Code prompts
for it at enable time (masked input). Sensitive values use the macOS Keychain, or
`~/.claude/.credentials.json` on platforms where no supported keychain is available;
the token is substituted into the server's
`MIRO_API_TOKEN` environment variable at launch.

Run `/miro:setup` to check enablement and MCP availability or, with explicit confirmation,
perform a minimal read-only API credential check. The setup skill never reads or exposes the
token and never invokes a mutating Miro tool.

### Rotating or clearing the token

Once set, a sensitive `userConfig` value has no dedicated reconfigure entry in the `/plugin`
detail view, and the `/mcp` server menu's "Clear authentication" applies to OAuth-based servers
only — it is not the rotation path for a token supplied through `userConfig` (the bundled stdio
server receives `miro_api_token` as its `MIRO_API_TOKEN` environment variable, never through an
OAuth flow). To change or clear the token at any time, run:

```text
/plugin configure miro
```

That reopens the same configuration screen shown at first enable, letting you overwrite or blank
the stored token. The headless `--config` flag on `claude plugin install` is not a rotation
path: it seeds a value only on a fresh install and is ignored once the plugin is already
installed, so rotating headlessly means uninstalling and reinstalling. Prefer the interactive
prompt — it masks input, where a token passed on the command line lands in shell history and the
process table.

## Tools

The server registers Miro operations grouped by concern: boards, sticky notes, frames,
tags, connectors, bulk create, and overlap detection. Read-only tools annotate
`readOnlyHint` so Claude can parallelize them; mutating tools serialize.

## Architecture

Stdio MCP server ([`@modelcontextprotocol/sdk`](https://github.com/modelcontextprotocol/typescript-sdk))
on Node ≥ 24 — cross-platform, no per-OS path divergence at the stdio boundary. Tool
definitions are thin wrappers over the [`@mirohq/miro-api`](https://www.npmjs.com/package/@mirohq/miro-api)
client; the request/response and error-shaping logic lives in `src/`.

The TypeScript in `src/` is the single source of truth. `dist/index.min.js` is generated
build output — an [esbuild](https://esbuild.github.io/) single-file bundle of the
source and all runtime dependencies. Plugin install runs no build step, so the bundle
is committed; CI rebuilds it from source with the pinned toolchain and fails on any
drift, so the committed artifact is always exactly what the source produces.

## Development

```shell
cd plugins/miro
npm install
npm run typecheck     # tsc --noEmit
npm test              # vitest (with coverage + typecheck)
npm run lint          # biome check
npm run bundle        # regenerate dist/index.min.js from src/
npm run verify-bundle # fail if dist/index.min.js drifts from src/
```

After editing `src/`, run `npm run bundle` and commit the regenerated `dist/index.min.js`
alongside the source change.

<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->

### Options reference

Generated from this plugin's `.claude-plugin/plugin.json`. Every option Claude Code
will prompt for when the plugin is enabled, with the environment variable each hook
reads it from.

| Option | Type | Default | Environment variable | Description |
| --- | --- | --- | --- | --- |
| `miro_api_token` | string | *(none)* | `CLAUDE_PLUGIN_OPTION_MIRO_API_TOKEN` | **Sensitive** — stored in the OS keychain or protected credentials file. Miro REST API token from https://miro.com/app/settings/user-profile/apps. Required — the bundled MCP server exits at startup without it. Stored by Claude Code in secure credential storage, never settings.json. |

### How to set these

Three supported routes, in the order most people want them:

1. **Interactively** — Claude Code prompts for declared options when you enable the
   plugin. To change them later: `/plugin configure miro`.
2. **Headless, at install time** — repeat `--config` for each option. Replace
   `<marketplace>` with the marketplace you installed this plugin from:

   ```shell
   claude plugin install miro@<marketplace> --config miro_api_token=<value>
   ```

3. **By hand, in settings** — add the value under `pluginConfigs` in your **user**
   settings (`~/.claude/settings.json`):

   ```json
   {
     "pluginConfigs": {
       "miro@<marketplace>": {
         "options": {
           "miro_api_token": <value>
         }
       }
     }
   }
   ```

   Plugin option values are read from **user**, `--settings`, and managed settings
   only — **not** from a project's `.claude/settings.json`. To vary behavior per
   repository, enable or disable the plugin in that project's `enabledPlugins`
   instead of setting an option there.

Do not set the `CLAUDE_PLUGIN_OPTION_*` variables yourself. They are how Claude Code
hands a configured value to a hook process; the value comes from the routes above.

### Upstream documentation

- [User configuration](https://code.claude.com/docs/en/plugins-reference#user-configuration) — the `userConfig` schema and the `CLAUDE_PLUGIN_OPTION_<KEY>` export
- [Plugin settings](https://code.claude.com/docs/en/settings#plugin-settings) — `enabledPlugins`, `extraKnownMarketplaces`, `pluginConfigs`
- [Configuration scopes](https://code.claude.com/docs/en/settings#configuration-scopes) — user vs project vs local precedence
- [Manage installed plugins](https://code.claude.com/docs/en/discover-plugins#manage-installed-plugins) — enabling, disabling, `/plugin list`

<!-- END GENERATED: plugin options -->
