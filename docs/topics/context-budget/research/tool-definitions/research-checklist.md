# Coverage ledger — pruning tool definitions from a Claude Code session's request payload

**Corpus verdict: BOUNDED.** The topic asks six questions whose answers, if they exist in first-party
form, live in a finite and enumerable set of pages across two publisher hosts plus the upstream
release stream. Enumerated Phase 0, before any query, from surfaces exhaustive by construction:

- `https://code.claude.com/sitemap.xml` (fetched 2026-08-17) — 187 `/docs/en/` pages
- `https://docs.claude.com/sitemap.xml` (fetched 2026-08-17, redirects to `platform.claude.com`) —
  2834 URLs, 1 language slice each
- `gh api repos/anthropics/claude-code/releases` — the upstream release stream (recency gate)

**Narrowing, recorded explicitly.** The 187+2834 page inventory is cut to the 24 rows below: the
pages whose titles or paths make them plausible owners of one of the six questions, plus the recency
and falsification surfaces. Cut and not covered: the 100+ `code.claude.com` pages on IDE
integrations, gateways, self-hosted environments, desktop/mobile clients, compliance, and the
non-English locale slices; the ~2700 `platform.claude.com` URLs outside tool-use, token-counting and
context management. A reader wanting those has the two sitemap files named above to enumerate from.

| # | Corpus item | Depth criterion | Done |
|---|-------------|-----------------|------|
| 1 | `code.claude.com/docs/en/tools-reference` | The full built-in tool table read end to end; every tool name extracted; any statement about which tools are deferred vs prefix-loaded quoted | [x] |
| 2 | `code.claude.com/docs/en/mcp` | Searched end to end for a statement that MCP tools are deferred/tool-search-gated by default; the statement quoted verbatim or its absence recorded | [x] |
| 3 | `code.claude.com/docs/en/agent-sdk/tool-search` | Read end to end — the deferral mechanism, what the model sees for a deferred tool, defaults per tool class, and every configuration key named on the page | [x] |
| 4 | `platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool` | Read end to end — the API-level tool-search contract, `defer_loading`, and what a deferred definition costs in the prefix | [x] |
| 5 | `code.claude.com/docs/en/settings` | The full settings-key table searched for deferral/tool-search/`alwaysLoad` keys and for `disallowedTools`/`permissions`; findings and absences both recorded | [x] |
| 6 | `code.claude.com/docs/en/permissions` | The `allow`/`ask`/`deny` semantics section read end to end; any statement about whether deny removes a tool schema quoted or its absence recorded | [x] |
| 7 | `code.claude.com/docs/en/cli-reference` | The full flag table read; `--disallowedTools`, `--allowedTools`, `-p`, and any tool-search flag located or recorded absent | [x] |
| 8 | `code.claude.com/docs/en/env-vars` | Searched end to end for any env var governing tool deferral, tool search, or tool-definition loading; findings and absences recorded | [x] |
| 9 | `code.claude.com/docs/en/costs` | Searched for `/context`, per-tool token attribution, and any token-measurement guidance | [x] |
| 10 | `code.claude.com/docs/en/monitoring-usage` | Searched for token-accounting granularity and whether tool definitions are separately attributed | [x] |
| 11 | `code.claude.com/docs/en/context-window` | Read end to end — what `/context` reports and at what granularity | [x] |
| 12 | `code.claude.com/docs/en/interactive-mode` + `code.claude.com/docs/en/commands` | Searched for `/context` as a documented slash command and for its output description | [x] |
| 13 | `code.claude.com/docs/en/headless` | Read for whether `claude -p` accepts a slash command as its prompt and what it returns | [x] |
| 14 | `platform.claude.com/docs/en/build-with-claude/token-counting` | Read end to end — the `count_tokens` endpoint, whether `tools` is an accepted field, and any statement on estimating tokens from characters | [x] |
| 15 | `platform.claude.com/docs/en/agents-and-tools/tool-use/manage-tool-context` | Read end to end — official guidance on tool-count thresholds, accuracy degradation, and context cost of definitions | [x] |
| 16 | `platform.claude.com/docs/en/agents-and-tools/tool-use/overview` | Searched for the per-tool token overhead statement and the tool-count guidance | [x] |
| 17 | `platform.claude.com/docs/en/agents-and-tools/tool-use/implement-tool-use` | Searched for the tool-definition token-overhead table; NOT present there — the table lives on `tool-use/overview#pricing`, which was fetched and read instead. Narrowed and recorded | [x] |
| 18 | `code.claude.com/docs/en/sub-agents` | Searched for whether an agent `tools:` allowlist / `disallowedTools` changes the schema set the subagent's model sees | [x] |
| 19 | `code.claude.com/docs/en/agent-sdk/typescript` | Searched for SDK-level options controlling tool deferral / tool search | [x] |
| 20 | `code.claude.com/docs/en/plugins-reference` + `plugin-relevance` | Searched for plugin-level control over whether a plugin's tools/skills load into the prefix | [x] |
| 21 | `gh api repos/anthropics/claude-code/releases` | The latest release fetched THIS turn; the CHANGELOG searched for tool-search / deferral / `disallowedTools` entries; verdict recorded per claim | [x] |
| 22 | Anthropic engineering blog on tool search / context management | Located (`anthropic.com/engineering/advanced-tool-use`) but UNREACHABLE after escalation: WebFetch EGRESS_BLOCKED, curl HTTP 403 `host_not_allowed`. Recorded as Gap 3 with surfaces checked; no accepted claim depends on it | [x] |
| 23 | Falsification surface — upstream issue tracker for "disallowedTools still counts tokens" / "deny does not remove schema" | Searched; result recorded whether or not it contradicts the leading hypothesis | [x] |
| 24 | Local Tier-0 evidence — this session's own tool surface (deferred-tool system-reminder, `ToolSearch` description, `claude --help`) | Captured as direct tool output and reconciled against the doc claims | [x] |
