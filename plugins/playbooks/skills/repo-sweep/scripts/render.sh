#!/usr/bin/env bash
# Render a repo-sweep plan (formats: ../SKILL.md "Formats").
#
#   render.sh --checklist <catalog> <selection-line> [<recommendations-tsv>]
#     The PR checklist block: the markers around one "- [ ] <id>: <skills>" line per
#     selected id, in selection order. Given the TSV, a "Not run:" section follows, one line
#     per unselected catalog entry in catalog order: "not applicable, <reason>" for a
#     not-applicable row, "not selected, recommended <rec>: <reason>" for any other row,
#     "not selected" for an entry the TSV lacks.
#   render.sh --page <catalog> <recommendations-tsv>
#     The selection page: the template with its one __REPO_SWEEP_DATA__ token replaced by
#     the JSON below. Template: $REPO_SWEEP_PAGE_TEMPLATE, default
#     ../../../reference/repo-sweep-plan-page.html from this script. The TSV must hold a
#     row for every catalog id.
#
# selection-line: "repo-sweep-selection: <id>,<id>,..." (the page's copy output).
# recommendations-tsv: id, recommendation (run|rerun|rerun-optional|not-applicable), reason:
# history.sh's output with the caller's not-applicable judgments applied.
# Page JSON, entries in catalog order:
#   {"playbook": "<catalog stem>", "entries": [{"id", "phase", "skills": [...], "args",
#    "issue", "appliesWhen", "recommendation", "reason", "checked"}]}
# checked is the catalog default, false on a not-applicable row. Every "<" is written as
# < so the data cannot close the <script> element holding it.
# Exit: 0 ok; 1 bad input (unknown or duplicate id, bad recommendation, missing TSV row,
# template missing or without exactly one token); 2 usage.
set -euo pipefail

dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
token=__REPO_SWEEP_DATA__
usage() {
  printf 'usage: render.sh --checklist <catalog> <selection-line> [<recommendations-tsv>]\n' >&2
  printf '       render.sh --page <catalog> <recommendations-tsv>\n' >&2
  exit 2
}
mode=${1-}
case $mode in
--checklist) (($# == 3 || $# == 4)) || usage ;;
--page) (($# == 3)) || usage ;;
*) usage ;;
esac
catalog=$2
recs=${4-}
[[ $mode == --page ]] && recs=$3
[[ -f $catalog && (-z $recs || -f $recs) ]] || usage
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
bash "$dir/catalog.sh" "$catalog" >"$tmp/rows"
playbook=$(basename "$catalog" .md)

if [[ -n $recs ]]; then
  tr -d '\r' <"$recs" | awk 'NF' >"$tmp/recs"
  awk -F'\t' -v all="$([[ $mode == --page ]] && echo 1)" '
    NR == FNR { ids[$1] = 1; next }
    function bad(msg) { printf "render.sh: %s\n", msg > "/dev/stderr"; err = 1 }
    !($1 in ids) { bad("unknown id in recommendations: " $1) }
    $2 !~ /^(run|rerun|rerun-optional|not-applicable)$/ { bad("bad recommendation for " $1 ": " $2) }
    $1 in seen { bad("duplicate recommendation row: " $1) }
    { seen[$1] = 1 }
    END { if (all) for (i in ids) if (!(i in seen)) bad("no recommendation row for " i); exit err }
  ' "$tmp/rows" "$tmp/recs"
fi

if [[ $mode == --checklist ]]; then
  line=$(printf '%s' "$3" | tr -d '\r')
  if [[ ! $line =~ ^[[:space:]]*repo-sweep-selection:(.*)$ ]]; then
    printf 'render.sh: selection line must start with repo-sweep-selection:\n' >&2
    exit 1
  fi
  awk -F'\t' -v sel="${BASH_REMATCH[1]}" -v pb="$playbook" -v recsf="${recs:+$tmp/recs}" '
    function bad(msg) { printf "render.sh: %s\n", msg > "/dev/stderr"; exit 1 }
    { skills[$1] = $3; order[++n] = $1 }
    END {
      m = split(sel, s, ",")
      for (i = 1; i <= m; i++) {
        gsub(/^[ \t]+|[ \t]+$/, "", s[i])
        if (s[i] == "") bad("empty id in selection")
        if (!(s[i] in skills)) bad("unknown id in selection: " s[i])
        if (s[i] in chosen) bad("duplicate id in selection: " s[i])
        chosen[s[i]] = 1
      }
      print "<!-- repo-sweep:begin playbook=" pb " -->"
      for (i = 1; i <= m; i++) print "- [ ] " s[i] ": " skills[s[i]]
      print "<!-- repo-sweep:end -->"
      if (recsf == "" || m == n) exit 0
      FS = "\t"
      while ((getline l < recsf) > 0) { split(l, f, "\t"); rec[f[1]] = f[2]; why[f[1]] = f[3] }
      print ""
      print "Not run:"
      for (i = 1; i <= n; i++) {
        id = order[i]
        if (id in chosen) continue
        if (!(id in rec)) print "- " id ": not selected"
        else if (rec[id] == "not-applicable") print "- " id ": not applicable, " why[id]
        else print "- " id ": not selected, recommended " rec[id] ": " why[id]
      }
    }' "$tmp/rows"
  exit 0
fi

template=${REPO_SWEEP_PAGE_TEMPLATE:-$dir/../../../reference/repo-sweep-plan-page.html}
if [[ ! -f $template ]]; then
  printf 'render.sh: page template not found: %s\n' "$template" >&2
  exit 1
fi
jq -nc --arg playbook "$playbook" --rawfile rows "$tmp/rows" --rawfile recs "$tmp/recs" '
  def tsv($s): $s | split("\n") | map(select(length > 0) | split("\t"));
  (tsv($recs) | map({key: .[0], value: {r: .[1], why: .[2]}}) | from_entries) as $R
  | {playbook: $playbook, entries: [tsv($rows)[] | {
      id: .[0], phase: .[1], skills: (.[2] | split(",") | map(gsub("^ +| +$"; ""))),
      args: .[3], issue: .[5], appliesWhen: .[6],
      recommendation: $R[.[0]].r, reason: $R[.[0]].why,
      checked: (.[4] == "true" and $R[.[0]].r != "not-applicable")}]}' |
  sed 's/</\\u003c/g' >"$tmp/json"
awk -v tok="$token" -v jf="$tmp/json" '
  BEGIN { getline json < jf }
  { out = ""; rest = $0
    while ((i = index(rest, tok)) > 0) { out = out substr(rest, 1, i - 1) json; rest = substr(rest, i + length(tok)); c++ }
    print out rest }
  END { exit c != 1 }' "$template" >"$tmp/page" || {
  printf 'render.sh: template must hold exactly one %s: %s\n' "$token" "$template" >&2
  exit 1
}
cat "$tmp/page"
