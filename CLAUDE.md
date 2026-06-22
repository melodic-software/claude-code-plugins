# Operating rules — AI agents working in this repo

This repository is a public Claude Code plugin marketplace. Plugins here must be reusable,
repo-agnostic, configurable by consumers, and safe in plugin form.

## Fresh-docs mandate (non-negotiable)

Operate only off current official documentation — never training-data recall, never a stale summary.
Before ANY change to this repo (a new plugin, a manifest edit, a structure change), WebFetch the
relevant page(s) below for current schema and behavior, and cite the URL. If a fact is not confirmed
from a fetched page this session, treat it as unverified and say so.

| Topic | Canonical URL |
|---|---|
| Create plugins | https://code.claude.com/docs/en/plugins |
| Plugins reference (schemas, variables, CLI) | https://code.claude.com/docs/en/plugins-reference |
| Plugin dependencies (version constraints) | https://code.claude.com/docs/en/plugin-dependencies |
| Create & distribute a marketplace | https://code.claude.com/docs/en/plugin-marketplaces |
| Discover & install plugins | https://code.claude.com/docs/en/discover-plugins |
| Skills | https://code.claude.com/docs/en/skills |
| Slash commands | https://code.claude.com/docs/en/commands |
| Hooks reference | https://code.claude.com/docs/en/hooks |
| Subagents | https://code.claude.com/docs/en/sub-agents |
| Settings | https://code.claude.com/docs/en/settings |
| Memory — CLAUDE.md, `.claude/rules/`, auto memory | https://code.claude.com/docs/en/memory |
| The `.claude` directory | https://code.claude.com/docs/en/claude-directory |
| MCP | https://code.claude.com/docs/en/mcp |
| Tools reference (monitors) | https://code.claude.com/docs/en/tools-reference |
| Docs index (discover any other page) | https://code.claude.com/docs/llms.txt |

Machine-readable JSON Schemas (editor validation for the JSON in this repo; Claude Code ignores the
`$schema` field at load time): `marketplace.json` →
`https://json.schemastore.org/claude-code-marketplace.json`, `plugin.json` →
`https://json.schemastore.org/claude-code-plugin-manifest.json` (published on SchemaStore).

## Design rules for plugins added here

- **Repo-agnostic.** No hardcoded paths, repo names, or project-specific values. Read the consumer's
  context via `${CLAUDE_PROJECT_DIR}` and the consumer's own `CLAUDE.md` / `.claude/rules`.
- **Configurable without editing the plugin.** Expose consumer choices through `userConfig`
  (`${user_config.KEY}`), never by requiring a fork or a hand-edit of the skill.
- **Plugin-form-safe.** Installed plugins run from an isolated cache — reference only files inside the
  plugin via `${CLAUDE_PLUGIN_ROOT}`; persist state in `${CLAUDE_PLUGIN_DATA}`. No `../` reach-outs.
- **No PII / secrets.** Public repo + permanent git history: scrub before the first commit, not after.
- **Versioned.** Set an explicit semver `version` in each `plugin.json` so consumers update on bumps.

## Process

The full design charter, extensibility model, plugin-form caveats, and per-plugin migration gate live
in [`docs/MIGRATION-PLAYBOOK.md`](docs/MIGRATION-PLAYBOOK.md). Follow it for every migration.
