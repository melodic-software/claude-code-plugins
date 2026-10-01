# Operator setup: retention

Parent: [`operator-setup.md`](operator-setup.md). Privacy tie-in: [`operator-setup-emission-privacy.md`](operator-setup-emission-privacy.md).

## Pruning the store (retention): two tiers

The store grows unbounded otherwise, and with full capture on it holds real prompt + raw API
bodies, so retention is also a privacy bound (see [operator-setup-emission-privacy.md](operator-setup-emission-privacy.md) "Privacy consequence").
[`../otel/prune-otel-store.sh`](../otel/prune-otel-store.sh) maintains a two-tier lifecycle:

- **Hot tier**: the NDJSON files the Collector appends (`cc-logs.json` / `cc-metrics.json` /
  `cc-traces.json`), kept byte-compatible with Collector appends, bounded by two per-class windows (knob table
  below). Batch lines past the body window but still inside the structure window get
  **record-granular jq surgery**: their `api_*_body` logRecords are stripped while sibling
  structure records survive in place (most body-bearing lines also carry structure events, so
  whole-line dropping would forfeit one class or the other).
- **Cold tier**: `cold/*.parquet` (ZSTD, structure-only). Lines aged past the structure
  window are compacted to a new cold file **before** the hot trim drops them, one file per
  prune run, append-only, so a failed compaction can never corrupt prior cold history and
  always aborts the trim (hot store untouched). Cold is unbounded by design. Measured: 72 MB
  over about 5 weeks (1.38M log rows, 2026-08-16 to 2026-09-22); recheck if `cold/` exceeds ~2 GB. Content boundary: no `api_*_body`
  rows ever reach cold; `user_prompt` rows survive with `body` NULLed and the `prompt` and
  `prompt_text` attributes scrubbed unless the prompt-keep knob is on. `prompt_text` is a copy
  of `prompt` on the `user_prompt` event. Basis: Claude Code 2.1.287 changelog entry ("Added
  `prompt_text` to the OpenTelemetry `user_prompt` event, a copy of `prompt`"),
  <https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md>. Verified 2026-10-01
  against that file and the installed 2.1.287 binary; recheck when a release adds another
  prompt-bearing attribute to `user_prompt`. Cold files written by a prune under Claude Code
  2.1.287 or later with claude-ops before 0.80.2 still carry `prompt_text`: compaction scrubs
  only what it compacts. A normal prune prints a `notice:` line when a cold file still holds
  prompt content, and stops scanning once `cold/.prompt-scrub-clean` records a clean scan
  (a compaction with the keep knob on removes it); `prune-otel-store.sh --scrub-cold` rewrites those files in place with the
  same scrub, keeping every row and every other attribute (`--dry-run` lists them first). If
  the scrub cannot run, deleting the `cold/*.parquet` files written since you installed 2.1.287
  also closes the exposure, at the cost of that span of structure history. Join keys (`session_id`, `prompt_id`,
  `tool_use_id`, `trace_id`, `span_id`) are always retained. They bridge cold rows to
  on-disk transcript lookups.

Hot is far larger than cold because log lines carry inline API bodies. Measured on melo-lap-001
on 2026-09-28: 7 days of logs held 790 MB; unpruned, `cc-logs.json` reached 2.8 GB and
`cc-metrics.json` 361 MB. Recheck if the store traffic mix changes (for example body capture
turned off). The size cap below bounds each hot file even when every line is inside the age windows.

### Retention knobs

| Env knob | Default | Semantics |
|---|---|---|
| `CC_OTEL_RETENTION_DAYS` | `7` | Hot window for structure events (everything that is not an `api_*_body` record). Older lines drop from hot, compacted to cold first. |
| `CC_OTEL_BODY_RETENTION_DAYS` | `2` | Hot window for `api_request_body` / `api_response_body` records. Must not exceed the structure window (exit 2, reject rather than clamp). Aged body records are stripped in place; they never reach cold. |
| `CC_OTEL_HOT_MAX_MB` | `1024` | Size cap per hot file in MiB; `0` disables. A file over the cap drops its oldest lines, compacted to cold first, until it fits, even inside the age windows. Must be a non-negative integer (exit 2 otherwise). |
| `CC_OTEL_COLD_KEEP_USER_PROMPTS` | off | `=1` keeps `user_prompt` bodies + the `prompt` and `prompt_text` attributes un-scrubbed in the cold tier. Default scrubs both (prompt frequency/timing analytics survive either way). |

`RETENTION_DAYS` alone is **not read**. Set without `CC_OTEL_RETENTION_DAYS` it exits 2.

```bash
bash "<skill-dir>/otel/prune-otel-store.sh" --dry-run   # cutoffs + per-class counts, mutates nothing
bash "<skill-dir>/otel/prune-otel-store.sh"             # prune if needed (stop/compact/trim/start)
CC_OTEL_RETENTION_DAYS=14 bash "<skill-dir>/otel/prune-otel-store.sh"   # one-off override
```

The Collector `fileexporter` can rotate its own files, but its README says "If `append: true` is set
then setting `rotation` is currently not supported". This store needs `append: true`, so the
external prune is the only size and age bound. Basis:
<https://github.com/open-telemetry/opentelemetry-collector-contrib/blob/main/exporter/fileexporter/README.md>
("File Rotation and Append Option"). Verified 2026-09-29 against that page as fetched that day;
recheck when the exporter README drops the restriction.

`--dry-run` also prints `hot_max_mb=` and, per file over the cap, a `size_prune cutoff_epoch_seconds=`
line, plus `size_pruned_files=` in the final `action=dry-run` line. It reports per file: `kept=` / `dropped=` (whole-line drops) / `surgery=` (lines
that would lose their body records) / `body_dropped=` (whole-line drops that carried bodies)
/ `would_compact=` (parseable dropped lines, what the cold COPY would receive).

### Overriding the windows machine-wide (setx recipe)

Two override surfaces with different reach. Pick by which consumers must honor the value:

- **OS user environment variables (`setx`)** reach CC sessions AND the daily Scheduled
  Task prune. The recipe for keeping raw bodies a full week and carrying prompts into cold:

  ```text
  setx CC_OTEL_BODY_RETENTION_DAYS 7
  setx CC_OTEL_COLD_KEEP_USER_PROMPTS 1
  ```

  `setx` affects **new** processes only, so restart terminals (and `schtasks /run` re-picks
  the environment on its next fire).

- **`.claude/settings.local.json` `env`** reaches CC sessions only; the Scheduled Task
  never sees it. Use `setx` for anything the unattended prune must honor.

### Safety properties

It is **lock-safe** around the machine-singleton Collector: it holds a sentinel directory
(`.prune-in-progress`), claimed by an O_EXCL owner token, so concurrent prunes cannot overlap, stops the provisioning-owned
`otelcol-contrib` Windows service, then per file: compacts aged lines
to cold, surgically strips aged body records, verifies the trimmed temp parses (`duckdb
read_json_auto`), and only then atomically replaces the hot file. **Compact-before-trim +
verify-before-replace**: every failure path (cold write, cold verify, surgery, hot verify)
aborts with the hot store untouched. A crash between the cold write and the hot replace
re-compacts the same lines next run, producing duplicate cold rows, never lost ones. It **dry-checks
first**: when nothing exceeds either window it skips the stop/compact/trim/start entirely,
so a routine run on recent data never churns the Collector. On days with many aged body
lines the jq surgery lengthens the Collector stop from seconds to ~1–2 minutes. The service has
no independent recovery restart, so the prune owns the complete stop → trim → start cycle. Also
holds the sentinel through the restart attempt and releases it last; an unreadable service state
is an error, never treated as `Stopped`, so the hot store stays untouched and cleanup attempts the
restart. It is wired into `/claude-ops:observability clean` (one entry covering the JSONL layers + this OTEL store;
the JSONL hook-events layer (`hook-events.jsonl` and its rotated `.1`, which the sink rotates at the size cap whatever the session-log switch is set to) keeps its own 30-day `--keep-days` window, and the opt-in skill-usage
layer its own 365-day `--keep-skill-usage-days` window, longer because a starvation report wants
long history and those rows carry names and branches only, no content).

### Windows: the provisioned daily Scheduled Task (no admin)

Machine provisioning registers the prune on each fleet host as `ClaudeCodeOtelPrune`: daily at
04:00 (off-peak, so the brief Collector stop rarely overlaps a session), as the console account,
run level `Limited`. The same apply converges the scoped `SERVICE_STOP | SERVICE_START` grant the
prune needs; the grant includes no service-configuration or ACL-writing rights.

The task runs a launcher, not a fixed path. On every run it reads the user-scope entry for this
plugin (key `claude-ops@<marketplace>`) in `installed_plugins.json` (under `CLAUDE_CONFIG_DIR`,
else `~/.claude/plugins/`) and runs `skills/observability/otel/prune-otel-store.sh` from that
`installPath` through Git Bash (a machine or a user-scope Git for Windows install). A plugin
update therefore needs no re-registration, and the 14-day orphan sweep of an old version directory
cannot strand the task. The log is `%LOCALAPPDATA%\provisioning\logs\ClaudeCodeOtelPrune.log`: one
UTC timestamp line per run, the prune's output, then `done: <plugin key> <version>` or
`failed: <reason>`. A missing plugin, a missing script and a failed prune each exit 1.

The contract between the two repositories is three names: the plugin key, the in-plugin path
`skills/observability/otel/prune-otel-store.sh`, and `CC_OTEL_STORE`. Renaming or moving the
script, or publishing the plugin from another marketplace, breaks the task. Basis:
`Get-OtelStorePruneArgument` in provisioning's `common/Provisioning.psm1` and the
`ClaudeCodeOtelPrune` rows of `hosts/*/Set-MachineConfiguration.ps1`
(melodic-software/provisioning#669, merged as `16aefbe`), read 2026-10-01; recheck when either
repository changes one of the three names.

A task registered by hand from an earlier version of this page names a versioned cache path or a
copied script. The next provisioning apply replaces it in place under the same name. On a machine
without that provisioning, register an equivalent daily task whose action finds the install path
at run time; one that names the versioned path breaks after the next plugin update.

The task sees only OS user environment variables, so use the `setx` recipe above to override its
retention windows.
**Verify:** `bash <skill-dir>/scripts/probe-observability-state.sh --otel-store` prints six lines:
the three hot files, `cold:<bytes>B (<n> files)`, `last-prune:<UTC time> (<age>)`, and
`prune-task:<state>`. Every successful non-dry prune writes `<store>/.last-prune`;
`last-prune:never` or an age of `2d` or more means the task is not firing or is failing (read its
log). The `prune-task:` states, none of which prints text from the task, since the line reaches
model context (read the action with `schtasks /query /tn "ClaudeCodeOtelPrune" /xml`):

| State | Meaning |
|---|---|
| `provisioned` | enabled, and the action is pwsh running the provisioning launcher: it names `installed_plugins.json`, the `claude-ops@` plugin key and the in-plugin prune path |
| `missing` | no `ClaudeCodeOtelPrune` task: run the provisioning apply |
| `disabled` | the task or its trigger is disabled |
| `stale path` | a hand-registered task names a prune script that no longer exists, typically a version directory the orphan sweep removed |
| `hand-registered` | a hand-registered task whose script still exists: a versioned path breaks at the next plugin update, and a copied script never gets fixes |
| `unrecognized action` | the task runs neither the launcher nor a prune script; a UNC path is never tested |
| `n/a (not Windows)`, `unknown (schtasks not found)` | not checked |

Provisioning's `-Test` also reports the task, and reports drift when the hot files pass 1 GiB
together or `cold/` passes 2 GiB. To run the task now, `schtasks /run /tn "ClaudeCodeOtelPrune"`
from cmd.exe, then re-run a `--dry-run` to confirm the window held.
**Reversal:** provisioning owns the task; remove it there (its host runbook), not by hand, or the
next apply registers it again.

### macOS / Linux: lifecycle integration required

`--dry-run` remains portable, but a mutating prune is Windows-first because its safe file-handle
cycle targets the provisioning-owned Windows service. Do not schedule a mutating prune on macOS
or Linux until machine provisioning owns an equivalent service and the lifecycle helper supports
that service manager.
