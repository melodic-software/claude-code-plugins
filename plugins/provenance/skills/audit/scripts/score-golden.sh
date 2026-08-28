#!/usr/bin/env bash
# Tally case-level precision and recall over the golden set.
#
#   score-golden.sh --golden DIR --actual FILE [--show-config]
#
# Reasoning-free (Brief constraint C1): the verdicts are already decided before
# this runs. `expected.json` carries the hand-scored truth for a case and the
# actual run carries what the audit produced; this script does arithmetic on
# the two, matching on class equality and span overlap. It never judges whether
# a finding is right — that judgment is what the golden set records.
#
# The confusion matrix is CASE-level, per the Brief. One case can be both a
# false negative and a false positive: a positive case where the run missed the
# real span and emitted a different one has failed twice, and collapsing that
# into a single cell would flatter one of the two metrics.
#
#   tp  the case has at least one actual finding matching an expected one
#   fn  a positive case with no matching finding
#   fp  a case with at least one actual finding matching nothing expected
#   tn  a hard negative with no actual findings
#
# What this script refuses to guess: a golden case the run never scored is
# DECLINED and excluded from the tally rather than counted as a miss. Scoring a
# case nobody ran would report a recall failure that describes the harness, not
# the detector. That refusal needs the run to declare its coverage, so the
# actual file carries `cases_run`; without it, `coverage_declared` reports false
# and every case is scored, so the assumption is visible in the product.
#
# Gates bind fix-mode eligibility and release readiness only, never the report
# surface (the Q16 posture). A class below `min_n_per_class` ships report-only:
# a precision bar measured on three cases is not a measurement.
#
# Contract: docs/topics/copied-external-content/design/type-inventory.md
# (golden-set case shape) and capability 16 in the capability matrix.
# Exit: 0 on a clean run, 2 on usage or input error, 3 when the golden
# directory holds no scoreable case, 4 when jq is absent.
set -uo pipefail

GOLDEN=""
ACTUAL=""
SHOW_CONFIG=0

usage() {
  cat <<'EOF'
score-golden.sh — case-level precision/recall over the golden set.

Usage:
  score-golden.sh --golden DIR --actual FILE [--show-config]

  --golden DIR   the golden-set root; one directory per case, each holding
                 expected.json ({findings, negatives, notes})
  --actual FILE  the run's product: {cases_run: [...], findings: [{case, class,
                 tier, span}]}. Without cases_run every case is scored and
                 coverage_declared reports false.
  --show-config  print the effective gate config per layer, then exit

Output: JSON on stdout — {golden, cases, coverage_declared, gates, overall,
by_class, by_case, declined}. Diagnostics go to stderr.
EOF
}

require_opt_value() {
  local opt="$1"
  if [[ $# -lt 2 || -z "${2:-}" || "$2" == -* ]]; then
    echo "score-golden.sh: $opt requires a value" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --golden)
    require_opt_value "$@"
    GOLDEN="$2"
    shift 2
    ;;
  --actual)
    require_opt_value "$@"
    ACTUAL="$2"
    shift 2
    ;;
  --show-config)
    SHOW_CONFIG=1
    shift
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    echo "score-golden.sh: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

command -v jq >/dev/null 2>&1 || {
  echo "score-golden.sh: jq is required" >&2
  exit 4
}

# --- Config cascade (.claude/provenance.json; user-global -> team -> overlay) -----

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CONFIG_ROOT="${CLAUDE_PROJECT_DIR:-$REPO_ROOT}"

CFG_LAYERS=()
[[ -f "${HOME:-/nonexistent}/.claude/provenance.json" ]] && CFG_LAYERS+=("$HOME/.claude/provenance.json")
[[ -f "$CONFIG_ROOT/.claude/provenance.json" ]] && CFG_LAYERS+=("$CONFIG_ROOT/.claude/provenance.json")
[[ -f "$CONFIG_ROOT/.claude/provenance.local.json" ]] && CFG_LAYERS+=("$CONFIG_ROOT/.claude/provenance.local.json")

# cfg_num <jq-path> <default>: last layer that defines the key wins (per-key
# override). A non-numeric value is ignored rather than propagated, so a typo in
# one layer falls back to the default instead of poisoning the arithmetic.
# Carriage returns are stripped for the Windows-jq CRLF reason (ai-slop #3343).
cfg_num() {
  local path="$1" out="$2" layer v
  for layer in ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}; do
    v="$(jq -r "$path // empty" "$layer" 2>/dev/null)" || continue
    v="${v//$'\r'/}"
    [[ "$v" =~ ^[0-9]+(\.[0-9]+)?$ ]] && out="$v"
  done
  printf '%s' "$out"
}

FIX_PRECISION_BAR="$(cfg_num '.gates.fix_precision_bar' 0.95)"
REPORT_RECALL_FLOOR="$(cfg_num '.gates.report_recall_floor' 0.8)"
MIN_N_PER_CLASS="$(cfg_num '.gates.min_n_per_class' 10)"

if [[ "$SHOW_CONFIG" -eq 1 ]]; then
  echo "Config layers (later refines earlier):"
  if [[ "${#CFG_LAYERS[@]}" -eq 0 ]]; then
    echo "  (none; bundled defaults)"
  else
    for layer in "${CFG_LAYERS[@]}"; do echo "  $layer"; done
  fi
  echo "Effective: gates.fix_precision_bar=$FIX_PRECISION_BAR"
  echo "Effective: gates.report_recall_floor=$REPORT_RECALL_FLOOR"
  echo "Effective: gates.min_n_per_class=$MIN_N_PER_CLASS"
  exit 0
fi

# --- Inputs ----------------------------------------------------------------------

[[ -n "$GOLDEN" && -n "$ACTUAL" ]] || {
  echo "score-golden.sh: --golden and --actual are both required" >&2
  usage >&2
  exit 2
}
[[ -d "$GOLDEN" ]] || {
  echo "score-golden.sh: not a directory: $GOLDEN" >&2
  exit 2
}
[[ -f "$ACTUAL" ]] || {
  echo "score-golden.sh: not a readable file: $ACTUAL" >&2
  exit 2
}
jq -e . "$ACTUAL" >/dev/null 2>&1 || {
  echo "score-golden.sh: --actual is not valid JSON: $ACTUAL" >&2
  exit 2
}

# One object keyed by case id. A case directory whose expected.json will not
# parse is skipped loudly rather than silently: an unreadable expectation would
# otherwise vanish from the denominator.
EXPECTED_PARTS=()
MALFORMED=()
while IFS= read -r dir; do
  [[ -n "$dir" ]] || continue
  id="$(basename "$dir")"
  exp="$dir/expected.json"
  [[ -f "$exp" ]] || continue
  if ! jq -e . "$exp" >/dev/null 2>&1; then
    MALFORMED+=("$id")
    echo "score-golden.sh: $exp is not valid JSON; case excluded" >&2
    continue
  fi
  EXPECTED_PARTS+=("$(jq -c --arg id "$id" '{($id): .}' "$exp")")
done < <(find "$GOLDEN" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | LC_ALL=C sort)

if [[ "${#EXPECTED_PARTS[@]}" -eq 0 ]]; then
  echo "score-golden.sh: no case directory under $GOLDEN carries a readable expected.json" >&2
  exit 3
fi

EXPECTED_JSON="$(printf '%s\n' "${EXPECTED_PARTS[@]}" | jq -s 'add // {}')"
MALFORMED_JSON="$(printf '%s\n' ${MALFORMED[@]+"${MALFORMED[@]}"} | jq -R . | jq -s 'map(select(. != ""))')"

# --- Tally -----------------------------------------------------------------------

jq -n \
  --arg golden "$GOLDEN" \
  --argjson expected "$EXPECTED_JSON" \
  --argjson malformed "$MALFORMED_JSON" \
  --slurpfile actual "$ACTUAL" \
  --argjson gates "{\"fix_precision_bar\": $FIX_PRECISION_BAR, \"report_recall_floor\": $REPORT_RECALL_FLOOR, \"min_n_per_class\": $MIN_N_PER_CLASS}" '

# Spans overlap when neither is missing and the intervals touch. A missing span
# on either side means the expectation is case-level, so class equality decides.
def overlaps($e; $a):
  ($e.span.start_line) as $es | (($e.span.end_line) // ($e.span.start_line)) as $ee
  | ($a.span.start_line) as $as | (($a.span.end_line) // ($a.span.start_line)) as $ae
  | if $es == null or $as == null then true else ($es <= $ae) and ($as <= $ee) end;

def matched($e; $a): ($e.class == $a.class) and overlaps($e; $a);

def ratio($n; $d): if $d == 0 then null else ($n / $d) end;

($actual[0] // {}) as $act
| ($act.findings // []) as $af
| ($act.cases_run // null) as $run
| ($run != null) as $covdecl
| ($af | map(select(.case != null)) | group_by(.case)
        | map({key: .[0].case, value: .}) | from_entries) as $byc
| ($expected | keys) as $ids

| [ $ids[]
    | . as $id
    | $expected[$id] as $e
    | (($e.findings) // []) as $ef
    | ((($e.negatives) == true) or (($ef | length) == 0)) as $isneg
    | (if $isneg then "negative" else ((($ef[0]).class) // "unclassified") end) as $cls
    | (($byc[$id]) // []) as $aa
    | (if $covdecl and (($run | map(select(. == $id)) | length) == 0)
       then "declined" else "scored" end) as $state
    | ([$aa[] | . as $a | select([$ef[] | select(matched(.; $a))] | length > 0)]) as $hit
    | ([$aa[] | . as $a | select([$ef[] | select(matched(.; $a))] | length == 0)]) as $miss
    | {
        case: $id,
        class: $cls,
        state: $state,
        tp: (if $state == "scored" and ($hit | length) > 0 then 1 else 0 end),
        fn: (if $state == "scored" and ($isneg | not) and ($hit | length) == 0 then 1 else 0 end),
        fp: (if $state == "scored" and ($miss | length) > 0 then 1 else 0 end),
        tn: (if $state == "scored" and $isneg and (($aa | length) == 0) then 1 else 0 end)
      }
    | . + { verdict: (
        if .state == "declined" then "declined"
        else ([ (if .tp == 1 then "tp" else empty end),
                (if .fn == 1 then "fn" else empty end),
                (if .fp == 1 then "fp" else empty end),
                (if .tn == 1 then "tn" else empty end) ] | join("+"))
        end) }
  ] as $cases

| ([$cases[] | select(.state == "scored")]) as $scored
| ([$scored[] | .tp] | add // 0) as $tp
| ([$scored[] | .fn] | add // 0) as $fn
| ([$scored[] | .fp] | add // 0) as $fp
| ([$scored[] | .tn] | add // 0) as $tn

| ([$cases[] | select(.state == "declined") | .case]) as $notrun
| ([$af[] | .case // "(unnamed)"] | unique
   | map(. as $c | select(($ids | map(select(. == $c)) | length) == 0))) as $stray

| {
    golden: $golden,
    cases: ($cases | length),
    coverage_declared: $covdecl,
    gates: $gates,
    overall: {
      scored: ($scored | length),
      tp: $tp, fp: $fp, fn: $fn, tn: $tn,
      precision: ratio($tp; $tp + $fp),
      recall: ratio($tp; $tp + $fn)
    },
    by_class: (
      $scored | group_by(.class) | map(
        (. | length) as $n
        | ([.[] | .tp] | add // 0) as $ctp
        | ([.[] | .fp] | add // 0) as $cfp
        | ([.[] | .fn] | add // 0) as $cfn
        | ([.[] | .tn] | add // 0) as $ctn
        | ratio($ctp; $ctp + $cfp) as $cp
        | ratio($ctp; $ctp + $cfn) as $cr
        | {
            class: .[0].class,
            n: $n, tp: $ctp, fp: $cfp, fn: $cfn, tn: $ctn,
            precision: $cp,
            recall: $cr,
            meets_precision_bar: (if $cp == null then null else ($cp >= $gates.fix_precision_bar) end),
            meets_recall_floor: (if $cr == null then null else ($cr >= $gates.report_recall_floor) end),
            gate: (if $n >= $gates.min_n_per_class
                   then "binding"
                   else "report-only (n=\($n) below min_n_per_class=\($gates.min_n_per_class))"
                   end)
          })
    ),
    by_case: $cases,
    declined: (
      [ (if ($notrun | length) > 0 then
          {reason: "case not scored by this run (absent from cases_run)",
           count: ($notrun | length), cases: $notrun} else empty end),
        (if ($stray | length) > 0 then
          {reason: "finding for a case not in the golden set",
           count: ($stray | length), cases: $stray} else empty end),
        (if ($malformed | length) > 0 then
          {reason: "expected.json is not valid JSON",
           count: ($malformed | length), cases: $malformed} else empty end) ]
    )
  }
'
