#!/usr/bin/env bash
# prepare.sh <gated-head> <trusted-base-sha> <version-bump-script> <out-dir>
# <version-bump-script> must be the trusted base's copy, never the head checkout's.
#
# The prepare half of merge-base mode, run from the root of the PR head
# checkout before any model turn: start a merge of the trusted base into the
# gated head and decide whether a model is needed. pr-unblock.yml runs it three
# times on one round, each in a job of its own: resolve-conflicts-select decides,
# the read runner merges again for the model, and the write runner's
# apply-patch merges again to commit; the last two go on only when their
# conflict tree is the select job's. These checks guard against model mistakes
# and hostile head content.
#
# 1. Repeat cap: count the first-parent commits back to the last commit not
#    authored by the lanes bot that carry the resolve-conflicts lane trailer;
#    at LOOP_NO_PROGRESS (loop.no-progress, default 3) escalate before merging.
# 2. Merge <trusted-base-sha> without committing, then run the version-bump
#    script under LC_ALL=C, so the common version-bump collision needs no
#    model and the three runs of a round sort alike.
# 3. Snapshot the index (stage 0 and unmerged entries) to <out-dir>, list the
#    unmerged paths, and escalate when one is a protected path (a workflow or
#    a settings file), or when one is a conflict a model
#    cannot resolve from markers: a side missing (modify or rename against
#    delete) or no markers in the file (binary).
# 4. For a clean or conflicted merge, write the conflict tree, T0: the
#    snapshot's stage-0 entries, plus each unmerged path's file as git left it,
#    markers and all, hashed with --no-filters under its stage-2 (head) mode,
#    built in a scratch index so the merge's own index is untouched. A model's
#    patch is measured from T0, so it holds only the model's edits.
#
# Every git call, the version-bump script's included, reads gitattributes
# from the trusted base tree (GIT_ATTR_SOURCE, git 2.41 or later), so the
# head's .gitattributes cannot pick a merge driver or a marker size.
#
# Environment: GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL, GIT_COMMITTER_NAME and
# GIT_COMMITTER_EMAIL, the lanes bot identity (hosted runners have none, and
# git refuses even a --no-commit merge without one); the author name also
# identifies lane commits for the repeat cap.
#
# Stdout, one key=value line each, for step outputs (run-prepare.sh reads
# them): merge-state (clean | conflicted | escalate), escalation-reason
# (protected-path-conflict | unresolved-conflict | repeat-cap, empty
# otherwise), conflict-tree (T0, empty on an escalation).
#
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
# Conflicts the lane does not resolve, matched on the lower-cased path: a
# workflow, which the lane token cannot push, and a settings file, which a
# review job could load before review.
PROTECTED_RE='^\.github/workflows/|(^|/)settings[^/]*\.json$'
# Marker lines in order, any length from seven (conflict-marker-size): a run of
# <, then a run of =, then a run of >, the outer two followed by a space or the
# line end. apply-patch.mjs's hasConflictMarkers holds the same rule.
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

# Lane commits are recognized by author name only; a commit forged with that
# name can only make the cap escalate early.
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

# The script runs its own git calls; GIT_CONFIG_COUNT gives them the same
# overrides g passes on the command line, and GIT_ATTR_SOURCE is exported.
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
    if [[ ${path,,} =~ $PROTECTED_RE ]]; then protected=1; fi
  fi
  # A gitlink or symlink side has no markers either: count it as a missing
  # side. The ancestor's (stage 1) mode does not decide whether the sides merge.
  if [[ $stage != 1 && ($mode == 160000 || $mode == 120000) ]]; then stage=x; fi
  stages[$path]+=$stage
done < <(g ls-files -u -z)

((protected == 0)) || escalate protected-path-conflict
for path in "${paths[@]}"; do
  [[ ${stages[$path]} == *2* && ${stages[$path]} == *3* && ${stages[$path]} != *x* ]] ||
    escalate unresolved-conflict
  [[ -f $path && ! -L $path ]] || escalate unresolved-conflict
  # In place of a conflict it cannot mark up (binary), git leaves the head's
  # bytes, whatever they look like.
  [[ $(g hash-object --path="$path" -- "$path") != "${ours[$path]}" ]] ||
    escalate unresolved-conflict
  found=$(tr -d '\r' <"$path" | LC_ALL=C awk "$MARKER_AWK")
  [[ $found == 1 ]] || escalate unresolved-conflict
done
if ((${#paths[@]})); then state=conflicted; else state=clean; fi

# T0, in a scratch index: update-index -z --index-info reads the snapshot's
# "<mode> <oid> <stage>\t<path>" records as they are.
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
