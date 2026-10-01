#!/usr/bin/env bash
# metrics.sh: the task-end judge's calibration numbers, from labels.tsv (the
# DT9 columns plus stratum and split; docs/specs/tautological-tests-judge/).
#
#   metrics.sh [labels.tsv]          per stratum, then pooled as "all": Cohen's
#                                    kappa user vs model rater, judge vs user and
#                                    judge vs model rater; the judge's confusion
#                                    matrix against the adjudicated label; FLAG
#                                    precision and recall with Wilson 95%
#                                    intervals; prevalence; UNKNOWN counts
#   metrics.sh --check [labels.tsv]  exit 1 unless every row has both rater
#                                    labels, a stratum and a split; holdout is at
#                                    least a third of each stratum; user vs model
#                                    kappa is at least 0.6; and every commit to
#                                    the judge prompt is an ancestor of the first
#                                    commit to labels.tsv, or calibration.md
#                                    carries a `holdout-only: <sha>` line for it
#                                    (its metrics are re-measured on holdout only)
#   metrics.sh --sweep [labels.tsv]  run the judge over every case for haiku,
#                                    sonnet and opus at low and medium effort,
#                                    through judge::run and judge::validate (what
#                                    the hooks relay), keep each arm's verdicts in
#                                    sweep/<model>-<effort>.tsv beside the labels,
#                                    and print the sweep table: holdout FLAG
#                                    precision and recall, UNKNOWN rate, cost
#
# Labels are FLAG, PASS or UNKNOWN. In FLAG precision and recall an UNKNOWN on
# an adjudicated FLAG is a miss, and only an adjudicated FLAG is a hit. Kappa
# prints NA when no row has both labels or chance agreement is 1. Intervals
# use z = 1.959964 and print to 4 decimals.
#
# A case file is cases/<id>.<real name>.fixture. The sweep copies it, and every
# cases/<id>.*.fixture beside it (an implementation the case ships with), into
# an empty temporary repository under its real name, so the judge sees no id,
# label or other case. TEST_JUDGE_CMD (the hooks' seam) replaces `claude`.
set -uo pipefail

# The sweep runs this script as the judge command to read each run's cost.
if [[ -n "${CAL_JUDGE_INNER:-}" ]]; then
  out="$("$CAL_JUDGE_INNER" "$@")"
  rc=$?
  printf '%s\n' "$out"
  jq -r '.total_cost_usd? // 0' <<<"$out" >>"$CAL_COST_LOG" 2>/dev/null
  exit "$rc"
fi

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/${BASH_SOURCE[0]##*/}"
HOOKS="${SELF%/*}/../../../../hooks"
PROMPT=plugins/testing/hooks/test-judge-prompt.md
CALMD=docs/specs/tautological-tests-judge/calibration.md

AWK_LIB='
function wilson(x, t,   p, d, c, h, lo, hi) {
  if (!t) return "NA (0/0)"
  p = x / t; d = 1 + Z * Z / t
  c = (p + Z * Z / (2 * t)) / d
  h = Z * sqrt(p * (1 - p) / t + Z * Z / (4 * t * t)) / d
  lo = c - h; hi = c + h
  if (lo < 0) lo = 0
  if (hi > 1) hi = 1
  return sprintf("%.4f [%.4f, %.4f] (%d/%d)", p, lo, hi, x, t)
}
BEGIN { FS = "\t"; Z = 1.959964; split("FLAG PASS UNKNOWN", L, " ") }
'

report() {
  awk "$AWK_LIB"'
    NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; next }
    {
      s = $col["stratum"]
      if (!(s in seen)) { seen[s] = 1; order[++ns] = s }
      add(s); add("all")
    }
    function add(g,   h, m, a, j) {
      n[g]++
      h = $col["human_label"]; m = $col["model_label"]; a = $col["adjudicated_label"]; j = $col["judge_verdict"]
      pair(g, "user-model", h, m); pair(g, "judge-user", j, h); pair(g, "judge-model", j, m)
      if (j != "" && a != "") cm[g, j, a]++
      if (a != "") { na[g]++; if (a == "FLAG") pf[g]++; if (a == "UNKNOWN") au[g]++ }
      if (j == "UNKNOWN") ju[g]++
    }
    function pair(g, k, x, y) {
      if (x == "" || y == "") return
      pn[g, k]++; if (x == y) po[g, k]++
      px[g, k, x]++; py[g, k, y]++
    }
    function kappa(g, k,   t, e, i, o) {
      t = pn[g, k]
      if (!t) return "NA"
      o = po[g, k] / t; e = 0
      for (i = 1; i <= 3; i++) e += px[g, k, L[i]] * py[g, k, L[i]]
      e /= t * t
      if (e >= 1) return "NA"
      return sprintf("%.4f", (o - e) / (1 - e))
    }
    function show(g,   k, i, j, a, tp, jf, af) {
      print "stratum " g " n=" n[g]
      split("user-model judge-user judge-model", K, " ")
      for (i = 1; i <= 3; i++) print "kappa " K[i] " " g " " kappa(g, K[i]) " (n=" pn[g, K[i]] + 0 ")"
      for (i = 1; i <= 3; i++) {
        printf "confusion %s judge=%s", g, L[i]
        for (j = 1; j <= 3; j++) printf " %s=%d", L[j], cm[g, L[i], L[j]]
        printf "\n"
      }
      tp = cm[g, "FLAG", "FLAG"]; jf = af = 0
      for (j = 1; j <= 3; j++) { jf += cm[g, "FLAG", L[j]]; af += cm[g, L[j], "FLAG"] }
      print "flag-precision " g " " wilson(tp, jf)
      print "flag-recall " g " " wilson(tp, af)
      print "prevalence " g " " (na[g] ? sprintf("%.4f (%d/%d)", pf[g] / na[g], pf[g], na[g]) : "NA (0/0)")
      print "unknown " g " judge=" ju[g] + 0 " adjudicated=" au[g] + 0
    }
    END { for (i = 1; i <= ns; i++) show(order[i]); show("all") }
  ' "$1"
}

check() {
  local labels="$1" bad=0 k top abs first p s marked
  awk '
    BEGIN { FS = "\t"; ok["FLAG"] = ok["PASS"] = ok["UNKNOWN"] = 1 }
    NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; next }
    {
      id = $col["id"]
      if (!($col["human_label"] in ok)) print id ": human_label \"" $col["human_label"] "\" is not FLAG, PASS or UNKNOWN"
      if (!($col["model_label"] in ok)) print id ": model_label \"" $col["model_label"] "\" is not FLAG, PASS or UNKNOWN"
      if ($col["stratum"] == "") print id ": stratum is empty"
      if ($col["split"] != "tune" && $col["split"] != "holdout") print id ": split \"" $col["split"] "\" is not tune or holdout"
      n[$col["stratum"]]++; if ($col["split"] == "holdout") h[$col["stratum"]]++
    }
    END { for (s in n) if (3 * h[s] < n[s]) print s ": holdout " h[s] + 0 " of " n[s] " is under a third" }
  ' "$labels" | grep . && bad=1
  k="$(report "$labels" | awk '$1 == "kappa" && $2 == "user-model" && $3 == "all" { print $4 }')"
  awk -v k="$k" 'BEGIN { exit !(k != "NA" && k + 0 >= 0.6) }' || {
    echo "kappa user-model $k is below 0.6"
    bad=1
  }
  abs="$(cd "$(dirname "$labels")" && pwd -P)/${labels##*/}"
  top="$(git -C "${abs%/*}" rev-parse --show-toplevel 2>/dev/null)"
  [[ -n "$top" ]] && first="$(git -C "$top" log --format=%H -- "${abs#"$top"/}" 2>/dev/null | tail -n 1)"
  if [[ -z "${first:-}" ]]; then
    echo "labels.tsv has no commit, so the prompt freeze cannot be checked"
    bad=1
  else
    while read -r p; do
      git -C "$top" merge-base --is-ancestor "$p" "$first" && continue
      marked=0
      while read -r _ s; do
        [[ ${#s} -ge 7 && "$p" == "$s"* ]] && marked=1
      done < <(grep -E '^holdout-only: [0-9a-f]+$' "$top/$CALMD" 2>/dev/null)
      ((marked)) && continue
      echo "${p:0:12} changed the judge prompt after labels.tsv was first committed, and calibration.md has no 'holdout-only: <sha>' line for it"
      bad=1
    done < <(git -C "$top" log --format=%H -- "$PROMPT")
  fi
  return "$bad"
}

# arm <labels> <dir>: one judge pass over every case, one line per row:
# id, verdict, the ledger's model and effort, reason.
arm() {
  local labels="$1" dir="$2" fx id t target s n rows names lines info r tid test ord name kh o v hit
  while IFS= read -r fx; do
    t="$TMPD/repo"
    rm -rf "$t" "$DATA/verdicts"
    mkdir -p "$t"
    git -C "$t" init -q
    id="${fx##*/}" && id="${id%%.*}"
    for s in "$dir/cases/$id".*.fixture; do
      n="${s##*/}" && n="${n#*.}"
      cp "$s" "$t/${n%.fixture}"
    done
    target="${fx##*/}" && target="${target#*.}" && target="$t/${target%.fixture}"
    rows="$(awk -F'\t' -v f="$fx" 'NR == 1 { for (i = 1; i <= NF; i++) c[$i] = i; next }
      $c["file"] == f { print $c["id"] "\t" $c["test"] "\t" $c["note"] }' "$labels")"
    names="$(cut -f2 <<<"$rows" | sed -E 's/^(.*) #([0-9]+)$/\2 \1/; t; s/^/1 /' | jq -Rsc 'split("\n") | map(select(. != ""))')"
    lines="$(cut -f3 <<<"$rows" | sed -nE 's/.*changed ([0-9,-]+).*/\1/p' | head -n 1 | tr ',' '\n' |
      awk -F- 'NF { for (i = $1; i <= ($2 == "" ? $1 : $2); i++) print i }' | jq -sc .)"
    info="$(jq -cn --arg f "$target" --arg r "$t" --argjson names "$names" --argjson lines "$lines" \
      '{file: $f, repo: $r, whole: false, names: $names, base_ok: 0, lines: $lines, writers: [], owner: ""}')"
    judge::derive "$info"
    [[ -z "$KEYS" ]] || judge::run "$info" "$KEYS" "$JUDGE_RUN_TIMEOUT" "$HINT"
    while IFS=$'\t' read -r tid test _; do
      ord=1 name="$test"
      [[ "$test" =~ ^(.*)\ \#([0-9]+)$ ]] && name="${BASH_REMATCH[1]}" ord="${BASH_REMATCH[2]}"
      hit=""
      while read -r kh o _ r; do
        [[ "$o" == "$ord" && "$r" == "$name" && -f "$DATA/verdicts/$PKEY/$SID/$kh.json" ]] && hit="$kh"
      done <<<"$KEYS"
      if [[ -z "$hit" ]]; then
        printf '%s\tUNKNOWN\t-\t-\tno verdict for this block\n' "$tid"
        continue
      fi
      v="$(judge::validate "$DATA/verdicts/$PKEY/$SID/$hit.json")"
      jq -r --arg id "$tid" '[$id, .verdict, .model, .effort, (.reason // "" | gsub("[\t\n]"; " "))] | @tsv' <<<"$v"
    done <<<"$rows"
  done < <(awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) c[$i] = i; next } !seen[$c["file"]]++ { print $c["file"] }' "$1")
}

sweep() {
  local labels="$1" dir swdir m e cost bad=0
  dir="$(cd "$(dirname "$labels")" && pwd -P)"
  swdir="$dir/sweep"
  TMPD="$(mktemp -d)" || return 2
  trap 'rm -rf "$TMPD"' EXIT
  mkdir -p "$swdir" "$TMPD/data"
  HOOK_DIR="$(cd "$HOOKS" && pwd -P)" DATA="$TMPD/data" PKEY=calibration SID=sweep TPATH="$TMPD/none.jsonl"
  # shellcheck source=../../../../hooks/scanner-run.sh
  source "$HOOK_DIR/scanner-run.sh"
  # shellcheck source=../../../../hooks/judge-lib.sh
  source "$HOOK_DIR/judge-lib.sh"
  export CAL_JUDGE_INNER="${TEST_JUDGE_CMD:-claude}" CAL_COST_LOG
  TEST_JUDGE_CMD="$SELF"
  printf '| model | effort | holdout FLAG precision [95%% CI] | holdout FLAG recall [95%% CI] | UNKNOWN rate | cost per case |\n'
  printf '|---|---|---|---|---|---|\n'
  for m in haiku sonnet opus; do
    for e in low medium; do
      CLAUDE_PLUGIN_OPTION_TEST_JUDGE_MODEL="$m" CLAUDE_PLUGIN_OPTION_TEST_JUDGE_EFFORT="$e"
      CAL_COST_LOG="$TMPD/cost-$m-$e"
      : >"$CAL_COST_LOG"
      arm "$labels" "$dir" >"$swdir/$m-$e.tsv"
      awk -F'\t' -v m="$m" -v e="$e" '$3 != "-" && ($3 != m || $4 != e) { print $1 ": the judge ran as " $3 " " $4 ", not " m " " e > "/dev/stderr"; bad = 1 } END { exit bad }' "$swdir/$m-$e.tsv" || bad=1
      cost="$(awk '{ s += $1 } END { printf "%.6f", s }' "$CAL_COST_LOG")"
      awk "$AWK_LIB"'
        FNR == 1 && NR == 1 { for (i = 1; i <= NF; i++) col[$i] = i; next }
        NR == FNR { adj[$col["id"]] = $col["adjudicated_label"]; ho[$col["id"]] = $col["split"] == "holdout"; next }
        {
          rows++; if ($2 == "UNKNOWN") unk++
          if (!ho[$1] || adj[$1] == "") next
          if ($2 == "FLAG") { jf++; if (adj[$1] == "FLAG") tp++ }
          if (adj[$1] == "FLAG") af++
        }
        END {
          printf "| %s | %s | %s | %s | %s | $%.4f |\n", m, e, wilson(tp, jf), wilson(tp, af),
            (rows ? sprintf("%.4f (%d/%d)", unk / rows, unk, rows) : "NA (0/0)"), (rows ? cost / rows : 0)
        }' m="$m" e="$e" cost="$cost" "$labels" "$swdir/$m-$e.tsv"
    done
  done
  return "$bad"
}

mode=report
case "${1:-}" in
--check | --sweep) mode="${1#--}" && shift ;;
-h | --help)
  sed -n '2,/^set -uo/p' "$SELF" | sed '$d; s/^# \{0,1\}//'
  exit 0
  ;;
*) ;;
esac
labels="${1:-${SELF%/*}/labels.tsv}"
[[ -f "$labels" ]] || {
  echo "metrics.sh: no labels file at $labels" >&2
  exit 2
}
"$mode" "$labels"
