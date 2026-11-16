#!/usr/bin/env bash
# Compares two live verification passes, each a findings.json
# (../schemas/findings.schema.json), and labels every finding id. No model
# call: ids are matched exactly.
#
#   findings-compare.sh [--baseline <findings.json>] <findings.json>
#
# The positional file is the newer pass. Labels:
#   NEW           the id is in the newer pass and not in the baseline
#   PRE-EXISTING  the id is in both
#   GONE          the id is only in the baseline, and the newer pass drove
#                 (passed or failed) every entry point the baseline finding
#                 lists, for its feature and part
#   not checked   the id is only in the baseline, and at least one of its entry
#                 points was not driven in the newer pass; not_driven names
#                 each one and why
# With no --baseline every finding in the newer pass is NEW.
#
# Prints one JSON object on stdout: builds (baseline, newer), counts per
# label, and findings, each the finding's record plus `compare` (its label),
# ordered NEW, PRE-EXISTING, GONE, not checked, then by severity (critical
# first), then by id. A PRE-EXISTING record is the newer pass's; a GONE or
# not checked record is the baseline's.
#
# Exit 0 on a comparison, 2 on a usage error, a missing jq, or a file that is
# not a findings.json (unreadable, not JSON, a missing field, a duplicate id).
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

# check_file <path>: exit 2 unless the file holds the fields this script reads.
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
