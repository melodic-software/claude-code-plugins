#!/usr/bin/env bash
# metrics.sh: the task-end judge's calibration numbers, from labels.tsv, its
# columns read by header name (docs/specs/tautological-tests-judge/).
#
#   metrics.sh [labels.tsv]          per stratum, then pooled as "all", against
#                                    the user's labels (human_label, the ground
#                                    truth): Cohen's kappa of each model rater
#                                    (every other *_label column holding a
#                                    label) and of the judge, each with
#                                    coverage and raw
#                                    agreement, a rater under 0.6 pooled marked
#                                    failed; the judge's confusion matrix; FLAG
#                                    precision and recall with Wilson 95%
#                                    intervals; prevalence; the achieved FLAG
#                                    n; the judge on rows the user labeled
#                                    UNKNOWN
#   metrics.sh --check [labels.tsv]  exit 1 unless every row has a human_label,
#                                    a stratum, a split and a label from every
#                                    configured rater (one whose column is
#                                    non-empty on any row); holdout is at least
#                                    a third of each stratum; and every commit
#                                    to the judge prompt is an ancestor of the
#                                    first commit to labels.tsv, or
#                                    calibration.md carries a `holdout-only:
#                                    <sha>` line for it (its metrics are
#                                    re-measured on holdout only)
#   metrics.sh --sweep [labels.tsv]  run the judge over every row for 7 arms,
#                                    sonnet at low, medium, high and xhigh and
#                                    opus at low, medium and high, through
#                                    judge::run and judge::validate (what the
#                                    hooks relay); keep each arm's verdicts in
#                                    sweep/<model>-<effort>.tsv and each run's
#                                    cost and wall seconds in
#                                    sweep/<model>-<effort>.runs.tsv beside the
#                                    labels; then print --table
#   metrics.sh --table [labels.tsv]  the sweep table from the kept sweep/ files:
#                                    per arm accuracy, FLAG precision and recall
#                                    with Wilson intervals, coverage, cost per
#                                    row, wall time per run (median, p95 by
#                                    nearest rank) and per arm, and the exact
#                                    McNemar p against the most accurate arm;
#                                    then the chosen arm and the fallback
#   metrics.sh --rerun <model> <effort> [labels.tsv]
#                                    two more runs of a swept arm over every
#                                    row (sweep/<model>-<effort>.rerun<n>.tsv);
#                                    prints the share of rows whose verdict
#                                    differs between any two of the three runs
#
# Labels are FLAG, PASS or UNKNOWN. A judge or rater UNKNOWN on a row the user
# labeled FLAG or PASS is an abstention: left out of kappa, precision and
# recall, and counted against coverage, whose denominator is the rows the user
# labeled FLAG or PASS. On a row the user labeled UNKNOWN, a judge UNKNOWN is
# correct and a FLAG or PASS is over-reach; a FLAG there counts against FLAG
# precision. Kappa is three-class over the rows where neither side abstained,
# and prints NA when no row qualifies or chance agreement is 1. Intervals use
# z = 1.959964 and print to 4 decimals.
#
# Selection: a verdict is correct when it equals the user's label, so an
# UNKNOWN on a FLAG or PASS row is wrong. Arms whose two-sided exact McNemar
# test (binomial on the discordant rows) against the most accurate arm is not
# significant at 0.05 tie with it; among tied arms sonnet wins, then the lower
# p95 wall time per run, then the lower cost per row. The fallback is the best
# arm of the other class by the same rule, tested against that class's most
# accurate arm. Ties for most accurate break the same way.
#
# A case is a directory cases/<id>/ holding the test file and the code it
# tests, each at its repository path plus `.fixture`. The sweep copies that
# directory, suffixes stripped, into an empty temporary repository, so the
# judge can read the code under test and sees no id, label or other case.
# TEST_JUDGE_CMD (the hooks' seam) replaces `claude`.
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
ARMS="sonnet-low sonnet-medium sonnet-high sonnet-xhigh opus-low opus-medium opus-high"

# FNR == 1 of the labels: col[] by header name, R[1..nr] the rater columns;
# need() exits 2 naming a missing column.
# shellcheck disable=SC2016 # an awk program
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
function share(x, t) { return t ? sprintf("%.4f (%d/%d)", x / t, x, t) : "NA (0/0)" }
function header(names,   i, k, n) {
  for (i = 1; i <= NF; i++) { col[$i] = i; if ($i ~ /_label$/ && $i != "human_label") R[++nr] = $i }
  n = split(names, k, " ")
  for (i = 1; i <= n; i++) if (!(k[i] in col)) { print "metrics.sh: no " k[i] " column in " FILENAME > "/dev/stderr"; BAD = 2; exit 2 }
}
BEGIN { FS = "\t"; Z = 1.959964; split("FLAG PASS UNKNOWN", L, " ") }
'

report() {
  awk "$AWK_LIB"'
    NR == 1 { header("id human_label judge_verdict stratum"); next }
    {
      s = $col["stratum"]
      if (!(s in seen)) { seen[s] = 1; order[++ns] = s }
      add(s); add("all")
    }
    function add(g,   h, j, r) {
      n[g]++
      h = $col["human_label"]; j = $col["judge_verdict"]
      for (r = 1; r <= nr; r++) { pair(g, "user-" rater(r), h, $col[R[r]]); if ($col[R[r]] != "") rated[r] = 1 }
      pair(g, "judge-user", h, j)
      if (j != "" && h != "") cm[g, j, h]++
      if (h != "") { nh[g]++; if (h == "FLAG") pf[g]++ }
      if (h == "UNKNOWN") { hu[g]++; if (j == "UNKNOWN") ok[g]++; if (j == "FLAG" || j == "PASS") over[g]++ }
      if (h == "FLAG" && (j == "FLAG" || j == "PASS")) rd[g]++
    }
    function rater(r,   x) { x = R[r]; sub(/_label$/, "", x); return x }
    # pair: the user u against another label x; x UNKNOWN on a user FLAG or
    # PASS row is an abstention, counted against coverage only.
    function pair(g, k, u, x) {
      if (u == "" || x == "") return
      if (u != "UNKNOWN") { cd[g, k]++; if (x == "UNKNOWN") return; cv[g, k]++ }
      cnt[g, k]++; if (u == x) po[g, k]++
      pu[g, k, u]++; px[g, k, x]++
    }
    function kappa(g, k,   t, e, i, o) {
      t = cnt[g, k]
      if (!t) return "NA"
      o = po[g, k] / t; e = 0
      for (i = 1; i <= 3; i++) e += pu[g, k, L[i]] * px[g, k, L[i]]
      e /= t * t
      if (e >= 1) return "NA"
      return sprintf("%.4f", (o - e) / (1 - e))
    }
    function kline(g, k,   v) {
      v = kappa(g, k)
      printf "kappa %s in %s %s (n=%d) coverage %s agreement %s", k, g, v, cnt[g, k], share(cv[g, k], cd[g, k]), share(po[g, k], cnt[g, k])
      if (g == "all" && k != "judge-user" && v != "NA" && v + 0 < 0.6) printf " failed"
      printf "\n"
    }
    function show(g,   r, i, j, tp, jf) {
      print "stratum " g " n=" n[g]
      for (r = 1; r <= nr; r++) if (rated[r]) kline(g, "user-" rater(r))
      kline(g, "judge-user")
      for (i = 1; i <= 3; i++) {
        printf "confusion %s judge=%s", g, L[i]
        for (j = 1; j <= 3; j++) printf " %s=%d", L[j], cm[g, L[i], L[j]]
        printf "\n"
      }
      tp = cm[g, "FLAG", "FLAG"]; jf = 0
      for (j = 1; j <= 3; j++) jf += cm[g, "FLAG", L[j]]
      print "flag-precision " g " " wilson(tp, jf)
      print "flag-recall " g " " wilson(tp, rd[g])
      print "prevalence " g " " share(pf[g], nh[g])
      print "flag-n " g " " pf[g] + 0
      print "unknown " g " user=" hu[g] + 0 " correct=" ok[g] + 0 " over-reach=" over[g] + 0
    }
    END { if (BAD) exit BAD; for (i = 1; i <= ns; i++) show(order[i]); show("all") }
  ' "$1"
}

check() {
  local labels="$1" bad=0 top abs first p s marked out
  out="$(awk "$AWK_LIB"'
    BEGIN { ok["FLAG"] = ok["PASS"] = ok["UNKNOWN"] = 1 }
    NR == 1 { header("id human_label stratum split"); next }
    {
      id[NR] = $col["id"]; h[NR] = $col["human_label"]; st[NR] = $col["stratum"]; sp[NR] = $col["split"]
      for (r = 1; r <= nr; r++) { v[NR, r] = $col[R[r]]; if (v[NR, r] != "") conf[r] = 1 }
      n[st[NR]]++; if (sp[NR] == "holdout") ho[st[NR]]++
    }
    END {
      if (BAD) exit BAD
      for (i = 2; i <= NR; i++) {
        if (!(h[i] in ok)) print id[i] ": human_label \"" h[i] "\" is not FLAG, PASS or UNKNOWN"
        for (r = 1; r <= nr; r++) if (conf[r] && !(v[i, r] in ok)) print id[i] ": " R[r] " \"" v[i, r] "\" is not FLAG, PASS or UNKNOWN"
        if (st[i] == "") print id[i] ": stratum is empty"
        if (sp[i] != "tune" && sp[i] != "holdout") print id[i] ": split \"" sp[i] "\" is not tune or holdout"
      }
      for (s in n) if (3 * ho[s] < n[s]) print s ": holdout " ho[s] + 0 " of " n[s] " is under a third"
    }
  ' "$labels")" || return 2
  [[ -n "$out" ]] && printf '%s\n' "$out" && bad=1
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

now() {
  local t="${EPOCHREALTIME:-$(date +%s)}"
  printf '%s' "${t/,/.}"
}

# arm <labels> <dir> <runs file>: one judge pass over every case, one line
# per row: id, verdict, the ledger's model and effort, reason. Appends each
# run's cost and wall seconds to <runs file>.
arm() {
  local labels="$1" dir="$2" runs="$3" fx id t target s n rows names lines info r tid test ord name kh o hit t0
  # fd 3: the judge and scanner children inherit stdin and may read it.
  while IFS= read -r fx <&3; do
    t="$TMPD/repo"
    rm -rf "${t:?}" "$DATA/verdicts"
    mkdir -p "$t"
    git -C "$t" init -q
    id="${fx#cases/}" && id="${id%%/*}"
    while IFS= read -r -d '' s; do
      n="${s#"$dir/cases/$id/"}" && n="${n%.fixture}"
      mkdir -p "$(dirname "$t/$n")" && cp "$s" "$t/$n"
    done < <(find "$dir/cases/$id" -type f -name '*.fixture' -print0)
    target="${fx#cases/"$id"/}" && target="$t/${target%.fixture}"
    rows="$(awk -F'\t' -v f="$fx" 'NR == 1 { for (i = 1; i <= NF; i++) c[$i] = i; next }
      $c["file"] == f { print $c["id"] "\t" $c["test"] "\t" $c["note"] }' "$labels")"
    names="$(cut -f2 <<<"$rows" | sed -E 's/^(.*) #([0-9]+)$/\2 \1/; t; s/^/1 /' | jq -Rsc 'split("\n") | map(select(. != ""))')"
    lines="$(cut -f3 <<<"$rows" | sed -nE 's/.*changed ([0-9,-]+).*/\1/p' | head -n 1 | tr ',' '\n' |
      awk -F- 'NF { for (i = $1; i <= ($2 == "" ? $1 : $2); i++) print i }' | jq -sc .)"
    info="$(jq -cn --arg f "$target" --arg r "$t" --argjson names "$names" --argjson lines "$lines" \
      '{file: $f, repo: $r, whole: false, names: $names, base_ok: 0, lines: $lines, writers: [], owner: ""}')"
    git -C "$t" add -A && git -C "$t" -c user.name=calibration -c user.email=calibration@localhost commit -qm case
    judge::derive "$info"
    if [[ -n "$KEYS" ]] && judge::reserve_run; then
      : >"$CAL_COST_LOG"
      t0="$(now)"
      judge::run "$info" "$KEYS" "$JUDGE_RUN_TIMEOUT" "$HINT" "$RUNRES"
      awk -v t0="$t0" -v t1="$(now)" '{ s += $1 } END { printf "%.6f\t%.3f\n", s, t1 - t0 }' "$CAL_COST_LOG" >>"$runs"
    fi
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
      judge::relay_reset
      judge::validate "$DATA/verdicts/$PKEY/$SID/$hit.json" "$target"
      jq -r --arg id "$tid" '[$id, .verdict, .model, .effort, (.reason // "" | gsub("[\t\n]"; " "))] | @tsv' <<<"$RELAY"
    done <<<"$rows"
  done 3< <(awk -F'\t' 'NR == 1 { for (i = 1; i <= NF; i++) c[$i] = i; next } !seen[$c["file"]]++ { print $c["file"] }' "$labels")
}

# judge_env: the hooks' judge library, pointed at a scratch data directory.
judge_env() {
  TMPD="$(mktemp -d)" || return 2
  trap 'rm -rf "${TMPD:?}"' EXIT
  mkdir -p "$TMPD/data"
  HOOK_DIR="$(cd "$HOOKS" && pwd -P)" DATA="$TMPD/data" PKEY=calibration SID=sweep TPATH="$TMPD/none.jsonl"
  # shellcheck source=../../../../hooks/scanner-run.sh
  source "$HOOK_DIR/scanner-run.sh"
  # shellcheck source=../../../../hooks/judge-lib.sh
  source "$HOOK_DIR/judge-lib.sh"
  # No session limit on calibration runs: every case gets its reservation.
  unset CLAUDE_PLUGIN_OPTION_TEST_JUDGE_SESSION_RUNS
  export CAL_JUDGE_INNER="${TEST_JUDGE_CMD:-claude}" CAL_COST_LOG="$TMPD/cost"
  TEST_JUDGE_CMD="$SELF"
}

# run_arm <labels> <model> <effort> <name>: sweep/<name>.tsv and .runs.tsv;
# false when a verdict came from another model or effort.
run_arm() {
  local labels="$1" m="$2" e="$3" swdir
  swdir="$(cd "$(dirname "$labels")" && pwd -P)/sweep"
  mkdir -p "$swdir"
  CLAUDE_PLUGIN_OPTION_TEST_JUDGE_MODEL="$m" CLAUDE_PLUGIN_OPTION_TEST_JUDGE_EFFORT="$e"
  : >"$swdir/$4.runs.tsv"
  arm "$labels" "${swdir%/*}" "$swdir/$4.runs.tsv" >"$swdir/$4.tsv"
  awk -F'\t' -v m="$m" -v e="$e" '$3 != "-" && ($3 != m || $4 != e) { print $1 ": the judge ran as " $3 " " $4 ", not " m " " e > "/dev/stderr"; bad = 1 } END { exit bad }' "$swdir/$4.tsv"
}

sweep() {
  local labels="$1" a bad=0
  judge_env || return 2
  for a in $ARMS; do run_arm "$labels" "${a%-*}" "${a#*-}" "$a" || bad=1; done
  table "$labels" || bad=1
  return "$bad"
}

rerun() {
  local m="$1" e="$2" labels="$3" swdir i bad=0
  swdir="$(cd "$(dirname "$labels")" && pwd -P)/sweep"
  [[ -f "$swdir/$m-$e.tsv" ]] || {
    echo "metrics.sh: no sweep/$m-$e.tsv to compare with; run --sweep first" >&2
    return 2
  }
  judge_env || return 2
  for i in 1 2; do run_arm "$labels" "$m" "$e" "$m-$e.rerun$i" || bad=1; done
  printf '| run | model | effort | rows whose verdict changed |\n|---|---|---|---|\n'
  awk -F'\t' -v m="$m" -v e="$e" '
    FNR == 1 { k++ }
    { v[k, $1] = $2; if (k == 1) id[++n] = $1 }
    END {
      for (i = 1; i <= n; i++) if (v[1, id[i]] != v[2, id[i]] || v[1, id[i]] != v[3, id[i]]) c++
      printf "| rerun | %s | %s | %s |\n", m, e, (n ? sprintf("%.4f (%d/%d)", c / n, c, n) : "NA (0/0)")
    }' "$swdir/$m-$e.tsv" "$swdir/$m-$e.rerun1.tsv" "$swdir/$m-$e.rerun2.tsv"
  return "$bad"
}

table() {
  local labels="$1" swdir a files=()
  swdir="$(cd "$(dirname "$labels")" && pwd -P)/sweep"
  for a in $ARMS; do
    [[ -f "$swdir/$a.tsv" ]] && files+=("$swdir/$a.tsv") && [[ -f "$swdir/$a.runs.tsv" ]] && files+=("$swdir/$a.runs.tsv")
  done
  printf '| model | effort | accuracy | FLAG precision [95%% CI] | FLAG recall [95%% CI] | coverage | cost per row | wall per run, median | wall per run, p95 | wall per arm | McNemar p vs most accurate |\n'
  printf '|---|---|---|---|---|---|---|---|---|---|---|\n'
  awk "$AWK_LIB"'
    FNR == 1 && NR == 1 { header("id human_label"); next }
    NR == FNR { if ($col["human_label"] != "") { h[$col["id"]] = $col["human_label"]; ids[++nl] = $col["id"] }; next }
    FNR == 1 { a = FILENAME; sub(/^.*\//, "", a); runs = sub(/\.runs\.tsv$/, "", a); sub(/\.tsv$/, "", a); if (!runs) arms[++na] = a }
    runs { cost[a] += $1; w[a, ++nw[a]] = $2; tw[a] += $2; next }
    { v[a, $1] = $2 }
    function mcnemar(x, y,   i, b, c, n, m, k, t, s) {
      for (i = 1; i <= nl; i++) {
        if (ok[x, ids[i]] && !ok[y, ids[i]]) b++
        if (!ok[x, ids[i]] && ok[y, ids[i]]) c++
      }
      n = b + c; m = b < c ? b : c
      if (!n) return 1
      t = 1; for (k = 1; k <= n; k++) t /= 2
      for (k = 0; k <= m; k++) { s += t; t = t * (n - k) / (k + 1) }
      return 2 * s > 1 ? 1 : 2 * s
    }
    # better: x beats y on accuracy (when acc is set), then sonnet, then
    # p95 wall, then cost.
    function better(x, y, acc) {
      if (y == "") return 1
      if (acc && right[x] != right[y]) return right[x] > right[y]
      if ((cls[x] == "sonnet") != (cls[y] == "sonnet")) return cls[x] == "sonnet"
      if (p95[x] != p95[y]) return p95[x] < p95[y]
      return cpr[x] < cpr[y]
    }
    # pick: the best arm of class c ("" for any): the most accurate, then the
    # best of those whose McNemar test against it is not significant.
    function pick(c,   i, top, best) {
      for (i = 1; i <= na; i++) if ((c == "" || cls[arms[i]] == c) && better(arms[i], top, 1)) top = arms[i]
      for (i = 1; i <= na; i++) if ((c == "" || cls[arms[i]] == c) && mcnemar(arms[i], top) >= 0.05 && better(arms[i], best, 0)) best = arms[i]
      return best
    }
    END {
      if (BAD) exit BAD
      for (i = 1; i <= na; i++) {
        a = arms[i]; cls[a] = a; sub(/-.*/, "", cls[a]); eff[a] = a; sub(/^[^-]*-/, "", eff[a])
        for (j = 1; j <= nl; j++) {
          id = ids[j]; x = v[a, id]; y = h[id]
          ok[a, id] = x == y; right[a] += x == y
          if (x == "FLAG") { jf[a]++; if (y == "FLAG") tp[a]++ }
          if (y == "FLAG" && (x == "FLAG" || x == "PASS")) rd[a]++
          if (y == "FLAG" || y == "PASS") { cd[a]++; if (x == "FLAG" || x == "PASS") cv[a]++ }
        }
        # Walls sorted (insertion sort: any awk), median and nearest-rank p95.
        n = nw[a]
        for (j = 2; j <= n; j++) { t = w[a, j]; for (k = j - 1; k >= 1 && w[a, k] + 0 > t + 0; k--) w[a, k + 1] = w[a, k]; w[a, k + 1] = t }
        med[a] = !n ? 0 : n % 2 ? w[a, (n + 1) / 2] : (w[a, n / 2] + w[a, n / 2 + 1]) / 2
        p95[a] = n ? w[a, int((95 * n + 99) / 100)] : 0
        cpr[a] = nl ? cost[a] / nl : 0
      }
      top = ""
      for (i = 1; i <= na; i++) if (better(arms[i], top, 1)) top = arms[i]
      for (i = 1; i <= na; i++) {
        a = arms[i]
        printf "| %s | %s | %s | %s | %s | %s | $%.4f | %.1f s | %.1f s | %.1f s | %.4f |\n", cls[a], eff[a], share(right[a], nl),
          wilson(tp[a], jf[a]), wilson(tp[a], rd[a]), share(cv[a], cd[a]), cpr[a], med[a], p95[a], tw[a], mcnemar(a, top)
      }
      if (!na) { print "chosen: none (no sweep files)"; exit }
      c = pick(""); print ""; print "chosen: " cls[c] " " eff[c]
      f = pick(cls[c] == "sonnet" ? "opus" : "sonnet")
      print "fallback: " (f == "" ? "none" : cls[f] " " eff[f])
    }
  ' "$labels" "${files[@]}"
}

mode=report
case "${1:-}" in
--check | --sweep | --table) mode="${1#--}" && shift ;;
--rerun)
  [[ $# -ge 3 ]] || {
    echo "metrics.sh: --rerun <model> <effort> [labels.tsv]" >&2
    exit 2
  }
  mode=rerun m="$2" e="$3" && shift 3
  ;;
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
if [[ "$mode" == rerun ]]; then rerun "$m" "$e" "$labels"; else "$mode" "$labels"; fi
