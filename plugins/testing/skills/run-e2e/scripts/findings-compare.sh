#!/usr/bin/env bash
set -uo pipefail

usage() {
  echo "usage: findings-compare.sh [--baseline <findings.json>] <findings.json>" >&2
  exit 2
}

baseline=""
newer=""
while (($#)); do
  case "$1" in
  --baseline)
    (($# >= 2)) || usage
    baseline="$2"
    shift 2
    ;;
  -*) usage ;;
  *)
    [[ -z "$newer" ]] || usage
    newer="$1"
    shift
    ;;
  esac
done
[[ -n "$newer" ]] || usage

command -v jq >/dev/null 2>&1 || {
  echo "findings-compare.sh: jq is required" >&2
  exit 2
}

check_file() {
  [[ -f "$1" && -r "$1" ]] || {
    echo "findings-compare.sh: cannot read $1" >&2
    exit 2
  }
  local problem
  if ! problem="$(jq -rs '
    def str: type == "string" and length > 0;
    def part_ok: .part == null or (.part | str);
    if length != 1 then "not exactly one JSON value" else .[0] |
    if type != "object" then "not a JSON object"
    elif (.pass | type) != "object" then "no pass object"
    elif (.pass.build | str) | not then "pass.build is not a non-empty string"
    elif (.pass.entries | type) != "array" then "pass.entries is not an array"
    elif any(.pass.entries[]; (type != "object") or ((.feature | str) | not) or (part_ok | not)
        or ((.entry_point | str) | not) or ((.outcome | IN("passed", "failed", "not checked")) | not))
      then "an entry lacks feature, part, entry_point or a known outcome"
    elif (.findings | type) != "array" then "findings is not an array"
    elif any(.findings[]; (type != "object") or ((.id | str) | not) or ((.feature | str) | not)
        or (part_ok | not) or ((.entry_points | type) != "array")
        or ((.entry_points | length) == 0) or any(.entry_points[]; str | not))
      then "a finding lacks id, feature, part or entry_points"
    elif ([.findings[].id] | length) != ([.findings[].id] | unique | length)
      then "two findings share an id"
    else empty end end' "$1" 2>/dev/null)"; then
    echo "findings-compare.sh: $1 is not JSON" >&2
    exit 2
  fi
  [[ -z "$problem" ]] || {
    echo "findings-compare.sh: $1: $problem" >&2
    exit 2
  }
}

check_file "$newer"
if [[ -n "$baseline" ]]; then
  check_file "$baseline"
  base_args=(--slurpfile base "$baseline")
else
  base_args=(--argjson base '[]')
fi

# shellcheck disable=SC2016 # $vars are jq's
jq -n --slurpfile cur "$newer" "${base_args[@]}" '
  def labels: ["NEW", "PRE-EXISTING", "GONE", "not checked"];
  def severities: ["critical", "high", "medium", "low"];
  def key($f; $p; $e): [$f, $p, $e] | tojson;
  ($cur[0]) as $n
  | ($base[0] // null) as $b
  | ([$n.findings[].id]) as $nids
  | ([($b // {findings: []}).findings[].id]) as $bids
  | ([$n.pass.entries[] | select(.outcome != "not checked")
      | key(.feature; .part; .entry_point)]) as $driven
  | ([$n.pass.entries[] | select(.outcome == "not checked")
      | {key: key(.feature; .part; .entry_point), value: (.reason // "not checked")}]
      | from_entries) as $skipped
  | ([$n.findings[]
      | . + {compare: (if (.id | IN($bids[])) then "PRE-EXISTING" else "NEW" end)}]
    + [($b // {findings: []}).findings[] | select((.id | IN($nids[])) | not)
      | . as $f
      | [$f.entry_points[] | key($f.feature; $f.part; .) as $k
          | select(($k | IN($driven[])) | not)
          | {entry_point: ., reason: ($skipped[$k] // "not in the newer pass")}] as $missing
      | if ($missing | length) == 0 then $f + {compare: "GONE"}
        else $f + {compare: "not checked", not_driven: $missing} end])
  | sort_by([(.compare as $c | labels | index($c)),
             (.severity as $s | severities | index($s) // 99), .id]) as $all
  | {
      builds: {baseline: ($b.pass.build // null), newer: $n.pass.build},
      counts: (labels | map({key: ., value: (. as $l | [$all[] | select(.compare == $l)] | length)})
               | from_entries),
      findings: $all
    }'
