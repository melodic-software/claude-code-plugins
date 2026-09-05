# `/claude-ops:observability` data sources — JSONL + ccusage query catalog

jq pipelines and CLI invocations for the **hook log root** and **ccusage**. OTEL store
(DuckDB) and Aspire: [read-routing.md](read-routing.md) + [otel-queries.md](otel-queries.md).

## Setup — common variables

The hook log root is the plugin's `session_event_log_dir` option, project-relative, default
`.observability/claude`. Its rendered value is on the skill body's "Hook log root" line: use
that, never `CLAUDE_PLUGIN_DATA` and never the environment (a skill subprocess inherits no
`CLAUDE_PLUGIN_OPTION_*`). A `--hook-root REL` token on the invocation overrides it for one
run. Under the root: `sessions/<session_id>.jsonl`, one file per session, holding the
per-session event log rows (`source: "event-log"`) and the sink's envelope rows for that
session (`source: "envelope"`); and the shared `hook-events.jsonl`, the legacy shape for
envelopes that carry no session id.

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
HOOK_ROOT_REL="${HOOK_ROOT_REL:-.observability/claude}"   # the rendered option, or the flag
HOOK_ROOT="${REPO_ROOT}/${HOOK_ROOT_REL%/}"

# Scope → window cutoff (ISO-8601 UTC) and file set. Every whole-root query reads
# every session file plus the shared file; a session scope reads one file.
shopt -s nullglob
HOOK_FILES=("$HOOK_ROOT"/sessions/*.jsonl)
shopt -u nullglob
[[ -f "$HOOK_ROOT/hook-events.jsonl" ]] && HOOK_FILES+=("$HOOK_ROOT/hook-events.jsonl")
case "$SCOPE" in
  session)  # the newest session file by mtime, the one still being written
    SINCE_ISO=""
    HOOK_FILES=("$(ls -t "$HOOK_ROOT"/sessions/*.jsonl 2>/dev/null | head -n 1)") ;;
  session:*) SINCE_ISO=""; HOOK_FILES=("$HOOK_ROOT/sessions/${SCOPE#session:}.jsonl") ;;
  day) SINCE_ISO=$(date -u -d "1 day ago" +%Y-%m-%dT%H:%M:%SZ) ;;
  week) SINCE_ISO=$(date -u -d "7 days ago" +%Y-%m-%dT%H:%M:%SZ) ;;
  month) SINCE_ISO=$(date -u -d "30 days ago" +%Y-%m-%dT%H:%M:%SZ) ;;
  since:*) SINCE_ISO="${SCOPE#since:}T00:00:00Z" ;;
  all) SINCE_ISO="1970-01-01T00:00:00Z" ;;
esac
[[ -f "${HOOK_FILES[0]:-}" ]] || echo "hook log empty — see the empty-store line under §2"
```

Never call `jq -s` with an empty file set: it would read stdin. Guard with the test above.

Three row shapes share the root, and the queries below normalize them with one prelude so a
`hook`-keyed query sees the same fields wherever the row came from:

```bash
# Prepend to every jq program: legacy rows carry `event`, per-session rows carry
# `hook_event_name`; only envelope-shaped rows (legacy or per-session) describe a hook.
HOOK_NORM='map(. + {event: (.event // .hook_event_name)})'
```

| Row | Where | Keys |
|---|---|---|
| legacy envelope | `hook-events.jsonl` | `ts event hook tool duration_ms exit_code subject status` |
| per-session envelope (`source: "envelope"`) | `sessions/<id>.jsonl` | the legacy keys with `hook_event_name` for `event`, plus `session_id`, and `changed` (boolean) when the producer sent one |
| per-session event log (`source: "event-log"`) | `sessions/<id>.jsonl` | `ts session_id hook_event_name category status duration_ms` plus `prompt_id tool_use_id agent_id tool_name file_path reason traceparent` when present; no `hook`, and `duration_ms` is the logger's own cost, not a hook's |

Cross-platform: `date -u -d "..."` is GNU. macOS BSD date uses `date -u -v-7d`. Skill detects platform — see fallback in implementation.

## 1. ccusage — token + cost

**Preferred path: MCP** (instant, no shell-out per call).

| Tool | Args | Returns |
|---|---|---|
| `mcp__ccusage__daily` | `{ since, until }` (YYYYMMDD) | per-day token + cost rows |
| `mcp__ccusage__session` | `{ since, until }` | per-session-id rows |
| `mcp__ccusage__monthly` | none | per-month aggregates |
| `mcp__ccusage__blocks` | none | 5-hour billing windows (current + recent) |

**Fallback path: CLI** when the ccusage MCP server is not configured.

```bash
if command -v npx >/dev/null 2>&1; then
  CCUSAGE_JSON=$(MSYS_NO_PATHCONV=1 npx -y ccusage daily --json --since "${SINCE_ISO%%T*}" 2>/dev/null)
fi
```

**Per-model breakdown:**

```bash
echo "$CCUSAGE_JSON" \
  | jq -r '.daily[] | .modelBreakdowns[] | [.modelName, .inputTokens, .outputTokens, .cost] | @tsv' \
  | awk -F'\t' '{ in_t[$1]+=$2; out_t[$1]+=$3; cost[$1]+=$4 }
                END { for (m in cost) printf "%-30s in=%d out=%d $%.2f\n", m, in_t[m], out_t[m], cost[m] }'
```

**5-hour block utilization** (matches statusline's `rate_limits.five_hour`):

```bash
mcp__ccusage__blocks  # call MCP tool
# Or:
npx -y ccusage blocks --json | jq '.blocks[] | select(.isActive==true) | {start: .startTime, tokens: .totalTokens, projectedTokens: .projection.totalTokens}'
```

Empty / missing: emit `"ccusage not installed — npm install -g ccusage or wire MCP"` warning; skip section.

## 2. Hook event log — latency outliers

**p50 / p95 / p99 / max per `(hook, event)`:**

```bash
jq -s --arg since "$SINCE_ISO" "$HOOK_NORM"' | map(select(.ts >= $since and .hook != null))
  | group_by(.hook + "|" + .event)
  | map({
      key: (.[0].hook + " " + .[0].event),
      n: length,
      p50: (sort_by(.duration_ms) | .[length/2|floor].duration_ms),
      p95: (sort_by(.duration_ms) | .[(length*0.95)|floor].duration_ms),
      p99: (sort_by(.duration_ms) | .[(length*0.99)|floor].duration_ms),
      max: (max_by(.duration_ms).duration_ms),
      err_count: (map(select(.exit_code != 0)) | length)
    })
  | sort_by(-.p95)
' "${HOOK_FILES[@]}"
```

**Flag rules:**

- HIGH severity: `p95 > 3000` ms (exceeds the PostToolUse hook 3s warm-cache latency budget) OR `p95 > 5 * p50` (variance outlier)
- MEDIUM: `p95 > 1000` ms but ≤ 3000
- INFO: distribution table

**Error rate per hook:**

```bash
jq -s --arg since "$SINCE_ISO" "$HOOK_NORM"' | map(select(.ts >= $since and .hook != null))
  | group_by(.hook)
  | map({
      hook: .[0].hook,
      n: length,
      errors: map(select(.exit_code != 0)) | length,
      err_pct: ((map(select(.exit_code != 0)) | length) * 100 / length)
    })
  | sort_by(-.err_pct)
  | map(select(.err_pct > 0))
' "${HOOK_FILES[@]}"
```

Empty: `"hook log empty — wire HOOK_TELEMETRY_SINK to your sink script, or turn on session_event_log_enabled, and re-run after hooks fire"`.

## 2.5 Per-session report (`session` and `session:<id>` scopes)

One file, one session. `session` is the newest `sessions/*.jsonl` by mtime (the file the running
session is still appending to); `session:<id>` names one. Rows from the shared
`hook-events.jsonl` carry no session id: they are never joined to a session, and a report that
mentions them says so ("legacy rows, shared file, time proximity only"). Each block below is
one jq over `"${HOOK_FILES[0]}"`.

**Hooks fired, grouped by hook (envelope rows only):**

```bash
jq -s "$HOOK_NORM"' | map(select(.source == "envelope"))
  | group_by(.hook)
  | map({hook: .[0].hook, n: length,
         events: (map(.event) | unique),
         errors: (map(select(.exit_code != 0)) | length),
         p50_ms: (sort_by(.duration_ms) | .[length/2|floor].duration_ms),
         max_ms: (max_by(.duration_ms).duration_ms)})
  | sort_by(-.n)
' "${HOOK_FILES[0]}"
```

**Blocked:** what a guard refused, in order.

```bash
jq -sc "$HOOK_NORM"' | .[] | select(.status == "blocked")
  | {ts, hook, event, subject}' "${HOOK_FILES[0]}"
```

**Rewrote:** what a formatter changed. `changed` is a defined key no producer emits yet
(formatters send `data.findings` only), so this list is empty until one does; render it as
`_no data — no producer reports rewrites yet_`, not as "nothing was rewritten".

```bash
jq -sc "$HOOK_NORM"' | .[] | select(.changed == true)
  | {ts, hook, subject}' "${HOOK_FILES[0]}"
```

**Duration per hook** is the `p50_ms` / `max_ms` pair in the first block; the whole-session
hook cost is `map(select(.source == "envelope") | .duration_ms) | add`. Per-hook duration is
available only for producers that emit `data.session_id` (the nine claude-ops audit hooks
today); a hook that does not still appears in the whole-root §2 tables through the shared file.

**Event timeline** (the per-session event log, opt-in): every hook event the session saw, in
order, with the correlation keys that were present.

```bash
jq -sr '.[] | select(.source == "event-log")
  | [.ts, .hook_event_name, .category, (.tool_name // ""), (.file_path // ""), (.agent_id // "")]
  | @tsv' "${HOOK_FILES[0]}"
```

Every block above slurps (`-s`): the prelude's `map` and the `.[]` walk need one array, and a
JSONL file read without `-s` hands jq one object at a time.

Group by `agent_id` to separate subagent fires from the main thread; group by `prompt_id` for
per-turn counts; `tool_use_id` joins a `PreToolUse` row to its `PostToolUse` (and to the OTEL
`tool_result` event). Empty when `session_event_log_enabled` is off: say so, and point at
`/claude-ops:setup` rather than at the shared file.

## 2.6 Toggles and retention in effect

Render the six options, the guard, and the prune state from one probe call, so the report
shows what the pipeline is doing rather than what the reader assumes. The values are the
rendered `${user_config.*}` from the skill body, passed as flags; an unrendered placeholder
reads as the manifest default.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/skills/observability/scripts/probe-observability-state.sh" --pipeline \
  --root "$HOOK_ROOT_REL" --enabled "<session_event_log_enabled>" \
  --categories "<session_event_log_categories>" --keep-sessions "<session_log_keep_sessions>" \
  --keep-days "<session_log_keep_days>" --pre-prune-command "<session_log_pre_prune_command>"
```

Six fixed lines: `root:`, `guard:`, `sessions:`, `shared:`, `prune-pending:`, `logging:`. Copy
them into the report verbatim under "Toggles and retention in effect". A `WARN` on the
`prune-pending:` line (a moved-aside set older than 24 h) is a MEDIUM finding: the configured
pre-prune command is not finishing, and `/claude-ops:observability clean` sweeps the set. A
`guard: operator-edited` line is a HIGH finding: the hooks are refusing to write. The probe
never heals the guard; `/claude-ops:setup apply` does.

## 3. Tool call decisions — which calls were denied, and why

**Not in hook-events.jsonl or session transcripts.** Permission and policy outcomes are
emitted as OTEL log events (`claude_code.tool_decision`, stored as `event_name='tool_decision'`
in the DuckDB store). Query the OTEL store — do not grep `history.jsonl`, session JSON, or
`~/.claude/sessions/*.json`.

**What it answers:** for each tool invocation, whether it was accepted or rejected and what
mechanism drove the decision.

| Field (promoted column) | Values | Meaning |
|---|---|---|
| `decision` | `accept` / `reject` | Outcome |
| `source` | `config`, … | Bucket for the deciding mechanism — see [Claude Code monitoring docs](https://code.claude.com/docs/en/monitoring-usage) |

**Column mapping:** the OTEL attribute on `tool_decision` events is `source` (official name).
`tool_result` events emit `decision_source` for the same bucket; the DuckDB projection
(`cc-otel.sql`) coalesces both into the promoted `source` column.

A `reject` with `source='config'` is a configuration-driven denial (settings,
allow/deny rules, managed policy, `--allowedTools`/`--disallowedTools`, permission mode,
session grants, inherently-safe tools, etc.). **Attribution caveat:** `config` is one bucket
over many mechanisms — a `reject`+`config` count is an **upper bound** on deny-rule firings
and cannot be pinned to an individual rule. Per-rule attribution is upstream.

DuckDB queries: [otel-queries.md](otel-queries.md) § "Tool decisions".

## 4. Recurring tool-call patterns

n-gram over `(event, hook)` sequences in hook event log. Flag any 3-gram appearing 5+ times in window.

```bash
jq -sr --arg since "$SINCE_ISO" "$HOOK_NORM"' | map(select(.ts >= $since and .hook != null))
  | sort_by(.ts)
  | map(.event + ":" + .hook)
' "${HOOK_FILES[@]}" \
  | python3 -c '
import sys, json, collections
seq = json.load(sys.stdin)
ngrams = collections.Counter(tuple(seq[i:i+3]) for i in range(len(seq)-2))
for k, v in ngrams.most_common(10):
    if v >= 5:
        print(f"{v}× {' → '.join(k)}")
'
```

**Failed-then-fixed sequences:** detect adjacent `exit_code != 0` followed by same-hook `exit_code == 0` — implies user/agent re-edited and same hook fired green.

```bash
jq -s "$HOOK_NORM"' | map(select(.hook != null)) | sort_by(.ts) as $e
  | [range(1; $e | length)
     | select($e[. - 1].hook == $e[.].hook and $e[. - 1].exit_code != 0 and $e[.].exit_code == 0)
     | $e[. - 1].hook]
  | group_by(.) | map({hook: .[0], retries: length})
  | sort_by(-.retries)
' "${HOOK_FILES[@]}"
```

## 4.5 Hallucination-guard catches (`cli-flag-verify` violations)

`cli-flag-verify` PostToolUse hook (advisory exit 1) emits one `PostToolUse` event per unverifiable `<bin> --<flag>` pair detected in a Write/Edit, discriminated from other `PostToolUse` writers via the `hook` field. Subject format: `<bin>:<sha16>` — bin in clear (groupable), sha16 = first 16 hex of `sha256("<bin> <flag>")` (flag content protected). Schema: whatever envelope the consumer's hook emitter writes; the fields used here are `hook` and `subject`. Per-period count + per-binary breakdown calibrates the verifier (false-positive rate, hallucination hot-spots) and gates the future advisory→blocking exit-2 graduation.

**Per-period count + per-binary breakdown:**

```bash
jq -s --arg since "$SINCE_ISO" "$HOOK_NORM"'
  | map(select(.event == "PostToolUse" and .hook == "cli-flag-verify" and .ts >= $since))
  | { total: length,
      unique_pairs: (map(.subject) | unique | length),
      by_binary: (group_by(.subject | split(":")[0])
                  | map({ bin: .[0].subject | split(":")[0],
                          count: length,
                          unique: (map(.subject) | unique | length) })
                  | sort_by(-.count)) }
' "${HOOK_FILES[@]}"
```

**Top recurring hallucinations** (same `<bin>:<sha16>` repeating = same flag re-hallucinated):

```bash
jq -s --arg since "$SINCE_ISO" "$HOOK_NORM"'
  | map(select(.event == "PostToolUse" and .hook == "cli-flag-verify" and .ts >= $since) | .subject)
  | group_by(.) | map({ subject: .[0], count: length })
  | sort_by(-.count) | .[0:10]
' "${HOOK_FILES[@]}"
```

**Flag rules:**

- HIGH: same `<bin>:<sha16>` appearing 3+ times (recurring agent confusion — escalation candidate for blocking exit 2 once FP rate < 1%)
- MEDIUM: per-binary count > 5 in window (binary's `--help` may be non-exhaustive — candidate for the guardrails `cli_flag_verify_skip_bins` option)
- INFO: total count, unique-pair count, per-binary distribution

Empty: `"no cli-flag-verify violations — verifier may be advisory-clean OR the consumer's telemetry sink is not wired/enabled"`.

## 5. Drift candidates (rules-vs-code mismatches)

Initial scope: the consumer project's `.claude/rules/*.md` (when present) cite paths/symbols that don't exist.

```bash
# Extract code-fenced and inline-code paths from rules
grep -oE '`[a-zA-Z0-9_./-]+\.(cs|sh|ts|py|md|json)`' .claude/rules/*.md \
  | sed -E 's/.*`([^`]+)`.*/\1/' \
  | sort -u \
  | while read -r path; do
      if ! git -C "$REPO_ROOT" ls-files --error-unmatch "$path" >/dev/null 2>&1; then
        echo "DRIFT: $path cited but not tracked"
      fi
    done
```

Function and symbol references are out of scope; the check covers file paths only.

## 6. Calibration signal — dismissed observations

If the consumer project has a rule that surfaces side observations, user dismissals are signal that its noise threshold needs tightening. Source: `~/.claude/projects/<slug>/memory/feedback_*.md` lines mentioning "side observation" / "noticed" / "mentioned".

```bash
PROJECT_SLUG=$(echo "$REPO_ROOT" | sed 's|[/:]|-|g; s|^-||')
grep -l -i "side observation\|surfaced\|dismissed" \
  ~/.claude/projects/"$PROJECT_SLUG"/memory/feedback_*.md 2>/dev/null \
  | wc -l
```

INFO bucket only — not actionable per-run.

## 7. Git + GH activity (context for severity)

```bash
git -C "$REPO_ROOT" log --since="$SINCE_ISO" --pretty=tformat:'%h %s' | wc -l
gh pr list --state all --search "created:>=${SINCE_ISO%%T*}" --json number,title,state \
  | jq 'length'
```

Used to anchor "X commits in Y window" trend lines, not for severity.

## Performance

All queries run on file sizes ≤ 50MB without issue. Skill caps total runtime ~10s on warm filesystem; ccusage MCP adds 200ms-2s per call (acceptable on-demand, never poll).

## Cross-references

- Row schemas: the three shapes in "Setup" above. The shared file is whatever the consumer's hook emitter writes — treat the fields used here (`ts`, `hook`, `tool`, `duration_ms`, `exit_code`, `subject`, `status`) as the expected shape and degrade gracefully when fields are absent; the per-session shapes are the reference sink's and `session-event-log.sh`'s (see `hooks/hook-events.registry.json` for which events the event log records)
- The old `.claude/observability/hook-events.jsonl` location is retired (`retirements.yaml` `claude-ops-r001`); `/claude-ops:setup` detects and migrates it. The skill-usage store and the OTEL store still live under `.claude/observability/`
- Privacy filter applied at output time: [privacy.md](privacy.md)
- Output template: [output-format.md](output-format.md)
