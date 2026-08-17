# Coverage ledger — claude.ai connectors in Claude Code

**Corpus verdict: BOUNDED.** The question set is six named sub-questions against a finite,
enumerable documentation surface plus one local Tier-0 artifact.

**Enumeration surfaces (exhaustive by construction):**

- `https://code.claude.com/sitemap.xml` — fetched 2026-08-17, 187 distinct `/docs/en/` pages.
  Rows 1-24 are every page in that enumeration whose subject plausibly carries a connector, MCP,
  settings-key, context-accounting, or prompt-cache claim. Pages excluded are excluded on subject
  (IDE integrations, cloud-provider setup, billing/analytics, localized duplicates), not on budget.
- The installed Claude Code bundle on this machine, `@anthropic-ai/claude-code` — the shipped
  `cli.js`, which is the implementation and outranks every doc about it ("source code as spec").
- `docs.claude.com` and `support.claude.com` — the claude.ai-side publisher surfaces for the
  connector concept itself, which `code.claude.com` does not own.

**Explicit narrowing:** localized (`/docs/de/`, `/docs/ja/`, …) mirrors of the same pages are out of
corpus — they are translations of the enumerated English pages, not independent sources.

| # | Corpus item | Depth criterion | Done |
|---|-------------|-----------------|------|
| 1 | `code.claude.com/docs/en/mcp` | full page read; every scope, config key and slash command it names extracted verbatim | [x] |
| 2 | `code.claude.com/docs/en/managed-mcp` | full page read; admin/managed-side connector controls and key spellings extracted | [x] |
| 3 | `code.claude.com/docs/en/settings` | settings-key table read end to end; every MCP/connector-related key name captured verbatim with its scope | [x] |
| 4 | `code.claude.com/docs/en/context-window` | read end to end for what `/context` reports and its category names | [x] |
| 5 | `code.claude.com/docs/en/costs` | read for context/token accounting statements bearing on connector cost | [x] |
| 6 | `code.claude.com/docs/en/tools-reference` | read for ToolSearch / deferred-tool loading semantics and which tools defer | [x] |
| 7 | `code.claude.com/docs/en/agent-sdk/tool-search` | read end to end for the deferred-loading mechanism and what governs it | [x] |
| 8 | `code.claude.com/docs/en/env-vars` | env-var table read end to end; every MCP/connector/tool-search var captured verbatim | [x] |
| 9 | `code.claude.com/docs/en/interactive-mode` | read for slash-command surface bearing on connectors/MCP | [x] |
| 10 | `code.claude.com/docs/en/commands` | slash-command reference read; presence/absence of `/connectors` and `/mcp` established | [x] |
| 11 | `code.claude.com/docs/en/cli-reference` | CLI flags read end to end for MCP/connector scoping flags | [x] |
| 12 | `code.claude.com/docs/en/third-party-integrations` | read for how connectors are surfaced vs MCP servers | [x] |
| 13 | `code.claude.com/docs/en/server-managed-settings` | read for managed/enterprise precedence over connector settings | [x] |
| 14 | `code.claude.com/docs/en/prompt-caching` | read end to end for any statement tying tool/connector definitions to cache invalidation | [x] |
| 15 | `code.claude.com/docs/en/how-claude-code-works` | read for the system-prompt/context assembly description | [x] |
| 16 | `code.claude.com/docs/en/glossary` | searched for a definition of "connector" and of "MCP server" | [x] |
| 17 | `code.claude.com/docs/en/plugins-reference` | read for plugin-supplied `mcpServers` and how they differ from connectors | [x] |
| 18 | `code.claude.com/docs/en/security` | read for connector/MCP trust and disable guidance | [x] |
| 19 | `code.claude.com/docs/en/claude-code-on-the-web` | read for connector availability on the web surface | [x] |
| 20 | `code.claude.com/docs/en/desktop` | read for connector availability/controls on the desktop surface | [x] |
| 21 | `code.claude.com/docs/en/mcp-quickstart` | read for the user-facing add/enable/disable flow | [x] |
| 22 | `code.claude.com/docs/en/changelog` | latest entries read; recency gate for every version-bearing claim | [x] |
| 23 | `code.claude.com/docs/en/whats-new` + latest weekly | latest weekly release note read for connector/context changes | [x] |
| 24 | `code.claude.com/docs/en/feature-availability` | read for which surfaces expose connectors | [x] |
| 25 | Installed `@anthropic-ai/claude-code` `cli.js` (Tier 0) | grepped for `connector`, `/connectors`, `enabledMcpjsonServers`, `disabledMcpjsonServers`, `enableAllProjectMcpServers`, and the `/context` category labels; matched strings quoted | [x] |
| 26 | `claude --help` / installed version (Tier 0) | version captured this turn and cross-checked against the published changelog | [x] |
| 27 | claude.ai-side publisher surface for "connector" (`docs.claude.com` / `support.claude.com`) | probed for a first-party definition of the connector concept; result recorded as carries / lacks / unresolved | [x] |
| 28 | Anthropic engineering/eng blog or official post on context accounting | probed for an official statement on tool-definition context cost; result recorded | [x] |

</content>

**Row-27 note (recorded outcome, not a silent pass):** the claude.ai-side publisher surface was
probed and is **unreachable from this session**, not absent. `support.claude.com`, `claude.com`,
and `www.anthropic.com` are all blocked by this environment's network egress proxy; the
`docs.claude.com/en/docs/connectors` guess returned 404. The row's criterion was "result recorded",
and the recorded result is *unreachable after escalation*. The connector definition used in the
findings therefore comes from `code.claude.com`'s own glossary and desktop pages, not from the
claude.ai-side surface. See `RESEARCH-gaps-and-unverified.md`.

**Row-28 note:** `www.anthropic.com/engineering/advanced-tool-use` was located via search but is
egress-blocked. The equivalent primary was fetched instead from
`platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool.md` (HTTP 200, 34,970 bytes).
