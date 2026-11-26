#!/usr/bin/env bash
# Exit: 0 with a merge-state; 1 on a failed precondition or git failure.
# shellcheck disable=SC2310  # g wraps one git call, so its status is that call's
set -euo pipefail

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_LITERAL_PATHSPECS=1
g() { git -c core.hooksPath=/dev/null -c core.fsmonitor= -c diff.external= "$@"; }
die() {
  printf 'prepare.sh: %s\n' "$*" >&2
  exit 1
}

TRAILER_VALUE=pr-unblock/resolve-conflicts
OID_RE='^([0-9a-f]{40}|[0-9a-f]{64})$'
PROTECTED_RE='^\.github/workflows/|(^|/)(\.gitmodules|settings[^/]*\.json)$'
PLUGIN_SETTINGS_RE='^plugins/(.*/)?settings[^/]*\.json$'
# shellcheck disable=SC2016  # an awk program, expanded by awk
MARKER_AWK='
  s == 0 && (/^<<<<<<<+$/ || /^<<<<<<<+ /) { s = 1; next }
  s == 1 && /^=======+$/ { s = 2; next }
  s == 2 && (/^>>>>>>>+$/ || /^>>>>>>>+ /) { s = 3 }
  END { print (s == 3) }'

(($# == 4)) || die 'usage: prepare.sh <gated-head> <trusted-base-sha> <version-bump-script> <out-dir>'
head=$1 base=$2 bump=$3 out=$4

version=$(git version)
version=${version#git version }
IFS=. read -r major minor _ <<<"$version"
if ! [[ $major =~ ^[0-9]+$ && $minor =~ ^[0-9]+$ ]] || ((major < 2 || (major == 2 && minor < 41))); then
  die "git $version cannot read attributes from a tree (GIT_ATTR_SOURCE); git 2.41 or later is required"
fi
for v in GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL; do
  [[ -n ${!v:-} ]] || die "$v is not set; the step env supplies the lanes bot identity"
done
cap=${LOOP_NO_PROGRESS:-3}
[[ $cap =~ ^[1-9][0-9]*$ ]] || die "LOOP_NO_PROGRESS must be a positive integer, got '$cap'"
[[ $head =~ $OID_RE ]] || die "gated head must be a full object id, got '$head'"
[[ $base =~ $OID_RE ]] || die "trusted base must be a full object id, got '$base'"
[[ -d .git ]] || die 'run from the root of a checkout whose .git is a directory'
[[ -f $bump ]] || die "version-bump script not found: $bump"

g cat-file -e "$base^{commit}" 2>/dev/null || die "trusted base $base is not a commit"
g cat-file -e "$head^{commit}" 2>/dev/null || die "gated head $head is not a commit"
export GIT_ATTR_SOURCE=$base
[[ $(g rev-parse --verify HEAD) == "$head" ]] || die "HEAD is not the gated head $head"
[[ -z $(g status --porcelain --untracked-files=no) ]] || die 'the checkout has staged or unstaged changes'

mkdir -p "$out"

escalate() {
  printf 'merge-state=escalate\nescalation-reason=%s\nconflict-tree=\n' "$1"
  exit 0
}

lane_runs=0
while IFS= read -r -d '' record; do
  [[ ${record%%$'\t'*} == "${GIT_AUTHOR_NAME:-}" ]] || break
  if [[ $'\t'${record#*$'\t'}$'\t' == *$'\t'"$TRAILER_VALUE"$'\t'* ]]; then
    lane_runs=$((lane_runs + 1))
  fi
done < <(g log --no-ext-diff --no-textconv --first-parent -z \
  --format="%an%x09%(trailers:key=Lane-Activity,valueonly,separator=%x09)" "$head")
((lane_runs < cap)) || escalate repeat-cap

rc=0
g merge --no-commit --no-ff "$base" >&2 || rc=$?
((rc <= 1)) || die "git merge exited $rc"
merge_head=$(g rev-parse -q --verify MERGE_HEAD) || die 'git merge left no merge in progress'
[[ $merge_head == "$base" ]] || die "MERGE_HEAD $merge_head is not the trusted base $base"

rc=0
GIT_CONFIG_COUNT=3 \
  GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null \
  GIT_CONFIG_KEY_1=core.fsmonitor GIT_CONFIG_VALUE_1='' \
  GIT_CONFIG_KEY_2=diff.external GIT_CONFIG_VALUE_2='' \
  LC_ALL=C bash "$bump" >&2 || rc=$?
((rc <= 1)) || die "version-bump script exited $rc"
g rev-parse -q --verify MERGE_HEAD >/dev/null || die 'the version-bump script ended the merge'

g ls-files -s -z >"$out/index-snapshot"

declare -A stages=() ours=() ours_mode=()
paths=()
protected=0
: >"$out/unmerged-paths"
while IFS= read -r -d '' record; do
  path=${record#*$'\t'}
  read -r mode oid stage <<<"${record%%$'\t'*}"
  if [[ $stage == 2 ]]; then ours[$path]=$oid ours_mode[$path]=$mode; fi
  if [[ -z ${stages[$path]:-} ]]; then
    paths+=("$path")
    printf '%s\0' "$path" >>"$out/unmerged-paths"
    if [[ ${path,,} =~ $PROTECTED_RE && ! ${path,,} =~ $PLUGIN_SETTINGS_RE ]]; then protected=1; fi
  fi
  if [[ $stage != 1 && ($mode == 160000 || $mode == 120000) ]]; then stage=x; fi
  stages[$path]+=$stage
done < <(g ls-files -u -z)

((protected == 0)) || escalate protected-path-conflict
for path in "${paths[@]}"; do
  [[ ${stages[$path]} == *2* && ${stages[$path]} == *3* && ${stages[$path]} != *x* ]] ||
    escalate unresolved-conflict
  [[ -f $path && ! -L $path ]] || escalate unresolved-conflict
  [[ $(g hash-object --path="$path" -- "$path") != "${ours[$path]}" ]] ||
    escalate unresolved-conflict
  found=$(tr -d '\r' <"$path" | LC_ALL=C awk "$MARKER_AWK")
  [[ $found == 1 ]] || escalate unresolved-conflict
done
if ((${#paths[@]})); then state=conflicted; else state=clean; fi

tree_index=$(mktemp -u "$out/t0-index.XXXXXX")
{
  while IFS= read -r -d '' record; do
    read -r _ _ stage <<<"${record%%$'\t'*}"
    if [[ $stage == 0 ]]; then printf '%s\0' "$record"; fi
  done <"$out/index-snapshot"
  for path in "${paths[@]}"; do
    printf '%s %s 0\t%s\0' "${ours_mode[$path]}" "$(g hash-object -w --no-filters -- "$path")" "$path"
  done
} | GIT_INDEX_FILE=$tree_index g update-index -z --index-info
tree=$(GIT_INDEX_FILE=$tree_index g write-tree)
rm -f "$tree_index"
printf 'merge-state=%s\nescalation-reason=\nconflict-tree=%s\n' "$state" "$tree"
