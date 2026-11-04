@AGENTS.md

# Operating rules — AI agents working in this repo

This repository is a private Claude Code plugin marketplace. Plugins here must still be reusable,
repo-agnostic, configurable by consumers, and safe in plugin form.

## Fresh-docs mandate (non-negotiable)

[`docs/OFFICIAL-DOCS.md`](docs/OFFICIAL-DOCS.md) is the canonical index of every plugin-relevant
official page, plus the self-updating `llms.txt` master list for anything it omits.

**Scope** — a change touching a plugin manifest, a marketplace schema, a hook contract, or documented
harness behavior, which includes the contract surface of every plugin component that index covers.
The discriminator is the surface, not the file: a skill's frontmatter, a subagent's fields, or an
`.mcp.json` entry is a contract change and is in; that same skill's prose body is a prose edit and is
out. Formatting and mechanical edits are out.

Inside that scope, operate only off current official documentation — never training-data recall,
never a stale summary. Before the change, open the index, WebFetch the page(s) it points to for
current schema and behavior, and cite the URL. If a fact is not confirmed from a page fetched this
session, treat it as unverified and say so. Non-negotiable.

Machine-readable JSON Schemas (editor validation for the JSON in this repo; Claude Code ignores the
`$schema` field at load time): `marketplace.json` →
`https://json.schemastore.org/claude-code-marketplace.json`, `plugin.json` →
`https://json.schemastore.org/claude-code-plugin-manifest.json` (published on SchemaStore).

Cursor dual-target artifacts are generated from the Claude SSOTs by
`node scripts/generate-cursor-manifests.mjs` (package: `scripts/cursor-export/`). Never
hand-edit them; regenerate after catalog, `plugin.json`, `.mcp.json`, or Claude
`hooks/hooks.json` presence changes. Generated outputs: `.cursor-plugin/**`,
`plugins/*/.cursor-plugin/**` (including empty Cursor-native `hooks.json` stubs when a
Claude plugin ships hooks — so Cursor does not discover Claude `hooks/hooks.json`), and
`plugins/*/mcp.json` when Claude `.mcp.json` needs `${user_config.*}` /
`${CLAUDE_PLUGIN_ROOT}` ported to Cursor `variables` / `${VAR}`. Cursor schema:
`https://cursor.com/docs/reference/plugins`; hooks: `https://cursor.com/docs/hooks`;
Claude settings-hook compatibility (not plugin hooks.json):
`https://cursor.com/docs/reference/third-party-hooks`.

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

PRs required; squash merge; branch `<type>/<description>`. `.github/workflows/pr-title.yml` enforces
the PR-title convention (squash merge sets the commit subject to the PR title). Org convention home:
`melodic-software/standards` `conventions/`.

`.github/workflows/pr-issue-linkage.yml` is a required check on the PR **body** — write the body to
this contract when opening the PR (through any surface: `gh`, API, or MCP tools), or the failure
costs a full CI round trip to discover. After stripping HTML comments, the body must carry BOTH:

1. a native closing keyword — `Closes`/`Fixes`/`Resolves #N` (or `owner/repo#N`) — or the literal
   line `No linked issue` when the PR closes nothing; and
2. a non-empty `## Related` section (`N/A` when nothing applies).

Fill in `.github/pull_request_template.md`; an unedited template fails, because its guidance lives
inside the HTML comments the check strips. A bare `Closes #` with no number also fails.

Enforcement at authoring time: a checked-in PreToolUse gate
(`.claude/hooks/pr-linkage-mcp-gate.sh`, wired in `.claude/settings.json`) blocks an MCP-created PR
body that would fail the check even in a session with no plugins; the source-control plugin
enforces the same contract on both surfaces (`pr-body-linkage-gate` for `gh pr create`/`edit`,
`pr-linkage-mcp-gate` for the MCP tools) wherever it is installed.
