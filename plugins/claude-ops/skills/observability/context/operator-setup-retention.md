# Operator setup — retention

Parent: [`operator-setup.md`](operator-setup.md). Privacy tie-in: [`operator-setup-emission-privacy.md`](operator-setup-emission-privacy.md).

## Pruning the store (retention) — two tiers

The store grows unbounded otherwise, and with full capture on it holds real prompt + raw API
bodies — so retention is also a privacy bound (see [operator-setup-emission-privacy.md](operator-setup-emission-privacy.md) "Privacy consequence").
[`../otel/prune-otel-store.sh`](../otel/prune-otel-store.sh) maintains a two-tier lifecycle:

- **Hot tier** — the NDJSON files the Collector appends (`cc-logs.json` / `cc-metrics.json` /
  `cc-traces.json`), kept byte-compatible with Collector appends, bounded by two per-class windows (knob table
  below). Batch lines past the body window but still inside the structure window get
  **record-granular jq surgery**: their `api_*_body` logRecords are stripped while sibling
  structure records survive in place (97% of body-bearing lines also carry structure events,
  so whole-line dropping would forfeit one class or the other).
- **Cold tier** — `cold/*.parquet` (ZSTD, structure-only). Lines aged past the structure
  window are compacted to a new cold file **before** the hot trim drops them — one file per
  prune run, append-only, so a failed compaction can never corrupt prior cold history and
  always aborts the trim (hot store untouched). Cold is unbounded by design (structure-only
  ≈ tens of MB/month); recheck if `cold/` exceeds ~2 GB. Content boundary: no `api_*_body`
  rows ever reach cold; `user_prompt` rows survive with `body` NULLed and the `prompt`
  attribute scrubbed unless the prompt-keep knob is on. Join keys (`session_id`, `prompt_id`,
  `tool_use_id`, `trace_id`, `span_id`) are always retained — they bridge cold rows to
  on-disk transcript lookups.

### Retention knobs

| Env knob | Default | Semantics |
|---|---|---|
| `CC_OTEL_RETENTION_DAYS` | `7` | Hot window for structure events (everything that is not an `api_*_body` record). Older lines drop from hot — compacted to cold first. |
| `CC_OTEL_BODY_RETENTION_DAYS` | `2` | Hot window for `api_request_body` / `api_response_body` records. Must not exceed the structure window (exit 2 — reject, not clamp). Aged body records are stripped in place; they never reach cold. |
| `CC_OTEL_COLD_KEEP_USER_PROMPTS` | off | `=1` keeps `user_prompt` bodies + the `prompt` attribute un-scrubbed in the cold tier. Default scrubs both (prompt frequency/timing analytics survive either way). |

`RETENTION_DAYS` alone is **not read** — set without `CC_OTEL_RETENTION_DAYS` it exits 2.

```bash
bash "${CLAUDE_PLUGIN_ROOT}"/skills/observability/otel/prune-otel-store.sh --dry-run   # cutoffs + per-class counts, mutates nothing
bash "${CLAUDE_PLUGIN_ROOT}"/skills/observability/otel/prune-otel-store.sh             # prune if needed (stop/compact/trim/restart)
CC_OTEL_RETENTION_DAYS=14 bash "${CLAUDE_PLUGIN_ROOT}"/skills/observability/otel/prune-otel-store.sh   # one-off override
```

`--dry-run` reports per file: `kept=` / `dropped=` (whole-line drops) / `surgery=` (lines
that would lose their body records) / `body_dropped=` (whole-line drops that carried bodies)
/ `would_compact=` (parseable dropped lines — what the cold COPY would receive).

### Overriding the windows machine-wide (setx recipe)

Two override surfaces with different reach — pick by which consumers must honor the value:

- **OS user environment variables (`setx`)** — reach CC sessions AND the daily Scheduled
  Task prune. The recipe for keeping raw bodies a full week and carrying prompts into cold:

  ```text
  setx CC_OTEL_BODY_RETENTION_DAYS 7
  setx CC_OTEL_COLD_KEEP_USER_PROMPTS 1
  ```

  `setx` affects **new** processes only — restart terminals (and `schtasks /run` re-picks
  the environment on its next fire).

- **`.claude/settings.local.json` `env`** — reaches CC sessions only; the Scheduled Task
  never sees it. Use `setx` for anything the unattended prune must honor.

### Safety properties

It is **lock-safe** around the machine-singleton Collector: it holds an mkdir-atomic sentinel
(`.prune-in-progress`) that [`../otel/start-collector.sh`](../otel/start-collector.sh) honors (no respawn
mid-trim — closes the revival race), stops the Collector, then per file: compacts aged lines
to cold, surgically strips aged body records, verifies the trimmed temp parses (`duckdb
read_json_auto`), and only then atomically replaces the hot file. **Compact-before-trim +
verify-before-replace**: every failure path (cold write, cold verify, surgery, hot verify)
aborts with the hot store untouched. A crash between the cold write and the hot replace
re-compacts the same lines next run — duplicate cold rows, never lost ones. It **dry-checks
first** — when nothing exceeds either window it skips the stop/compact/trim/restart entirely,
so a routine run on recent data never churns the Collector. On days with many aged body
lines the jq surgery lengthens the Collector stop from seconds to ~1–2 minutes; the
SessionStart backstop honors the sentinel, so there is no revival race. Also wired into
`/observability clean` (one entry covering the JSONL layers + this OTEL store;
the JSONL layers keep their own 30-day `--keep-days` window).

### Windows — per-user Scheduled Task (no admin)

Like the Collector task, the registration carries machine-specific absolute paths, so it is
**generated from your machine's paths** and never committed. Unlike the Collector daemon — which
invokes the binary directly to avoid a Git Bash dependency at logon — the prune is a bash script,
so the task must invoke `bash.exe` by full path. The script ships inside the installed plugin and
sources sibling helpers, so the task must point at the plugin's own directory: resolve
`${CLAUDE_PLUGIN_ROOT}/skills/observability/otel/prune-otel-store.sh` from a Claude Code
session and substitute that absolute path below (`<plugin-prune-script>`). The plugin cache path
changes on plugin updates — re-register the task after updating the plugin. Daily, off-peak
(minimizes overlap with the brief stop window):

```text
schtasks /create /tn "ClaudeCodeOtelPrune" /sc daily /st 04:00 /rl limited /f /tr ^
  "\"C:\Program Files\Git\bin\bash.exe\" \"<plugin-prune-script>\""
```

With `CC_OTEL_STORE` set (the prerequisite above) the working directory is irrelevant — every
resolved path is absolute. To override the retention windows for this task, use the `setx`
recipe above (user env vars are the only surface the task sees).
**Verify:** `schtasks /query /tn "ClaudeCodeOtelPrune"`;
`schtasks /run /tn "ClaudeCodeOtelPrune"` then re-run a `--dry-run` to confirm the window held.
**Reversal:** `schtasks /delete /tn "ClaudeCodeOtelPrune" /f`.

### macOS / Linux — deferred (recipe)

A `launchd` LaunchAgent with a `StartCalendarInterval` (daily), or a `systemd --user` timer
(`cc-otel-prune.timer` + `.service`), or a cron entry — each running the installed plugin's
`prune-otel-store.sh` (resolve via `${CLAUDE_PLUGIN_ROOT}/skills/observability/otel/`;
re-point after plugin updates) with `CC_OTEL_STORE` exported. Not implemented (Windows-first);
the manual invocation above always works.
