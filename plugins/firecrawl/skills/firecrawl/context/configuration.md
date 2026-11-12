# firecrawl configuration & defaults

Env vars, global flags, and built-in defaults for the `firecrawl-cli` binary. SKILL.md points here from its Configuration pointer.

**Environment variables**: set these three. This skill needs none of the others the CLI reads; see its [Telemetry section](https://github.com/firecrawl/cli#telemetry) (as of 2026-11-07, CLI 1.29.0; recheck when `/firecrawl:update` reports a CLI release). Extended `FIRECRAWL_RETRY_*` and `FIRECRAWL_CREDIT_*_THRESHOLD` vars found in older setups were **specific to the `firecrawl-mcp` server**; the CLI ignores them and uses built-in retry/backoff. Don't set them.

| Var | Purpose | Default |
|---|---|---|
| `FIRECRAWL_API_KEY` | Cloud API auth | (required) |
| `FIRECRAWL_API_URL` | Override API endpoint (self-hosted) | Firecrawl's cloud API; see [Self-hosted / Local Development](https://github.com/firecrawl/cli#self-hosted--local-development) |
| `FIRECRAWL_NO_TELEMETRY` | Disable usage analytics | telemetry on |

**Global flags** apply to every subcommand:

| Flag | Purpose |
|---|---|
| `-k`, `--api-key <key>` | One-shot override of stored/env key |
| `--api-url <url>` | One-shot override of API endpoint |
| `-o`, `--output <path>` | Write result to file (mandatory for non-trivial output, see Core pattern) |
| `--json` | Force JSON output even for single-format calls |
| `--pretty` | Pretty-print JSON |
| `--status` | Print version + auth + concurrency + credits in one call |
| `-V`, `--version` | CLI version only |
| `-h`, `--help` | Subcommand help |

**Built-in defaults** (knobs NOT exposed as env vars). Their current values are in the README's [Check Status](https://github.com/firecrawl/cli#check-status) example and per-command option tables such as [Search Options](https://github.com/firecrawl/cli#search-options):

- **Concurrency**: the CLI throttles itself; `firecrawl --status` shows the real limit for the account
- **Retry / backoff**: built in. If you need deterministic control, fail-fast with `--timeout` and handle retry in the agent turn
- **Local cache**: CLI creates `.firecrawl/` in the working directory for cached responses. Add `.firecrawl/` to your repository's `.gitignore`. Never commit it

**Prefer env-var auth over `firecrawl config` / `firecrawl login`.** Both persist settings to a user-level config directory that becomes a second source of truth alongside the env var. Authenticate by setting `FIRECRAWL_API_KEY` as an OS user environment variable; override per-call with `--api-key` / `--api-url` if needed.
