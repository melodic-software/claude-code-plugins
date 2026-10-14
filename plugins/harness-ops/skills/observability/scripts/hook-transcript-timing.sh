#!/usr/bin/env bash
# /observability hooks — per-hook durations the harness already recorded in session transcripts.
# Read-only; never executes a hook. Reads only the transcript paths given, and from them only the
# duration, hook and event fields: never a hook's stdout, stderr or content.
#
# Usage:
#   bash hook-transcript-timing.sh [--enabled FILE] <transcript.jsonl>...
#   bash hook-transcript-timing.sh --latency [--budget EVENT=MS]... <transcript.jsonl>...
#
#   --enabled FILE    enabled hooks, one `EVENT<TAB>COMMAND` per line (`#` comments), COMMAND as
#                     the transcript records it; each with no sample is listed as unsampled
#   --latency         per-event p50/p95 instead of per-hook rows (the `latency` fallback)
#   --budget EVENT=MS Stop p95 budget for --latency; repeatable, last wins
#
# Sources: Stop from `stop_hook_summary` records (one per firing, every hook); every other event
# from `hook_success` and `hook_non_blocking_error` attachments, which cover only some firings,
# so those rows are labeled sampled. Stop attachments are skipped: the summary already has them.
# A firing's cost is its slowest hook, never a sum: hooks on one event run in parallel.
#
# Exit: 0 read (in --latency, nothing over budget), 1 a Stop p95 over budget (--latency only),
# 2 usage error, unreadable transcript, jq missing, or no hook durations found.

set -uo pipefail

usage() { sed -n '2,21p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
die() {
  printf 'hook-transcript-timing: %s\n' "$1" >&2
  exit 2
}

mode=hooks enabled="" budgets="Stop=2000"
while (($#)); do
  case "$1" in
    --enabled)
      [[ -r "${2:-}" ]] || die "--enabled needs a readable file"
      enabled="$(cat "$2")"
      shift 2
      ;;
    --latency)
      mode=latency
      shift
      ;;
    --budget)
      [[ "${2:-}" =~ ^[A-Za-z]+=[0-9]+$ ]] || die "--budget needs EVENT=MS"
      budgets+=",$2"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    --) shift && break ;;
    -*) die "unknown argument: $1 (see --help)" ;;
    *) break ;;
  esac
done
(($#)) || die "needs at least one transcript path (see --help)"
for t in "$@"; do [[ -r "$t" ]] || die "cannot read transcript: $t"; done
command -v jq >/dev/null 2>&1 || die "jq not found"

# shellcheck disable=SC2016 # jq program, not shell expansion
jq -nrR --arg mode "$mode" --arg enabled "$enabled" --arg budgets "$budgets" '
def q($p): sort as $s | ($s | length) as $n | (($n - 1) * $p) as $h | ($h | floor) as $lo
  | if $lo + 1 < $n then $s[$lo] + ($h - $lo) * ($s[$lo + 1] - $s[$lo]) else $s[$lo] end;
def r: . + 0.5 | floor;
[inputs | fromjson? | objects] as $recs
# One entry per firing: {event, coverage, hooks: [{command, ms}]}. Only these fields are read.
| [ ($recs[] | select(.subtype? == "stop_hook_summary")
      | {event: "Stop", coverage: "complete",
         hooks: [.hookInfos[]? | select(.durationMs | type == "number")
                 | {command: (.command // "?"), ms: .durationMs}]}),
    ($recs | [to_entries[] | .key as $i | .value | select(.type? == "attachment") | .attachment
       | select(.type? == "hook_success" or .type? == "hook_non_blocking_error")
       | select(.durationMs | type == "number")
       | {event: (.hookEvent // (.hookName // "?" | split(":")[0])),
          command: (.command // .hookName // "?"), ms: .durationMs,
          key: (.toolUseID // "line \($i)")}
       | select(.event != "Stop")]
     | group_by([.event, .key])[]
     | {event: .[0].event, coverage: "sampled", hooks: map({command, ms})})
  ] | map(select(.hooks | length > 0)) as $firings
| if ($firings | length) == 0 then "no hook durations found\n" | halt_error(2) else . end
| if $mode == "latency" then
    ([$budgets | split(",")[] | split("=") | {(.[0]): (.[1] | tonumber)}] | add) as $budget
    | ($firings | group_by(.event) | map(
        (map(.hooks | map(.ms) | max)) as $ms
        | {event: .[0].event, coverage: .[0].coverage, n: ($ms | length),
           p50: ($ms | q(0.5) | r), p95: ($ms | q(0.95) | r)}
        | .budget = (if .coverage == "complete" then $budget[.event] else null end)
        | .reason = (if .budget != null and .p95 > .budget then "p95>budget"
                     elif .coverage == "sampled" then "sampled" else "" end))) as $rows
    | (["lane", "hook_event", "fires", "p50", "p95", "budget", "reason"] | @tsv),
      ($rows[] | ["unknown", .event, .n, .p50, .p95, (.budget // "n/a"), .reason] | @tsv),
      (if any($rows[]; .reason == "p95>budget") then "" | halt_error(1) else empty end)
  else
    ($firings | map(.event as $e | .coverage as $c | .hooks[] | .event = $e | .coverage = $c)
      | group_by([.event, .command])
      | map({event: .[0].event, command: .[0].command, coverage: .[0].coverage,
             n: length, median: (map(.ms) | q(0.5) | r)})) as $rows
    | "event\tsamples\tmedian_ms\tcoverage\thook",
      ($rows[] | [.event, .n, .median, .coverage, .command] | @tsv),
      "",
      "slowest hook per event (hooks on one event run in parallel: never sum them)",
      "event\tmedian_ms\thook",
      ($rows | group_by(.event)[] | max_by(.median) | [.event, .median, .command] | @tsv),
      "",
      "unsampled enabled hooks (attachment records likely skip silent successful hooks)",
      "event\thook",
      ($enabled | split("\n")[] | select(test("^[[:space:]]*(#|$)") | not) | split("\t")
        | select(length >= 2) | {event: .[0], command: (.[1:] | join("\t"))}
        | select(. as $h | $rows | any(.event == $h.event and .command == $h.command) | not)
        | [.event, .command] | @tsv)
  end
' "$@"
