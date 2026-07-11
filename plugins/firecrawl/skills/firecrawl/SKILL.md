---
name: firecrawl
description: "Scrape, search, crawl, map, parse, or interact with web pages via the firecrawl-cli binary, writing results to disk instead of streaming them into context — actions: scrape, search, crawl, map, parse, interact, agent, monitor, update. Use when: WebFetch returns 403/429 (Cloudflare, PerimeterX, anti-bot block), a page requires JS rendering or clicks/form fills, you need web search with scraped results, bulk URL discovery and crawling, a local file (PDF/DOCX/XLSX) needs text extraction to markdown, or a natural-language web research task — skip for plain unprotected pages (WebFetch suffices) or when you want synthesis rather than primary source."
argument-hint: "<command> [args] — commands: scrape, search, crawl, map, parse, interact, agent, monitor, search-feedback, credit-usage, update [--check]"
user-invocable: true
disable-model-invocation: false
allowed-tools: Bash(command -v firecrawl*) Bash(firecrawl --status*) Bash(grep -m1 *UPSTREAM.md*)
---

## Pre-computed context

Status: !`command -v firecrawl >/dev/null 2>&1 && firecrawl --status 2>/dev/null | head -10 || echo "NOT INSTALLED — run: npm install -g firecrawl-cli"`
Last upstream sync: !`grep -m1 '^- Last sync:' "${CLAUDE_SKILL_DIR}/UPSTREAM.md" 2>/dev/null | sed 's/^- //' || echo "never — run the update action with --check"`

The `firecrawl --status` line above includes auth state. If it shows unauthenticated (or the CLI is missing), the fix is: obtain a key from the <https://firecrawl.dev> dashboard and set `FIRECRAWL_API_KEY` as an OS user environment variable.

## Purpose

`firecrawl-cli` is the CLI alternative to the `firecrawl-mcp` MCP server. It wraps api.firecrawl.dev with agent defaults: retry/rotation on anti-bot blocks, JS rendering, and an `-o <path>` flag that writes results to disk instead of streaming into the conversation.

When WebFetch fails on a large page and an MCP equivalent would dump 30K tokens of raw markdown into context, this skill writes to a tempfile and lets the agent `Read` only the slice it needs. Scalekit benchmark measured 32–35× token savings vs the MCP on comparable tasks.

## When to reach for this skill

| Situation | Command | Why |
|---|---|---|
| WebFetch returned 403/429 (Cloudflare, PerimeterX, rate limit) | `firecrawl scrape` | Managed IP rotation + headless browser |
| Page is a SPA or requires JS rendering | `firecrawl scrape` | WebFetch is a plain HTTP client — no JS |
| Page needs clicks, form fills, or login | `firecrawl interact` | Full browser actions, not just fetch |
| Need web search, not a known URL | `firecrawl search` | Search-and-scrape in one call |
| Discovering all URLs on a site | `firecrawl map` | Cheap URL-only discovery |
| Bulk extraction across a site | `firecrawl crawl` | Follows links, respects depth |
| Local PDF / DOCX / XLSX / HTML file on disk → markdown | `firecrawl parse` | Server-side text extraction; no local Office tooling required |
| Natural-language "find me X on the web" | `firecrawl agent` | Hosted agent with Spark models |

## When NOT to use this skill

- **WebFetch works.** WebFetch burns no Firecrawl credits and is faster for simple, unprotected pages.
- **A doc-site-specialist tool is a better fit for official docs.** If the session has a documentation MCP with a headless-browser backend and caching (e.g. Ref), try it before Firecrawl on known docs hosts.
- **You want a training-data summary, not primary source.** A synthesis tool (e.g. a Perplexity MCP, if available) is designed for that.

Escalation order when WebFetch fails:

1. A cached doc-site reader MCP, if the session has one
2. **`firecrawl scrape`** (this skill) — managed scrape with rotation
3. **`firecrawl interact`** (this skill) — when the page needs clicks or login
4. A synthesis tool with a domain filter, if available — forces a domain-specific read through another backend

## Core pattern — write to disk, Read selectively

Every firecrawl invocation writes to `/tmp/fc-<nonce>.<ext>` and uses the `Read` tool to pull only the needed portion into context:

```bash
# Scrape a blocked doc page to markdown
NONCE=$(date +%s%N)
firecrawl scrape "https://www.gnu.org/software/bash/manual/bash.html" \
  --format markdown \
  -o "/tmp/fc-${NONCE}.md"
# Then (in the agent turn): Read /tmp/fc-${NONCE}.md with offset/limit as needed
```

```bash
# Search for recent posts on a topic, saving URL list + excerpts to JSON
NONCE=$(date +%s%N)
firecrawl search "HybridCache .NET 10" \
  --limit 5 \
  --json \
  -o "/tmp/fc-search-${NONCE}.json"
# Then: Read /tmp/fc-search-${NONCE}.json
```

```bash
# Interact with a page that needs a login-then-scrape flow (session model:
# scrape first, then interact against the cached scrape-id).
NONCE=$(date +%s%N)
firecrawl scrape "https://example.com/login" \
  --format markdown \
  -o "/tmp/fc-login-${NONCE}.md"
firecrawl interact \
  "fill the username field with 'agent' and click Sign In, then summarize the dashboard" \
  -o "/tmp/fc-interact-${NONCE}.md"
```

Direct stdout is acceptable only for tiny, single-paragraph results (e.g., "get the page title") where file I/O overhead exceeds the token savings. Default: `-o <path> && Read`.

## Commands

Ten subcommands. One-line purpose below; **full flag detail + examples in `context/commands.md`** — read it when constructing any non-trivial call. `firecrawl <cmd> --help` is the live fallback.

| Command | Purpose |
|---|---|
| `scrape <url>` | Single URL → markdown/html/json/screenshot |
| `search "<q>"` | Query → ranked URLs (+ optional `--scrape`) |
| `crawl <url>` | Follow links from a seed (bulk, expensive; `map` first) |
| `map <url>` | Fast URL-only discovery, no content |
| `parse <file>` | Local PDF/DOCX/XLSX/HTML → markdown, server-side |
| `interact "<p>"` | Prompt/code against a cached scrape session |
| `agent "<p>"` | Hosted NL web-research task (Spark models) |
| `monitor` | Server-side scheduled scrapes + change alerts (use sparingly — a local scheduler such as the built-in `/schedule` may fit better) |
| `search-feedback <id>` | Refund a credit on a bad `search` result |
| `credit-usage` | Remaining quota (pre-computed in the context block above) |

## Configuration & defaults

The CLI reads exactly three env vars (`FIRECRAWL_API_KEY` / `FIRECRAWL_API_URL` / `FIRECRAWL_NO_TELEMETRY`), a set of global flags (`-o`, `--json`, `--status`, …), and built-in non-env defaults (5-job concurrency, 60s search timeout, automatic retry/backoff, `.firecrawl/` local cache). Full tables in `context/configuration.md`. **Prefer env-var auth over `firecrawl config` / `firecrawl login`** — those persist to a user-level config dir that becomes a second source of truth alongside the env var.

## Prerequisites

The CLI is an escalation option, not a hard dependency — install it when first needed:

```bash
npm install -g firecrawl-cli
```

Authenticate via the `FIRECRAWL_API_KEY` environment variable (OS user scope); the CLI reads it automatically. Avoid `firecrawl login` — it writes a separate user-level config that diverges from the env-var flow.

**Do NOT run `firecrawl init --all --browser`.** That command installs the `firecrawl-mcp` MCP server plus a bundled copy of the upstream skill into `~/.claude/skills/` — a parallel install that shadows nothing but duplicates this plugin's capability and drifts from it. This plugin IS the maintained integration; updates arrive through `/plugin marketplace update`.

## Updating the skill and CLI

The CLI ships new versions roughly weekly; the upstream canonical skill at `https://www.firecrawl.dev/agent-onboarding/SKILL.md` evolves alongside it. This skill **owns** its content — upstream is a *source*, not a parallel install.

`/firecrawl:firecrawl update` is maintainer-facing: run it in a working-tree checkout of this plugin (the marketplace clone, or a directory loaded via `--plugin-dir`), never against an installed marketplace copy — the apply path rewrites `UPSTREAM.md` inside the skill directory, and consumers receive updates through `/plugin marketplace update`. Drift detection uses the sidecar `UPSTREAM.md` (SHA tracking): upstream `SKILL.md` is fetched fresh on `--check` and hashed; the sidecar records the prior hash for diff. No vendored snapshot is kept. The action is advisory — the two approval gates below keep every mutation behind an explicit yes.

**When to invoke, the modes, and the full update pipeline:** read `context/update-flow.md`. The preservation invariants and safety guarantees below stay inline.

### Preservation rules (for any skill-content integration)

These are the invariants an integration run must keep, in this exact form:

- Single-line YAML `description` with `Use when:` and skip guidance phrase lists
- Frontmatter fields: `name`, `description`, `argument-hint`, `user-invocable: true`, `disable-model-invocation: false`
- Pre-computed context block at top, using `firecrawl --status` for the health line
- "Core pattern — write to disk, Read selectively" rule: every non-trivial example uses `-o /tmp/fc-<nonce>.<ext>` then `Read`
- "When NOT to use this skill" section with the doc-site-reader-first and synthesis-tool escalation ordering
- "Updating the skill and CLI" section (this one) and its Safety subsection
- Gotchas section with the "don't run `firecrawl init`, don't run `firecrawl login`" prohibitions
- Imperative tone, no marketing language

The helper at `scripts/update.sh` does the deterministic parts (fetch, SHA, diff); the skill body does the Claude-facing decisions (integration and approval). For a non-trivial content delta, the `/skill-creator:skill-creator` plugin skill (if installed) can drive the rewrite under the preservation rules above; otherwise inline-edit.

## Safety

Nothing destructive happens without explicit approval. Four guarantees:

1. **Two approval gates.** The update action never runs `npm install -g` or rewrites SKILL.md without asking first. Gate 1 covers the binary install; Gate 2 covers the skill content. Either `No` exits cleanly.
2. **Atomic fetching.** `update.sh --check` completes all network I/O (npm metadata + upstream fetch) before printing anything. A mid-run 404 or DNS failure leaves state untouched — no partial write.
3. **Rollback path.** `UPSTREAM.md` records the *previous* CLI version before each upgrade. If a new version breaks something, the rollback is one line: `npm install -g firecrawl-cli@<previous-version>`. Revert the plugin PR for skill-content changes.
4. **Post-install verification.** After `npm install -g`, the flow re-runs `firecrawl --status` and diffs `firecrawl --help` against the pre-install snapshot. A removed command or auth failure is flagged before the skill-content integration step begins.

**Network requirement.** The update path needs `registry.npmjs.org` and `www.firecrawl.dev` reachable. Some sandboxed/cloud egress proxies intermittently 503 with "DNS cache overflow" — retry after ~30s, or run the update from an unrestricted session.

**Idempotency.** Running the update action with `--check` twice with no upstream change: "no drift, current." Running a full update when already at latest: reports "no drift" and exits before Gate 1. Safe to schedule or re-run.

## Gotchas

- **`-o` is mandatory for anything larger than a paragraph.** Streaming to stdout wastes the whole token-efficiency advantage. If a command lacks `-o` in this skill's examples, it's because the output is truly small (e.g., `credit-usage`). Everything else — scrape, search, crawl, interact, agent — writes to disk.
- **Credits are a shared resource.** Every call charges the account. Use `map` before `crawl`, use `--limit` aggressively on search, and skip Firecrawl entirely when a plain fetch would do.
- **`firecrawl login` creates a second source of truth.** Auth via the `FIRECRAWL_API_KEY` env var; the login command writes to a user-level config dir — mixing them leaves two sources of truth.
- **Transient DNS 503 on `api.firecrawl.dev` from sandboxed sessions.** Some cloud egress proxies intermittently return "DNS cache overflow" — retry after ~30s. This affects both the CLI and direct curl; it's an egress issue, not a Firecrawl outage.
- **Windows/Git Bash tmp paths.** `/tmp/fc-<nonce>.md` resolves to a Windows path via Git Bash's mount. Both path forms work for Read; no normalization needed on the agent side.
- **Self-hosted Firecrawl.** Set `FIRECRAWL_API_URL` as an OS user environment variable to switch the CLI to a local instance. Default is `https://api.firecrawl.dev` — only override when running against a self-hosted stack.
- **CLI and `mcp__firecrawl__*` MCP tools overlap** — running both wastes context and splits configuration. If the consuming project also has the Firecrawl MCP registered, pick one surface.

## Related

- `UPSTREAM.md` (skill root) — sync-state anchor (last sync date, upstream SHA, previous CLI version for rollback). Updated only by the update action.
- `scripts/update.sh` — deterministic helper invoked by the update flow (npm version lookup, upstream fetch + SHA, help diff).
- Firecrawl docs: <https://docs.firecrawl.dev/sdks/cli>. Upstream skill source: <https://www.firecrawl.dev/agent-onboarding/SKILL.md>. MCP-vs-CLI guidance: <https://www.firecrawl.dev/blog/mcp-vs-cli>.
