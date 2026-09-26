#!/usr/bin/env bash
# Find this repo's sweep PR and report where the sweep stands.
#
#   state.sh     run anywhere inside the repo; no arguments
#
# Sweep PR: on a chore/repo-sweep-* branch, that branch's PR (the open one, else the
# newest). On any other branch, the open PRs whose head branch starts with chore/repo-sweep-.
# Checklist grammar: ../SKILL.md "Formats"; body lines are
# read with \r stripped.
#
# Output, "key value" lines in this order, each only when it applies:
#   pr <number>
#   branch <head-branch>
#   pr-state OPEN|MERGED|CLOSED
#   playbook <name>
#   dirty yes|no           any change, tracked or untracked, outside .work/
#   untick-committed <id> <sha> <skill@version>...
#       a "[ ]", "[~]", or bare "[x]" line whose exact skill set carries Playbook-Step
#       trailers in one commit on the branch (after origin/<base>): tick it with tick.sh
#       committed <sha> <skill@version>..., do not rerun it
#   done-unverified <id>   a bare "[x]" line (no versions: ticked in the web UI) no trailer backs
#   next <id> in-progress|pending   the first "[~]" line, else the first "[ ]" line
#   sweep <number> <branch>         one per open sweep PR (exit 15 only)
# A done line is "[x]" ending ", committed <sha>" or ", no findings".
#
# Exit:
#   0  next step found; under an in-progress step a dirty tree means resume
#   1  error: no markers in the body; any other unlisted code is a failed gh, git, or jq
#   10 no sweep PR
#   11 the sweep PR is merged or closed
#   12 dirty tree and the next step is pending, not in progress
#   13 all steps done
#   14 one open sweep PR, on another branch: git fetch origin <branch>, git worktree add
#      <path> <branch>, rerun there
#   15 several open sweep PRs: listed, pick one
set -euo pipefail

prefix=chore/repo-sweep-
fields=number,state,headRefName,baseRefName,body
top=$(git rev-parse --show-toplevel)
cd "$top"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

branch=$(git symbolic-ref -q --short HEAD || true)
if [[ $branch == "$prefix"* ]]; then
  gh pr list --state all --head "$branch" --limit 1000 --json "$fields" >"$tmp/prs"
  jq '(map(select(.state == "OPEN")) + .)[0] // empty' "$tmp/prs" >"$tmp/pr"
else
  gh pr list --state open --search "head:$prefix" --limit 1000 --json "$fields" >"$tmp/prs"
  jq -r --arg p "$prefix" '.[] | select(.headRefName | startswith($p)) | "sweep \(.number) \(.headRefName)"' \
    "$tmp/prs" >"$tmp/open"
  case $(wc -l <"$tmp/open" | tr -d ' ') in
  0) exit 10 ;;
  1)
    read -r _ number head <"$tmp/open"
    printf 'pr %s\nbranch %s\npr-state OPEN\n' "$number" "$head"
    exit 14
    ;;
  *)
    cat "$tmp/open"
    exit 15
    ;;
  esac
fi
[[ -s $tmp/pr ]] || exit 10

jq -r '"pr \(.number)\nbranch \(.headRefName)\npr-state \(.state)"' "$tmp/pr"
[[ $(jq -r .state "$tmp/pr") == OPEN ]] || exit 11
jq -r .body "$tmp/pr" | tr -d '\r' | awk '
  /^<!-- repo-sweep:end -->/ { if (inb) exit; next }
  inb { print; next }
  match($0, /^<!-- repo-sweep:begin playbook=[^ ]+ -->/) { inb = 1; print }' >"$tmp/block"
if [[ ! -s $tmp/block ]]; then
  printf 'state.sh: no repo-sweep markers in the body of PR #%s\n' "$(jq -r .number "$tmp/pr")" >&2
  exit 1
fi
sed -n '1s/^<!-- repo-sweep:begin playbook=\([^ ]*\) -->.*/playbook \1/p' "$tmp/block"

dirty=no
[[ -n $(git status --porcelain -- ':/' ':(top,exclude).work') ]] && dirty=yes
printf 'dirty %s\n' "$dirty"

base=origin/$(jq -r .baseRefName "$tmp/pr")
range=$base..HEAD
if ! git rev-parse -q --verify "$base" >/dev/null; then
  printf 'state.sh: %s not found; reading trailers from all of HEAD\n' "$base" >&2
  range=HEAD
fi
git log --format='%h %(trailers:key=Playbook-Step,valueonly,separator=%x20)' "$range" >"$tmp/log"

awk -v logf="$tmp/log" '
  BEGIN {
    while ((getline l < logf) > 0) {
      k = split(l, t, " ")
      if (k < 2) continue
      nc++; sha[nc] = t[1]; vals[nc] = substr(l, length(t[1]) + 2); cnt[nc] = k - 1; names[nc] = " "
      for (j = 2; j <= k; j++) { sub(/@[^@]*$/, "", t[j]); names[nc] = names[nc] t[j] " " }
    }
  }
  NR > 1 && match($0, /^- \[[ ~xX]\] /) {
    mark = substr($0, 4, 1); rest = substr($0, 7); i = index(rest, ": ")
    if (!i) next
    id = substr(rest, 1, i - 1); tail = substr(rest, i + 2)
    if (mark ~ /[xX]/ && tail ~ /(, committed [0-9a-f]+|, no findings)$/) next
    n = split(tail, s, /, */)
    for (c = 1; c <= nc; c++) {
      if (cnt[c] != n) continue
      for (j = 1; j <= n; j++) { sk = s[j]; sub(/@[^@]*$/, "", sk); if (!index(names[c], " " sk " ")) break }
      if (j > n) break
    }
    if (c <= nc) { print "untick-committed " id " " sha[c] " " vals[c]; next }
    if (mark ~ /[xX]/) { print "done-unverified " id; next }
    if (mark == "~" && !prog) prog = id
    if (mark == " " && !pend) pend = id
  }
  END {
    if (prog) print "next " prog " in-progress"
    else if (pend) print "next " pend " pending"
  }' "$tmp/block" >"$tmp/out"
cat "$tmp/out"

next=$(grep '^next ' "$tmp/out" || true)
[[ -n $next ]] || exit 13
[[ $next == *" pending" && $dirty == yes ]] && exit 12
exit 0
