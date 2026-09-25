#!/usr/bin/env bash
# Independent em-dash count for the /ai-slop:audit fix flow's closing step.
#
# Reads a `detect.sh --list-targets` file and finds, per file, the lines that
# hold an em dash outside fenced code, inline code, and ignore markers. The
# parse is written separately from detect.sh on purpose: a shared parser would
# share its blind spots. Given the detector's output, it prints a Disagree row
# for every file whose count or set of line numbers differs from the
# detector's rule-em-dash findings, naming the lines only one side holds.
#
# Output rows use the CrossCheck:/Disagree: prefixes, never Finding:.
# Exit: 0 on success; 2 on usage errors.
set -u
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/opt-value.sh
source "$SCRIPT_DIR/lib/opt-value.sh"
ME="cross-check.sh"

usage() {
  cat <<'EOF'
cross-check.sh: count em-dash lines per file independently of detect.sh.

Usage:
  cross-check.sh --targets <list-targets file> [--detector <detector output file>]

Exit: 0 on success, 2 on usage errors.
EOF
}

TARGETS_FILE=""
DETECTOR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
  --targets) require_opt_value "$ME" "$@"; TARGETS_FILE="$2"; shift 2 ;;
  --detector) require_opt_value "$ME" "$@"; DETECTOR="$2"; shift 2 ;;
  --help | -h) usage; exit 0 ;;
  *) echo "$ME: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done
[[ -n "$TARGETS_FILE" ]] || { usage >&2; exit 2; }
[[ -r "$TARGETS_FILE" ]] || { echo "$ME: cannot read --targets: $TARGETS_FILE" >&2; exit 2; }
[[ -z "$DETECTOR" || -r "$DETECTOR" ]] || { echo "$ME: cannot read --detector: $DETECTOR" >&2; exit 2; }

# The detector's effective config decides whether the rule ran and where.
config="$(bash "$SCRIPT_DIR/detect.sh" --show-config 2>/dev/null | tr -d '\r')"
disabled="$(sed -n 's/^Effective: disabled_rules=//p' <<<"$config")"
case " $disabled " in
*" rule-em-dash "*)
  echo "CrossCheck: comparison skipped: rule-em-dash disabled"
  exit 0
  ;;
*) ;;
esac
allowed=()
read -r -a allowed <<<"$(sed -n 's/^Effective: rule_allowed_paths\[rule-em-dash\]=//p' <<<"$config")"

is_allowed() {
  local g
  for g in ${allowed[@]+"${allowed[@]}"}; do
    # shellcheck disable=SC2053
    [[ $1 == $g || $2 == $g ]] && return 0
  done
  return 1
}

keys=()
paths=()
while IFS=$'\t' read -r key path; do
  key="${key%$'\r'}"
  path="${path%$'\r'}"
  [[ -n "$key" ]] || continue
  keys+=("$key")
  paths+=("${path:-$key}")
done <"$TARGETS_FILE"

# One awk pass over every file. A fence opens on ``` or ~~~, optionally after a
# list marker, and closes on its own character. Inline code spans are removed
# before a line marker is looked for, so a backticked marker is prose.
# shellcheck disable=SC2016  # an awk program, not a shell expansion
count_prog='
  function fchar(s) {
    if (substr(s, 1, 3) == "```") return "`"
    if (substr(s, 1, 3) == "~~~") return "~"
    return ""
  }
  function done_file() { if (cur != "") printf "%s\t%d\t%s\n", cur, n, (ls == "" ? "-" : substr(ls, 2)) }
  BEGIN { em = "\342\200\224" }
  FNR == 1 { done_file(); cur = FILENAME; n = 0; ls = ""; fence = ""; fcol = 0; block = 0 }
  { line = $0; sub(/\r$/, "", line) }
  line ~ /^[ \t]*<!-- ai-slop-ignore-file(:[^>]*)? -->[ \t]*$/ { n = 0; ls = ""; nextfile }
  {
    # CommonMark fence rules as detect.sh applies them: indentation counts
    # spaces only; an opener sits at most three spaces in, optionally after a
    # bullet or an ordinal of up to nine digits and one to four spaces; a closer
    # sits at most three spaces past the opener column.
    t = line
    sub(/^ +/, "", t)
    ind = length(line) - length(t)
    # A fence opened inside a list item ends with the item: a non-blank line
    # indented less than the item content column.
    if (fence != "" && fcol > 0 && t != "" && ind < fcol) fence = ""
    if (fence != "") {
      if (fchar(t) == fence && ind <= fcol + 3) fence = ""
      next
    }
    c = ""
    if (ind <= 3) {
      c = fchar(t)
      fcol = 0
      if (c == "" && match(t, /^([-*+]|[0-9]+[.)])/) && RLENGTH <= 10) {
        m = RLENGTH
        sp = 0
        while (substr(t, m + sp + 1, 1) == " ") sp++
        if (sp >= 1 && sp <= 4) {
          c = fchar(substr(t, m + sp + 1))
          if (c != "") fcol = ind + m + sp
        }
      }
    }
    if (c != "") { fence = c; next }
  }
  line ~ /^[ \t]*<!-- ai-slop-ignore-start(:[^>]*)? -->[ \t]*$/ { block = 1; next }
  line ~ /^[ \t]*<!-- ai-slop-ignore-end(:[^>]*)? -->[ \t]*$/ { block = 0; next }
  block { next }
  {
    gsub(/`[^`]*`/, "", line)
    if (line ~ /<!-- ai-slop-ignore(:[^>]*)? -->/) next
    if (index(line, em)) { n++; ls = ls "," FNR }
  }
  END { done_file() }'

declare -A skip=() count=() xlines=()
scan=()
for i in "${!keys[@]}"; do
  if is_allowed "${keys[$i]}" "${paths[$i]}"; then
    skip[$i]=rule-allowed
  elif [[ -r "${paths[$i]}" ]]; then
    scan+=("${paths[$i]}")
  else
    skip[$i]=unreadable
  fi
done
if [[ "${#scan[@]}" -gt 0 ]]; then
  while IFS=$'\t' read -r p c l; do
    count[$p]="$c"
    xlines[$p]="$l"
  done < <(awk "$count_prog" "${scan[@]}")
fi

# Per file: the detector's row count and its set of line numbers, ascending.
# The file and line come from the leftmost ` line=N fired=`, so an excerpt
# holding that text changes neither.
declare -A det=() dlines=() declined=()
if [[ -n "$DETECTOR" ]]; then
  while IFS=$'\t' read -r kind l k; do
    if [[ "$kind" == D ]]; then
      declined[$k]=1
    else
      det[$k]="$kind"
      dlines[$k]="$l"
    fi
  done < <(tr -d '\r' <"$DETECTOR" | awk '
    /^Finding: rule=ai-slop\/audit\/rule-em-dash file=/ {
      s = $0
      sub(/^Finding: rule=ai-slop\/audit\/rule-em-dash file=/, "", s)
      if (match(s, / line=[0-9]+ fired=/)) {
        n = substr(s, RSTART + 6, RLENGTH - 13) + 0
        s = substr(s, 1, RSTART - 1)
        if (!((s, n) in seen)) { seen[s, n] = 1; m[s]++; v[s, m[s]] = n }
      }
      c[s]++
    }
    /^Declined: file=/ {
      s = $0
      sub(/^Declined: file=/, "", s)
      sub(/ cause=[^ ]*$/, "", s)
      print "D\t-\t" s
    }
    END {
      for (k in c) {
        for (i = 2; i <= m[k]; i++) {
          x = v[k, i]
          for (j = i - 1; j >= 1 && v[k, j] > x; j--) v[k, j + 1] = v[k, j]
          v[k, j + 1] = x
        }
        out = ""
        for (i = 1; i <= m[k]; i++) out = out "," v[k, i]
        printf "%d\t%s\t%s\n", c[k], (out == "" ? "-" : substr(out, 2)), k
      }
    }')
fi

# only_lines <a> <b>: the lines only in a, then only in b, each a comma list
# or `-`. Both inputs are ascending, so each output is too.
only_lines() {
  awk -v a="$1" -v b="$2" 'BEGIN {
    na = split(a, A, ","); nb = split(b, B, ",")
    for (i = 1; i <= na; i++) inA[A[i]] = 1
    for (i = 1; i <= nb; i++) inB[B[i]] = 1
    for (i = 1; i <= na; i++) if (A[i] != "-" && !(A[i] in inB)) oa = oa "," A[i]
    for (i = 1; i <= nb; i++) if (B[i] != "-" && !(B[i] in inA)) ob = ob "," B[i]
    printf "detector_only=%s cross_check_only=%s\n", (oa == "" ? "-" : substr(oa, 2)), (ob == "" ? "-" : substr(ob, 2))
  }'
}

files=0
disagree=0
for i in "${!keys[@]}"; do
  key="${keys[$i]}"
  if [[ -n "${skip[$i]:-}" ]]; then
    echo "CrossCheck: file=$key skipped=${skip[$i]}"
    continue
  fi
  if [[ -n "${declined[$key]:-}" ]]; then
    echo "CrossCheck: file=$key skipped=declined"
    continue
  fi
  n="${count[${paths[$i]}]:-0}"
  xl="${xlines[${paths[$i]}]:--}"
  dl="${dlines[$key]:--}"
  files=$((files + 1))
  echo "CrossCheck: file=$key em_dash_lines=$n"
  if [[ -n "$DETECTOR" ]] && [[ "${det[$key]:-0}" -ne "$n" || "$dl" != "$xl" ]]; then
    echo "Disagree: file=$key detector=${det[$key]:-0} cross_check=$n $(only_lines "$dl" "$xl")"
    disagree=$((disagree + 1))
  fi
done
if [[ -n "$DETECTOR" ]]; then
  echo "CrossCheck total: files=$files disagreements=$disagree"
fi
exit 0
