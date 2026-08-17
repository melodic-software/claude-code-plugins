# Coverage ledger — plugins/MCP as a context-budget lever

**Corpus verdict: BOUNDED.** Three enumerable sets, each from a surface exhaustive by construction:

1. **Doc pages** — `https://code.claude.com/docs/sitemap.xml` (fetched 2026-08-17), 187 `/docs/en/`
   pages. `llms.txt` exists at `/docs/llms.txt` but is curated, so the sitemap is the enumeration
   surface and `llms.txt` only prioritizes.
2. **CLI surfaces** — `claude --help` and each relevant subcommand's own `--help` (Tier 0, exhaustive
   for the installed build, v2.1.232).
3. **Release stream** — `gh api repos/anthropics/claude-code/releases` + the docs changelog page.

**Explicit narrowing (recorded, not quiet).** Of the 187 `/docs/en/` pages, this ledger covers the
subset that can carry an answer to the six numbered questions, plus the pages that would falsify one.
Excluded by construction and NOT covered: all `agent-sdk/*` pages (the SDK's programmatic surface is a
different consumer than the CLI operator surface this topic is about — noted as a Gap if a claim turns
out to live only there), all deployment/gateway/enterprise-hosting pages, all IDE/platform pages, and
the `whats-new/2026-w*` archive except the weeks a `/doctor` or plugin-context change lands in.

| # | Corpus item | Depth criterion | Done |
|---|-------------|-----------------|------|
| 1 | docs/en/settings | Every settings-file scope named, its filename, the full precedence list, and every plugin/MCP enablement key spelling read end to end | [x] |
| 2 | docs/en/plugins-reference | The plugin component inventory read end to end; each component's load timing recorded or recorded as unstated | [x] |
| 3 | docs/en/plugins | Enable/disable mechanics + `enabledPlugins` section read end to end | [x] |
| 4 | docs/en/plugin-relevance | Read end to end; whether it describes deferred vs always-loaded plugin content | [x] |
| 5 | docs/en/plugin-hints | Read end to end; what a hint contributes to the payload | [x] |
| 6 | docs/en/plugin-marketplaces | Searched for `enabledPlugins` / enablement-scope statements | [x] |
| 7 | docs/en/plugin-dependencies | Searched for whether dependencies alter enablement or load timing | [x] |
| 8 | docs/en/mcp | Every MCP enable/disable key spelling, its scope, and any statement about tool deferral read end to end | [x] |
| 9 | docs/en/managed-mcp | Read for managed-scope MCP enablement and its precedence | [x] |
| 10 | docs/en/server-managed-settings | Read for where managed/policy settings sit in precedence | [x] |
| 11 | docs/en/prompt-caching | The cache-invalidation material located and QUOTED verbatim; MCP/plugin-specific sentences extracted | [x] |
| 12 | docs/en/context-window | Read end to end for what `/context` reports and the startup-payload breakdown | [x] |
| 13 | docs/en/cli-reference | `--safe-mode`, `-p`, `--setting-sources`, `--strict-mcp-config`, `--plugin-dir` entries read | [x] |
| 14 | docs/en/interactive-mode | The slash-command table read; presence/absence of each of the 8 named commands recorded | [x] |
| 15 | docs/en/skills | The always-loaded name+description claim located and quoted, or recorded absent | [x] |
| 16 | docs/en/hooks | Read for where hook config is loaded from and when | [x] |
| 17 | docs/en/output-styles | Read for what an output style contributes and when it loads | [x] |
| 18 | docs/en/memory | Read for `/memory` and CLAUDE.md load timing | [x] |
| 19 | docs/en/debug-your-config | Read end to end for `/doctor`'s documented scope | [x] |
| 20 | docs/en/troubleshooting | Searched for `/doctor` claims about unused skills/MCP/plugins | [x] |
| 21 | docs/en/env-vars | `CLAUDE_CONFIG_DIR` entry read verbatim | [x] |
| 22 | docs/en/headless | Read for whether slash commands run under `claude -p` | [x] |
| 23 | docs/en/costs + docs/en/monitoring-usage | Searched for a context/token measurement surface | [x] |
| 24 | docs/en/changelog | Searched for the release that made `/doctor` a bundled skill and for plugin/MCP context changes | [x] |
| 25 | `claude --help` (v2.1.232) | `--safe-mode`, `--setting-sources`, `--strict-mcp-config`, `--bare` option text captured verbatim | [x] |
| 26 | `claude plugin *` subcommand help | Every subcommand's `--help` captured; `enable`/`disable`/`details` scope flags verbatim | [x] |
| 27 | `claude mcp *` subcommand help | Every subcommand's `--help` captured; scope flag values verbatim | [x] |
| 28 | `claude plugin details <name>` real output | Run against an installed plugin; the component inventory and token-cost columns captured verbatim | [x] |
| 29 | Headless probe of the 8 native inventory commands | Each of `/context /memory /skills /hooks /mcp /permissions /status /plugin` invoked via `claude -p`; per-command result recorded | [x] |
| 30 | The bundled `/doctor` skill body | Its own text located (binary or session) and its claims about unused skills/MCP/plugins read verbatim, or recorded unreachable with surfaces enumerated | [x] |
| 31 | Upstream release stream | `gh api repos/anthropics/claude-code/releases` fetched this turn; latest version confirmed; `/doctor`-bundled-skill and plugin-context entries searched | [x] |
| 32 | `installed_plugins.json` / settings on disk | The real on-disk shape of the enablement record read (Tier 0) | [x] |
