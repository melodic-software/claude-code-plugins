# Cursor companion-host export

Build-time adapter that emits **Cursor-only** manifests from **Claude Code SSOTs**.
It is not a runtime shim and does not dual-read one file for two hosts.

Aligned with this marketplace's [PLUGIN-PHILOSOPHY](../../docs/PLUGIN-PHILOSOPHY.md)
(no silent dual-read shims), [MIGRATION-PLAYBOOK](../../docs/MIGRATION-PLAYBOOK.md)
(regenerate Cursor manifests from Claude SSOTs), and Melodic
`standards/conventions` — especially `shareable-artifact-design` (declare host
boundaries), `code-organization` (one concern per module; Claude SSOT vs Cursor
generated contract), `reference-dont-duplicate` (one generated description for
Cursor plugin + marketplace entry), and `source-authority-tiers` (Cursor/Claude
vendor docs are Canonical for their own hosts).

## Official contracts (re-fetch before changing this package)

| Host | Manifest | MCP | Secrets | Hooks |
|---|---|---|---|---|
| Claude Code | [`.claude-plugin/`](https://code.claude.com/docs/en/plugins-reference) | [`.mcp.json`](https://code.claude.com/docs/en/plugins-reference) | `userConfig` → `${user_config.KEY}` | Plugin `hooks/hooks.json` (Claude events + `${CLAUDE_PLUGIN_ROOT}`) |
| Cursor | [`.cursor-plugin/`](https://cursor.com/docs/reference/plugins) | [`mcp.json`](https://cursor.com/docs/reference/plugins) | `variables` → `${VAR}` (Plugins → Configure) | Plugin hooks: Cursor schema ([hooks](https://cursor.com/docs/hooks)); Claude *settings* hooks are a different load path ([third-party hooks](https://cursor.com/docs/reference/third-party-hooks)) |

## Ownership

| Path | Owner |
|---|---|
| `.claude-plugin/**`, `plugins/*/.claude-plugin/**`, `plugins/*/.mcp.json`, `plugins/*/hooks/hooks.json` | Claude SSOT — never written by this package |
| `.cursor-plugin/**`, `plugins/*/.cursor-plugin/**`, `plugins/*/mcp.json` | Generated Cursor artifacts — never hand-edit |

## Module map (one concern each)

| Module | Concern |
|---|---|
| `paths.mjs` | Path ownership and Claude SSOT reads |
| `json.mjs` | Shared JSON helpers |
| `description.mjs` | Cursor-facing description rewrite (honest capability) |
| `mcp.mjs` | `.mcp.json` → `mcp.json` + `variables` |
| `plugin.mjs` | Cursor `plugin.json` + hooks stub decision |
| `marketplace.mjs` | Cursor marketplace catalog |
| `artifacts.mjs` | Plan write set from Claude catalog |
| `io.mjs` | Write + drift check + orphan removal |
| `cli.mjs` | argv / exit codes |
| `test.mjs` | Unit tests for translation rules |

## Design rules

- **No dual-read windows** — each host reads its own files; this package only *writes* Cursor outputs from Claude inputs at build time.
- **No mixed concerns** — Claude hook scripts (`hooks/*.sh`) stay Claude-payload-specific; Cursor does not call them through a compatibility wrapper.
- **Native-first per host** — Cursor MCP uses Cursor `variables` / `mcp.json`; Claude MCP stays on `userConfig` / `.mcp.json`.
- **Honest capability** — Claude plugin hooks are not claimed as Cursor plugin hooks; Cursor `plugin.json` points `hooks` at an empty Cursor-native stub under `.cursor-plugin/` so Cursor does not parse Claude `hooks/hooks.json` (specifying `hooks` replaces discovery — [plugins reference](https://cursor.com/docs/reference/plugins)).

## Commands

```shell
node scripts/generate-cursor-manifests.mjs           # write
node scripts/generate-cursor-manifests.mjs --check   # CI drift gate
node scripts/cursor-export/test.mjs                  # unit tests
```
