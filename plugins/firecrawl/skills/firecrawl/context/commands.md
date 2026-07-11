# firecrawl commands — full reference

Per-command flag detail for the `/firecrawl` skill. SKILL.md carries the command summary table + Core pattern; this file is the complete construction reference. Run `firecrawl <cmd> --help` for the full flag set when a use case requires something advanced.

## Contents

- [scrape](#scrape--single-url--content)
- [search](#search--query--ranked-urls--optional-scrape)
- [crawl](#crawl--follow-links-from-a-seed-url)
- [map](#map--fast-url-discovery-no-content)
- [parse](#parse--local-file--markdownjson)
- [interact](#interact--run-promptscode-against-a-prior-scrape)
- [agent](#agent--natural-language-web-research-task)
- [monitor](#monitor--scheduled-scrapes--change-tracking)
- [search-feedback](#search-feedback--refund-credits-on-bad-search-results)
- [credit-usage](#credit-usage--check-remaining-quota)

## scrape — single URL → content

```bash
firecrawl scrape <url> --format <markdown|html|rawHtml|screenshot|json|summary> -o <path>
```

Default `--format markdown`. Use `--format json` for structured output (title, metadata, links, content in one file). Use `--format screenshot` for PNG to `-o path.png`. Combine multiple formats with comma-separated values — output becomes JSON containing each format.

## search — query → ranked URLs (+ optional scrape)

```bash
# URLs + metadata only (cheap):
firecrawl search "<query>" --limit <N> --json -o <path>

# URLs + scraped content in one call (costs more credits):
firecrawl search "<query>" --limit <N> --scrape --scrape-formats markdown --json -o <path>
```

`--limit 5` suffices for research (default 5, max 100). `--scrape` is a **boolean** enabling result scraping; `--scrape-formats` controls which scrape formats are included (markdown/html/links/etc., comma-separated). No `--format` or `--pretty` flag — use `--json` for structured output, pipe through `jq` for pretty-printing.

## crawl — follow links from a seed URL

```bash
# Kick off a crawl and get a job-id (non-blocking):
firecrawl crawl <url> --limit <N> --max-depth <D> -o <path>

# Block until complete:
firecrawl crawl <url> --limit <N> --max-depth <D> --wait -o <path>

# Poll an existing job:
firecrawl crawl <job-id> --status
```

`-o <path>` writes a **single JSON file** with all page results inside — not a directory of per-page files. Bulk and expensive; set `--limit` to cap total pages and `--max-depth` to stop runaway crawls. Prefer `map` first to estimate scope. Use `--wait` for simple scripts; for long crawls capture the job-id and poll with `--status`.

## map — fast URL discovery, no content

```bash
firecrawl map <url> -o <path>
```

Cheap. Returns a list of URLs the site exposes. Use before `crawl` to estimate scope and choose `--limit`.

## parse — local file → markdown/json

```bash
firecrawl parse <file> --format <markdown|html|rawHtml|links|images|summary|json|attributes> -o <path>
```

Supported file types: `.html`, `.htm`, `.pdf`, `.docx`, `.doc`, `.odt`, `.rtf`, `.xlsx`, `.xls`. Max upload: 50 MB. Uses `/v2/parse` server-side. Multiple formats with commas produce a JSON wrapper; single format produces raw content. `--only-main-content` strips boilerplate. `-Q "<question>"` runs a Q&A pass over the parsed content in one call. Use this instead of WebFetch when the artifact is a binary doc already on disk (downloaded PDF, exported DOCX) — no separate text-extraction step needed.

## interact — run prompts/code against a prior scrape

`firecrawl interact` operates on a **scrape session**, not on a URL directly. The CLI caches the last scrape's ID, so the usual flow is scrape-then-interact:

```bash
# 1. Scrape the page (session ID cached by the CLI):
firecrawl scrape <url> --format markdown -o /tmp/fc-<nonce>.md

# 2. Run a prompt against the last scrape:
firecrawl interact "<natural-language prompt>" -o /tmp/fc-interact-<nonce>.md

# Or pass an explicit scrape-id (also works as positional):
firecrawl interact -s <scrape-id> "<prompt>" -o <path>

# Code execution in the browser sandbox (Node/Playwright default; --python / --bash alternatives):
firecrawl interact -c "await page.title()" -o <path>

# Stop the interactive browser session when done:
firecrawl interact stop
```

Replaces the deprecated MCP `browser_create/execute/close` family. Flags: `-p/--prompt` is the long form of the positional prompt; `-c/--code` switches to code execution; `-s/--scrape-id` overrides the cached last-scrape. There is no `<url>` positional and no `--instructions`/`--format` flags.

## agent — natural-language web research task

```bash
firecrawl agent "<prompt>" --model <spark-1-mini|spark-1-pro> -o <path>
```

Hosted agent (different from the Anthropic model running this conversation). Use for "find me the latest X and summarize" tasks where Firecrawl plans the browse path. `spark-1-mini` is the default, sufficient for most research.

## monitor — scheduled scrapes + change tracking

```bash
# Create a monitor (flags form):
firecrawl monitor create --name "<label>" --schedule "<natural-language>" \
  --scrape-urls <url1>,<url2> --email <addr>

# Or from a JSON spec:
firecrawl monitor create monitor.json

# List / inspect / control:
firecrawl monitor list --limit <N>
firecrawl monitor get <monitorId>
firecrawl monitor update <monitorId> --state paused
firecrawl monitor run <monitorId>                  # trigger immediately
firecrawl monitor checks <monitorId> --limit <N>
firecrawl monitor check <monitorId> <checkId> --page-status changed
firecrawl monitor delete <monitorId>
```

Out-of-band scheduled scraping with email alerts on content changes. Lives server-side at Firecrawl, not in this repo. Use sparingly — this repo's recurring-work pattern is `/schedule` (CC routines); Firecrawl monitors carry their own credit cost and a notification side channel that bypasses CC observability. Reach for it only when the alert recipient should be a human inbox rather than a CC routine.

## search-feedback — refund credits on bad search results

```bash
firecrawl search-feedback <searchId> --rating <good|bad|partial> [...]
```

`<searchId>` is returned by `firecrawl search ... --json` in the response payload. **Refunds 1 credit on first submission** when the search was unsatisfactory. Optional `--valuable-sources`, `--missing-content`, `--query-suggestions` train future ranking. Worth doing whenever a `search` call returned junk — recovers credit AND improves the API.

## credit-usage — check remaining quota

```bash
firecrawl credit-usage
```

Pre-computed in the skill's context block via `firecrawl --status`. Watch the running number — when credits dip low, prefer WebFetch or Ref over Firecrawl unless the work requires anti-bot handling or JS rendering. The CLI has no `FIRECRAWL_CREDIT_*_THRESHOLD` env vars (those were MCP-era knobs — see `configuration.md`).
