# Official docs index

This is a link index into Claude Code's official documentation, scoped to pages relevant to
authoring, distributing, or consuming plugins in this marketplace. It exists so an agent or
contributor can jump straight to the current canonical page instead of guessing a URL or trusting
training-data recall.

> [!WARNING]
> **This file goes stale. The platform changes constantly.** Always re-fetch the linked page before
> acting on it — never trust this file's descriptions, and never trust remembered content from a
> prior fetch. The authoritative, self-updating master list is
> [`https://code.claude.com/docs/llms.txt`](https://code.claude.com/docs/llms.txt); if a page listed
> here is missing from it, or a page you need isn't listed here, treat `llms.txt` as the source of
> truth and update this file. Every row below was verified against a live fetch on the date shown —
> that date is the ceiling on how current the row still is, not a guarantee. The
> [upstream-drift convention](conventions/upstream-drift/README.md) owns this stamp-and-trigger
> discipline.

## Plugin components → doc page

One row per plugin component type, per the current [Plugins reference](https://code.claude.com/docs/en/plugins-reference).
`Commands` is the legacy flat-markdown form of a skill — the [Skills](https://code.claude.com/docs/en/skills)
page is authoritative for both. Statusline is not its own plugin component: it is one of the two
settings keys (`subagentStatusLine`) a plugin's `settings.json` may set. Channels are declared via a
`channels` manifest field bound to an MCP server, not a separate file location.

| Component | Official doc page | Verified date |
|---|---|---|
| Skills (`skills/`) | <https://code.claude.com/docs/en/skills> | 2026-07-17 |
| Commands — legacy flat-file skills (`commands/`) | <https://code.claude.com/docs/en/commands> | 2026-07-17 |
| Agents / subagents (`agents/`) | <https://code.claude.com/docs/en/sub-agents> | 2026-07-17 |
| Hooks (`hooks/hooks.json`) | <https://code.claude.com/docs/en/hooks> | 2026-07-17 |
| MCP servers (`.mcp.json`) | <https://code.claude.com/docs/en/mcp> | 2026-07-17 |
| LSP servers (`.lsp.json`) | <https://code.claude.com/docs/en/plugins-reference#lsp-servers> | 2026-07-17 |
| Output styles (`output-styles/`) | <https://code.claude.com/docs/en/output-styles> | 2026-07-17 |
| Themes (`themes/`) | <https://code.claude.com/docs/en/plugins-reference#themes> | 2026-07-17 |
| Monitors (`monitors/monitors.json`) | <https://code.claude.com/docs/en/plugins-reference#monitors> | 2026-07-17 |
| Channels (`channels` manifest field) | <https://code.claude.com/docs/en/channels> | 2026-07-17 |
| Executables (`bin/`) | <https://code.claude.com/docs/en/plugins-reference#file-locations-reference> | 2026-07-17 |
| Settings (`settings.json` defaults) | <https://code.claude.com/docs/en/settings> | 2026-07-17 |
| Dependencies (`dependencies` manifest field) | <https://code.claude.com/docs/en/plugin-dependencies> | 2026-07-17 |

## Authoring

| Page | Official doc page | Verified date |
|---|---|---|
| Create plugins | <https://code.claude.com/docs/en/plugins> | 2026-07-17 |
| Plugins reference (schemas, variables, CLI) | <https://code.claude.com/docs/en/plugins-reference> | 2026-07-17 |
| Skills | <https://code.claude.com/docs/en/skills> | 2026-07-17 |
| Slash commands | <https://code.claude.com/docs/en/commands> | 2026-07-17 |
| Hooks reference | <https://code.claude.com/docs/en/hooks> | 2026-07-17 |
| Automate actions with hooks (guide) | <https://code.claude.com/docs/en/hooks-guide> | 2026-07-17 |
| Subagents | <https://code.claude.com/docs/en/sub-agents> | 2026-07-17 |
| Dynamic workflows — script-held orchestration, runtime agent caps | <https://code.claude.com/docs/en/workflows> | 2026-07-26 |
| MCP | <https://code.claude.com/docs/en/mcp> | 2026-07-17 |
| Connect to MCP servers (quickstart) | <https://code.claude.com/docs/en/mcp-quickstart> | 2026-07-17 |
| Output styles | <https://code.claude.com/docs/en/output-styles> | 2026-07-17 |
| Statusline | <https://code.claude.com/docs/en/statusline> | 2026-07-17 |
| Push events into a session with channels | <https://code.claude.com/docs/en/channels> | 2026-07-17 |
| Channels reference | <https://code.claude.com/docs/en/channels-reference> | 2026-07-17 |
| Sandboxing the Bash tool | <https://code.claude.com/docs/en/sandboxing> | 2026-07-17 |
| Sandbox environments | <https://code.claude.com/docs/en/sandbox-environments> | 2026-07-17 |
| Run parallel sessions with worktrees | <https://code.claude.com/docs/en/worktrees> | 2026-07-17 |
| Tools reference (includes the Monitor tool) | <https://code.claude.com/docs/en/tools-reference> | 2026-07-17 |

## Distribution / marketplace

| Page | Official doc page | Verified date |
|---|---|---|
| Create & distribute a marketplace | <https://code.claude.com/docs/en/plugin-marketplaces> | 2026-07-17 |
| Discover & install plugins | <https://code.claude.com/docs/en/discover-plugins> | 2026-07-17 |
| Plugin dependencies (version constraints) | <https://code.claude.com/docs/en/plugin-dependencies> | 2026-07-17 |
| Recommend plugins for your org (plugin relevance) | <https://code.claude.com/docs/en/plugin-relevance> | 2026-07-17 |
| Recommend your plugin from your CLI (plugin hints) | <https://code.claude.com/docs/en/plugin-hints> | 2026-07-17 |
| Plugins in the Agent SDK | <https://code.claude.com/docs/en/agent-sdk/plugins> | 2026-07-17 |

The Agent SDK's own skills/hooks/subagents/MCP pages (`agent-sdk/skills`, `agent-sdk/hooks`,
`agent-sdk/subagents`, `agent-sdk/mcp`) describe those concepts for custom SDK-built agent hosts, not
for authoring or distributing a Claude Code CLI plugin — deliberately out of scope here. Only
`agent-sdk/plugins` is in scope, because it covers how this repo's plugins behave when loaded by an
SDK-based host.

## Configuration / settings

| Page | Official doc page | Verified date |
|---|---|---|
| Settings | <https://code.claude.com/docs/en/settings> | 2026-07-17 |
| Server-managed settings | <https://code.claude.com/docs/en/server-managed-settings> | 2026-07-17 |
| Control MCP server access for your organization | <https://code.claude.com/docs/en/managed-mcp> | 2026-07-17 |
| Memory — CLAUDE.md, `.claude/rules/`, auto memory | <https://code.claude.com/docs/en/memory> | 2026-07-17 |
| The `.claude` directory | <https://code.claude.com/docs/en/claude-directory> | 2026-07-17 |
| Permissions | <https://code.claude.com/docs/en/permissions> | 2026-07-17 |
| Permission modes | <https://code.claude.com/docs/en/permission-modes> | 2026-07-17 |
| Environment variables | <https://code.claude.com/docs/en/env-vars> | 2026-07-17 |

## Reference / schemas

| Page | Official doc page | Verified date |
|---|---|---|
| Docs index (discover any other page) | <https://code.claude.com/docs/llms.txt> | 2026-07-17 |
| CLI reference | <https://code.claude.com/docs/en/cli-reference> | 2026-07-17 |
| Error reference | <https://code.claude.com/docs/en/errors> | 2026-07-17 |
| Glossary | <https://code.claude.com/docs/en/glossary> | 2026-07-17 |
| Release changelog — per-version behavior changes | <https://code.claude.com/docs/en/changelog> | 2026-07-26 |

**On citing the changelog.** It is indexed here because the prose pages can lag it: a behavior can
change in a release and reach the topic page a release or more later, and when the two disagree the
changelog is the one that matches the running harness. Two handling rules follow. First, the
rendered page summarizes; fetch the raw markdown (`…/changelog.md`, or the upstream
`CHANGELOG.md`) when you need a byte-exact version-pinned quote, because a summarizing fetch of this
page has produced inconsistent readings of the same entries. Second, a changelog citation records
what changed **in a version** — always pin the version, and pair it with the topic page rather than
replacing it, since the topic page stays authoritative for mechanism and semantics.

Machine-readable JSON Schemas (editor validation only; Claude Code ignores the `$schema` field at
load time — already cited in this repo's `CLAUDE.md`): `marketplace.json` →
[`https://json.schemastore.org/claude-code-marketplace.json`](https://json.schemastore.org/claude-code-marketplace.json),
`plugin.json` →
[`https://json.schemastore.org/claude-code-plugin-manifest.json`](https://json.schemastore.org/claude-code-plugin-manifest.json)
(published on SchemaStore, sourced from the same plugin system these pages document).
