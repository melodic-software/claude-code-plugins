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
the stored token. `claude plugin install --config miro_api_token=<token>` is not a rotation
path — the flag seeds a value only on a fresh install and is ignored once the plugin is already
installed, so a headless rotation means uninstall then reinstall.

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
