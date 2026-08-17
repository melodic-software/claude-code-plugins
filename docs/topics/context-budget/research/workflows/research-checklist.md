# Coverage ledger — Claude Code Workflow tool / workflows feature

**Corpus verdict: BOUNDED.** The question set is six named sub-questions about one vendor feature.
The set of first-party surfaces that could carry the answers is finite and was enumerated *before any
query* from an exhaustive surface: `https://code.claude.com/docs/sitemap.xml` (fetched 2026-08-17,
262 KB, 187 `/docs/en/` pages), filtered to the pages whose slug bears on workflows, settings,
env vars, slash commands, plugin structure, tool loading, managed policy, plan gating, and `/context`.
Plus the upstream release stream (recency gate) and the locally installed CLI (Tier 0).

**Narrowing recorded:** the 187-page English corpus was cut to the 14 rows below plus the release
stream and the local binary. Cut and why: the 33 non-English locale trees (translations of the same
pages, no independent evidence); `agent-sdk/*` pages other than `tool-search` (the SDK is a separate
product surface from the CLI session prefix this research is about); IDE/deployment/gateway/admin
pages with no bearing on any of the six questions. A page cut here that later proved to carry an
answer would show up as an unresolved rung in the fetch log, not as a silent gap.

| # | Corpus item | Depth criterion | Done |
|---|-------------|-----------------|------|
| 1 | `docs/en/workflows` | read end to end; feature definition, every component it adds to a session, and any disable/gating statement extracted verbatim | [x] |
| 2 | `docs/en/settings` | the settings-key table read end to end; `disableWorkflows` located verbatim or its absence confirmed against the full table; the settings-precedence section read | [x] |
| 3 | `docs/en/env-vars` | the env-var table read end to end; `CLAUDE_CODE_DISABLE_WORKFLOWS` located verbatim or its absence confirmed against the full table | [x] |
| 4 | `docs/en/commands` | built-in slash-command table read; `/workflows` located or absence confirmed | [x] |
| 5 | `docs/en/plugins-reference` | plugin directory-structure section read; a `workflows/` component directory located or absence confirmed | [x] |
| 6 | `docs/en/plugins` | plugin-components section read for a workflows component type | [x] |
| 7 | `docs/en/context-window` | `/context` output description read end to end; the row set it reports enumerated; whether any row names workflows or tool schemas | [x] |
| 8 | `docs/en/tools-reference` | the tool table read end to end; whether a Workflow tool appears; any statement on which tool schemas are always in the prefix | [x] |
| 9 | `docs/en/agent-sdk/tool-search` | read for the deferred-vs-prefix loading mechanics and which tools are eligible for deferral | [x] |
| 10 | `docs/en/server-managed-settings` | read for whether workflows settings are enforceable server-side / by managed policy, and the enforcement precedence | [x] |
| 11 | `docs/en/feature-availability` | the plan/product availability matrix read; whether workflows carries a plan gate | [x] |
| 12 | Upstream release stream — `anthropics/claude-code` releases + `CHANGELOG.md` | latest release confirmed THIS turn; every `workflow`-matching entry in the changelog extracted; each disable spelling cross-checked against it | [x] |
| 13 | Local Claude Code CLI (Tier 0) | `claude --help` / installed package searched for `workflow` spellings; result recorded whether hit or miss | [x] |
| 14 | `docs/en/security-guidance` + `docs/en/glossary` (disable-mechanism sweep) | searched for any further workflows disable spelling not found in rows 1-3, to make the "every supported mechanism" claim an enumeration rather than a no-hit | [x] |
