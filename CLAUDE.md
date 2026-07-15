# Operating rules — AI agents working in this repo

This repository is a private Claude Code plugin marketplace. Plugins here must still be reusable,
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
- **Configurable without editing the plugin.** Use `userConfig` (`${user_config.KEY}`) for personal or
  administrator-provided scalars. Put tracked repository policy and team conventions in a documented
  consumer-project file. Never require a fork or a hand-edit of the installed plugin.
- **Plugin-form-safe.** Installed plugins run from an isolated cache — reference only files inside the
  plugin via `${CLAUDE_PLUGIN_ROOT}`; persist state in `${CLAUDE_PLUGIN_DATA}`. No `../` reach-outs.
- **No PII / secrets.** Git history is durable: scrub before the first commit, not after.
- **Versioned.** Set an explicit semver `version` in each `plugin.json` so consumers update on bumps.
- **Security-reviewed.** Every plugin clears the playbook's plugin-acceptance security review before publish —
  code execution, remote MCP servers, config secrets, cache isolation, data egress, and third-party trust.
  Deny by default on unjustified egress or trust delegation.

## Process

The durable design rules live in [`docs/PLUGIN-PHILOSOPHY.md`](docs/PLUGIN-PHILOSOPHY.md). The
extensibility model, plugin-form caveats, per-plugin migration gate, and plugin-acceptance security
review live in [`docs/MIGRATION-PLAYBOOK.md`](docs/MIGRATION-PLAYBOOK.md). Follow both for every
migration.

## Branching & PRs

PRs required; squash merge; Conventional Commits branch `<type>/<description>` (enforced here by
`.github/workflows/pr-title.yml`). Org convention home: `melodic-software/standards` `conventions/`.
