# firecrawl configuration & defaults

Env vars, global flags, and built-in defaults for the `firecrawl-cli` binary. SKILL.md points here from its Configuration pointer.

**Environment variables** — the CLI reads exactly three. Extended `FIRECRAWL_RETRY_*` and `FIRECRAWL_CREDIT_*_THRESHOLD` vars found in older setups were **specific to the `firecrawl-mcp` server**; the CLI ignores them and uses built-in retry/backoff. Don't set them.

| Var | Purpose | Default |
|---|---|---|
| `FIRECRAWL_API_KEY` | Cloud API auth | (required) |
| `FIRECRAWL_API_URL` | Override API endpoint (self-hosted) | `https://api.firecrawl.dev` |
| `FIRECRAWL_NO_TELEMETRY` | Disable usage analytics | telemetry on |

**Global flags** — apply to every subcommand:

| Flag | Purpose |
|---|---|
| `-k`, `--api-key <key>` | One-shot override of stored/env key |
| `--api-url <url>` | One-shot override of API endpoint |
| `-o`, `--output <path>` | Write result to file (mandatory for non-trivial output — see Core pattern) |
| `--json` | Force JSON output even for single-format calls |
| `--pretty` | Pretty-print JSON |
| `--status` | Print version + auth + concurrency + credits in one call |
| `-V`, `--version` | CLI version only |
| `-h`, `--help` | Subcommand help |

**Built-in defaults** (knobs NOT exposed as env vars):

- **Concurrency**: 5 parallel scrape jobs (shown as `0/5` in `firecrawl --status`) — CLI throttles itself. Higher ceilings are plan-dependent; `--status` shows the real number
- **Search timeout**: 60000 ms
- **Crawl / agent poll interval**: 5 s
- **Retry / backoff**: automatic; not configurable. If you need deterministic control, fail-fast with `--timeout` and handle retry in the agent turn
- **Local cache**: CLI creates `.firecrawl/` in the working directory for cached responses. Add `.firecrawl/` to your repository's `.gitignore` — never commit it

**Prefer env-var auth over `firecrawl config` / `firecrawl login`** — both persist settings to a user-level config directory that becomes a second source of truth alongside the env var. Authenticate by setting `FIRECRAWL_API_KEY` as an OS user environment variable; override per-call with `--api-key` / `--api-url` if needed.
