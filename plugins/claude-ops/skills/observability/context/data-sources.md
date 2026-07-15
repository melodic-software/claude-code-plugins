# `/observability` data sources — JSONL + ccusage query catalog

jq pipelines and CLI invocations for **hook-events.jsonl** and **ccusage**. OTEL store
(DuckDB) and Aspire: [read-routing.md](read-routing.md) + [otel-queries.md](otel-queries.md).

## Setup — common variables

```bash
REPO_ROOT=$(git rev-parse --show-toplevel)
HOOK_LOG="${REPO_ROOT}/.claude/observability/hook-events.jsonl"

# Scope → window cutoff (ISO-8601 UTC)
case "$SCOPE" in
  session) SINCE_ISO="" ;;  # filter by session_id at query time
  day) SINCE_ISO=$(date -u -d "1 day ago" +%Y-%m-%dT%H:%M:%SZ) ;;
  week) SINCE_ISO=$(date -u -d "7 days ago" +%Y-%m-%dT%H:%M:%SZ) ;;
  month) SINCE_ISO=$(date -u -d "30 days ago" +%Y-%m-%dT%H:%M:%SZ) ;;
  since:*) SINCE_ISO="${SCOPE#since:}T00:00:00Z" ;;
  all) SINCE_ISO="1970-01-01T00:00:00Z" ;;
esac
```

Cross-platform: `date -u -d "..."` is GNU. macOS BSD date uses `date -u -v-7d`. Skill detects platform — see fallback in implementation.

## 1. ccusage — token + cost

**Preferred path: MCP** (instant, no shell-out per call).

| Tool | Args | Returns |
|---|---|---|
| `mcp__ccusage__daily` | `{ since, until }` (YYYYMMDD) | per-day token + cost rows |
| `mcp__ccusage__session` | `{ since, until }` | per-session-id rows |
| `mcp__ccusage__monthly` | none | per-month aggregates |
| `mcp__ccusage__blocks` | none | 5-hour billing windows (current + recent) |

**Fallback path: CLI** when MCP not yet wired.

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
jq -s --arg since "$SINCE_ISO" '
  map(select(.ts >= $since))
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
' "$HOOK_LOG"
```

**Flag rules:**

- HIGH severity: `p95 > 3000` ms (exceeds the PostToolUse hook 3s warm-cache latency budget) OR `p95 > 5 * p50` (variance outlier)
- MEDIUM: `p95 > 1000` ms but ≤ 3000
- INFO: distribution table

**Error rate per hook:**

```bash
jq -s --arg since "$SINCE_ISO" '
  map(select(.ts >= $since))
  | group_by(.hook)
  | map({
      hook: .[0].hook,
      n: length,
      errors: map(select(.exit_code != 0)) | length,
      err_pct: ((map(select(.exit_code != 0)) | length) * 100 / length)
    })
  | sort_by(-.err_pct)
  | map(select(.err_pct > 0))
' "$HOOK_LOG"
```

Empty: `"hook log empty — set HOOK_OBSERVABILITY_LOG_ENABLED=true and re-run after hooks fire"`.

## 4. Recurring tool-call patterns

n-gram over `(event, hook)` sequences in hook event log. Flag any 3-gram appearing 5+ times in window.

```bash
jq -sr --arg since "$SINCE_ISO" '
  map(select(.ts >= $since))
  | sort_by(.ts)
  | map(.event + ":" + .hook)
' "$HOOK_LOG" \
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
jq -s '
  sort_by(.ts) as $e
  | [range(1; $e | length)
     | select($e[. - 1].hook == $e[.].hook and $e[. - 1].exit_code != 0 and $e[.].exit_code == 0)
     | $e[. - 1].hook]
  | group_by(.) | map({hook: .[0], retries: length})
  | sort_by(-.retries)
' "$HOOK_LOG"
```

Pattern detection across session JSONL transcripts (`~/.claude/projects/<slug>/*.jsonl`) is deferred — schema undocumented.

## 4.5 Hallucination-guard catches (`cli-flag-verify` violations)

`cli-flag-verify` PostToolUse hook (advisory exit 1) emits one `PostToolUse` event per unverifiable `<bin> --<flag>` pair detected in a Write/Edit, discriminated from other `PostToolUse` writers via the `hook` field. Subject format: `<bin>:<sha16>` — bin in clear (groupable), sha16 = first 16 hex of `sha256("<bin> <flag>")` (flag content protected). Schema: whatever envelope the consumer's hook emitter writes; the fields used here are `hook` and `subject`. Per-period count + per-binary breakdown calibrates the verifier (false-positive rate, hallucination hot-spots) and gates the future advisory→blocking exit-2 graduation.

**Per-period count + per-binary breakdown:**

```bash
jq -s --arg since "$SINCE_ISO" '
  map(select(.event == "PostToolUse" and .hook == "cli-flag-verify" and .ts >= $since))
  | { total: length,
      unique_pairs: (map(.subject) | unique | length),
      by_binary: (group_by(.subject | split(":")[0])
                  | map({ bin: .[0].subject | split(":")[0],
                          count: length,
                          unique: (map(.subject) | unique | length) })
                  | sort_by(-.count)) }
' "$HOOK_LOG"
```

**Top recurring hallucinations** (same `<bin>:<sha16>` repeating = same flag re-hallucinated):

```bash
jq -s --arg since "$SINCE_ISO" '
  map(select(.event == "PostToolUse" and .hook == "cli-flag-verify" and .ts >= $since) | .subject)
  | group_by(.) | map({ subject: .[0], count: length })
  | sort_by(-.count) | .[0:10]
' "$HOOK_LOG"
```

**Flag rules:**

- HIGH: same `<bin>:<sha16>` appearing 3+ times (recurring agent confusion — escalation candidate for blocking exit 2 once FP rate < 1%)
- MEDIUM: per-binary count > 5 in window (binary's `--help` may be non-exhaustive — candidate for `HOOK_CLI_FLAG_VERIFY_SKIP_BINS`)
- INFO: total count, unique-pair count, per-binary distribution

Empty: `"no cli-flag-verify violations — verifier may be advisory-clean OR HOOK_OBSERVABILITY_LOG_ENABLED is false / HOOK_CLI_FLAG_VERIFY_LOG_VIOLATIONS_ENABLED is false"`.

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

Out of scope for v1: function/symbol references (needs ctags or Roslyn).

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

- `hook-events.jsonl` schema: whatever the consumer's hook emitter writes — treat the fields used here (`ts`, `hook`, `tool`, `duration_ms`, `exit_code`, `subject`, `status`) as the expected shape and degrade gracefully when fields are absent
- Privacy filter applied at output time: [privacy.md](privacy.md)
- Output template: [output-format.md](output-format.md)
