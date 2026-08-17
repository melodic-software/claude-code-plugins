# Coverage ledger — /context output contract in Claude Code v2.1.232

**Corpus verdict: BOUNDED.** The corpus is enumerable before the first query from two
exhaustive-by-construction surfaces:

1. **The dispatch prompt itself** — the naming source for the seven numbered questions the
   parent asked (per the discipline file's corpus-enumeration table: "A named finite set →
   the naming source itself — the prompt").
2. **The installed artifact** — `@anthropic-ai/claude-code` v2.1.232's own bundle on this
   machine, which is exhaustive by construction for "what does the shipped code do", and the
   official docs site's `sitemap.xml`, which is exhaustive for that host's pages.

Rows 1-7 are the parent's questions. Rows 8-12 are the primary surfaces that must each be
walked for the answers to be gradeable (artifact-ladder rungs + the recency gate). Nothing was
cut; the corpus is covered in full.

| # | Corpus item | Depth criterion | Done |
|---|-------------|-----------------|------|
| 1 | Q1 — is /context's output format documented officially; which version introduced per-skill/per-agent tables; is the format declared stable | docs sitemap enumerated and every /context-bearing page fetched; official CHANGELOG.md fetched this turn and grepped for every `context` entry; a stability statement either quoted or its absence reported with the surfaces checked named | [x] |
| 2 | Q2 — what "System tools" contains and why no per-tool breakdown; any flag/env/verbose mode for per-tool attribution | the category's construction read out of the shipped v2.1.232 bundle (Tier 0), AND the full CLI flag surface (`claude --help`) plus the docs' settings/env-var reference enumerated for any per-tool switch | [x] |
| 3 | Q3 — meaning of "System tools (deferred)" and its relation to ToolSearch / MCP deferral | the deferral mechanism located in the shipped bundle and its gating setting named, corroborated against the official docs page that documents it | [x] |
| 4 | Q4 — whether configured MCP servers add an MCP row or per-server attribution to /context | the row's construction read out of the shipped bundle showing the exact condition under which an MCP row renders, plus ≥1 independent public report of the row being observed | [x] |
| 5 | Q5 — whether CLAUDE.md memory files are their own /context row at 2.1.232, or were replaced by the category table | the shipped bundle's category list read end to end and compared against the historical "Memory files" section; the version at which the change landed named from the changelog | [x] |
| 6 | Q6 — exact meaning of Source values Built-in / claude.ai sync / Plugin (x) / User, and how to disable claude.ai sync | each of the four Source strings located in the shipped bundle with the condition that emits it, AND the disable path for claude.ai sync confirmed against official docs/settings reference | [x] |
| 7 | Q7 — any JSON/structured output for /context specifically, or for `claude -p` generally | `claude --help` output format flags enumerated (Tier 0); the CLI-reference and headless/SDK docs pages fetched; the slash-command-in-`-p` path tested empirically for what the JSON envelope actually contains | [x] |
| 8 | Official docs surface: `code.claude.com/docs` sitemap.xml | sitemap fetched and enumerated; every page whose URL or content bears on /context, context editing, tool search, MCP, or memory identified and the relevant ones fetched | [x] |
| 9 | Official CHANGELOG.md (upstream `anthropics/claude-code`) — the recency gate | raw CHANGELOG.md fetched this turn, latest release confirmed, and every entry mentioning context/skills/agents/tool-search read to date the features in rows 1-7 | [x] |
| 10 | The shipped v2.1.232 bundle (`/opt/node22/lib/node_modules/@anthropic-ai/claude-code/cli.js`) | the /context renderer located and read: category list, row ordering, conditional rows, Source-value strings, and any structured-output path | [x] |
| 11 | Empirical probe of the installed binary (Tier 0) | `/context` re-run under this session's conditions and against a modified config, plus `claude --help` and `-p --output-format` enumerated, to test claims the source read predicts | [x] |
| 12 | Community/issue corroboration (upstream issue tracker + practitioner reports) | upstream issue tracker searched for /context output-format reports, and ≥1 named-author independent report located, for the claims where a second pool is needed (esp. Q4 MCP row, Q1 stability) | [x] |
