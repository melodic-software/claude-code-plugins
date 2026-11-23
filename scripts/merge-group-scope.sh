#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)" || exit 2
SECONDS_LIST="$ROOT/scripts/suite-seconds.txt"
WHOLE_TREE_JOBS=("Lint Repo" "Lint Shell" "Check Plugins" "Check Catalog" "Check Skills" "Check Managed Files")
LANES=(bash python node)

usage() {
  cat >&2 <<'EOF'
Log what a narrower merge-group run would skip, and skip nothing: the dark
launch of the merge-queue scope rule. Select Tests runs it in a merge group
after the lane plan; nothing reads what it prints, so no job's work changes.

  scripts/merge-group-scope.sh --pull FILE --statuses FILE --group-base SHA
      --pr-plan FILE [--summary FILE] [--planner CMD] [--repo DIR]

  --pull        the queued pull request as GitHub returns it (its head.sha)
  --statuses    the head's commit statuses, newest first, as GitHub returns them
  --group-base  merge_group.base_sha
  --pr-plan     the key=value plan scripts/plan-test-lanes.sh made for this group
  --summary     a file to append the markdown table to ($GITHUB_STEP_SUMMARY)
  --planner     the lane planner to run over X (default scripts/plan-test-lanes.sh)
  --repo        the checkout of the group commit (default this script's repository)

THE RULE. The pull request's green full run tested M, its head merged onto
main as main stood then; Mark Lanes records M in the pending `ci-lanes`
marker of that run ("full run <id> in flight, testing <M>"). The group commit
(HEAD here) is the head merged onto the group base. X is the files M and HEAD
differ in: what main and the entries ahead changed since M.
  - A test unit (a bash or Python suite, a Node package) would run only when
    both the pull request's plan and the plan of X select it, sel(P) ∩ sel(X).
    The planner's own widening (a workflow change, a pin, an unmapped file)
    applies to X as to any diff.
  - Lint Repo, Lint Shell, Check Plugins, Check Catalog, Check Skills and
    Check Managed Files would skip only when X is empty: the group tree is the
    tree the pull request run proved.
  - Test Selection, Select Tests and CI Status always run.
Any missing or inconsistent input is a fallback to today's plan: would-skip=0.

OUTPUT. One line on stdout, the parseable record of the run:
  mq-scope: would-run=<units> would-skip=<units> whole-tree-would-skip=<jobs>
    tree-identical=<true|false|unknown> x-files=<n|unknown>
    est-job-min-saved=<minutes> fallback=<reason|none>
est-job-min-saved sums scripts/suite-seconds.txt over the units that would
skip (an unlisted unit counts 5 s, the planner's floor), so it leaves out leg
setup and the whole-tree jobs. A fallback also prints
"fallback: today's plan (<reason>)" on stderr.

Exit: 0 once the arguments parse, a fallback included; 2 usage.
EOF
  exit 2
}

pull="" statuses="" group_base="" pr_plan="" summary="" planner="$ROOT/scripts/plan-test-lanes.sh" repo="$ROOT"
while (($# > 0)); do
  [[ $# -ge 2 ]] || usage
  case "$1" in
  --pull) pull="$2" ;;
  --statuses) statuses="$2" ;;
  --group-base) group_base="$2" ;;
  --pr-plan) pr_plan="$2" ;;
  --summary) summary="$2" ;;
  --planner) planner="$2" ;;
  --repo) repo="$2" ;;
  *) usage ;;
  esac
  shift 2
done
[[ -n "$pull" && -n "$statuses" && -n "$group_base" && -n "$pr_plan" ]] || usage

WORK="$(mktemp -d)" || exit 2
trap 'rm -rf "$WORK"' EXIT

units() {
  sed -n "s/^$2_plan=//p" "$1" | jq -r '[.[]?[]?] | unique[]' 2>/dev/null
}

all_units() {
  local lane
  for lane in "${LANES[@]}"; do units "$1" "$lane" | sed "s/^/$lane /"; done
}

today_count=0
if [[ -s "$pr_plan" ]]; then
  all_units "$pr_plan" >"$WORK/p.txt"
  today_count=$(grep -c . "$WORK/p.txt")
fi

report() {
  local run="$1" skip="$2" whole="$3" identical="$4" xfiles="$5" minutes="$6" reason="$7"
  printf 'mq-scope: would-run=%s would-skip=%s whole-tree-would-skip=%s tree-identical=%s x-files=%s est-job-min-saved=%s fallback=%s\n' \
    "$run" "$skip" "$whole" "$identical" "$xfiles" "$minutes" "$reason"
  [[ -n "$summary" ]] || return 0
  {
    echo "### Merge-group scope (dark launch: nothing skipped)"
    echo
    if [[ "$reason" != none ]]; then
      echo "Fallback: today's plan (\`$reason\`)."
      echo
    fi
    echo "| Part | Today | Would run | Would skip |"
    echo "|---|---|---|---|"
    local lane p r
    for lane in "${LANES[@]}"; do
      p=$(grep -c "^$lane " "$WORK/p.txt" 2>/dev/null) || p=0
      r=$p
      [[ ! -f "$WORK/run.txt" ]] || r=$(grep -c "^$lane " "$WORK/run.txt") || r=0
      echo "| $lane units | $p | $r | $((p - r)) |"
    done
    echo "| whole-tree jobs | ${#WHOLE_TREE_JOBS[@]} | $((${#WHOLE_TREE_JOBS[@]} - whole)) | $whole |"
    echo
    echo "tree-identical=$identical, x-files=$xfiles, est-job-min-saved=$minutes"
    if [[ -s "$WORK/skip.txt" ]]; then
      echo
      echo "<details><summary>Units that would skip</summary>"
      echo
      # shellcheck disable=SC2016 # markdown code spans, not expansions
      sed 's/^\([a-z]*\) \(.*\)$/- \1: `\2`/' "$WORK/skip.txt"
      echo
      echo "</details>"
    fi
  } >>"$summary"
}

fallback() {
  echo "fallback: today's plan ($1)" >&2
  report "$today_count" 0 0 unknown unknown 0 "$1"
  exit 0
}

[[ -s "$pr_plan" ]] || fallback pr-plan-missing
[[ $group_base =~ ^[0-9a-f]{40}$ ]] || fallback group-base-invalid
head=$(jq -r '.head.sha // ""' "$pull" 2>/dev/null) || head=""
[[ $head =~ ^[0-9a-f]{40}$ ]] || fallback pull-unreadable
jq -e 'type == "array"' "$statuses" >/dev/null 2>&1 || fallback statuses-unreadable

found=$(jq -r '
  [.[] | select(.context == "ci-lanes" and .creator.login? == "github-actions[bot]")] as $s
  | ($s | max_by(.id)) as $n
  | if $n == null or $n.state != "success" then "no-green-pr-run"
    else first($s[] | select(.state == "pending" and .target_url == $n.target_url)
        | .description // "" | capture("testing (?<m>[0-9a-f]{40})$").m) // "no-tested-merge-recorded"
    end' "$statuses" 2>/dev/null) || found="statuses-unreadable"
[[ $found =~ ^[0-9a-f]{40}$ ]] || fallback "$found"
merge="$found"

GIT_NO_LAZY_FETCH=1 git -C "$repo" cat-file -e "$merge^{commit}" 2>/dev/null ||
  git -C "$repo" fetch --quiet --no-tags origin "$merge" 2>/dev/null ||
  fallback tested-merge-fetch-refused
[[ "$(git -C "$repo" rev-parse --verify --quiet "$merge^2")" == "$head" ]] || fallback tested-merge-not-of-head
tested_base=$(git -C "$repo" rev-parse --verify --quiet "$merge^1") || fallback tested-merge-no-parent
git -C "$repo" merge-base --is-ancestor "$tested_base" "$group_base" 2>/dev/null || fallback tested-base-not-ancestor

git -C "$repo" diff --no-renames --name-only "$merge" HEAD -- >"$WORK/x.txt" || fallback x-diff-failed
xfiles=$(grep -c . "$WORK/x.txt")

if ((xfiles == 0)); then
  : >"$WORK/run.txt"
  whole=${#WHOLE_TREE_JOBS[@]}
  identical=true
else
  mapfile -t x <"$WORK/x.txt"
  (cd "$repo" && "$planner" -- "${x[@]}") >"$WORK/x-plan.txt" 2>"$WORK/x-plan.err" || fallback x-plan-failed
  all_units "$WORK/x-plan.txt" >"$WORK/x-units.txt"
  comm -12 <(sort "$WORK/p.txt") <(sort "$WORK/x-units.txt") >"$WORK/run.txt"
  whole=0
  identical=false
fi
comm -23 <(sort "$WORK/p.txt") <(sort "$WORK/run.txt") >"$WORK/skip.txt"

run_count=$(grep -c . "$WORK/run.txt")
skip_count=$(grep -c . "$WORK/skip.txt")
minutes=$(awk 'NR == FNR { if ($0 !~ /^#/ && NF == 2) s[$1] = $2; next }
  { t += ($2 in s) ? s[$2] : 5 }
  END { printf "%.1f", t / 60 }' "$SECONDS_LIST" "$WORK/skip.txt")
report "$run_count" "$skip_count" "$whole" "$identical" "$xfiles" "$minutes" none
