#!/usr/bin/env bash
# prepare.sh <gated-head> <trusted-base-sha> <version-bump-script> <out-dir>
#
# The prepare half of the write runner's merge-base mode, run from the root of
# the PR head checkout before any model turn: start a merge of the trusted base
# into the gated head and decide whether a model is needed.
#
# 1. Save copies of .git/config and .git/info/attributes in <out-dir>; the
#    action run later rewrites .git/config and post.sh puts the copies back.
# 2. Repeat cap: count the first-parent commits back to the last commit not
#    authored by the lanes bot that carry the resolve-conflicts lane trailer;
#    at LOOP_NO_PROGRESS (loop.no-progress, default 3) escalate before merging.
# 3. Merge <trusted-base-sha> without committing, then run the version-bump
#    script, so the common version-bump collision needs no model.
# 4. Snapshot the index (stage 0 and unmerged entries) to <out-dir>, list the
#    unmerged paths, and escalate when one is a protected path.
#
# Environment: GIT_AUTHOR_NAME, GIT_AUTHOR_EMAIL, GIT_COMMITTER_NAME and
# GIT_COMMITTER_EMAIL, the lanes bot identity (hosted runners have none, and
# git refuses even a --no-commit merge without one); the author name also
# identifies lane commits for the repeat cap.
#
# Stdout, one key=value line each, for step outputs: config-sha256,
# attributes-sha256 (`absent` when there is no file), snapshot-sha256,
# merge-state (clean | conflicted | escalate), escalation-reason
# (protected-path-conflict | repeat-cap, empty otherwise). The caller keeps the
# hashes as step outputs and hands them to post.sh; files under <out-dir> are
# not trusted on their own.
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
sha256() {
  local s
  s=$(sha256sum <"$1")
  printf '%s' "${s%% *}"
}

TRAILER_VALUE=pr-unblock/resolve-conflicts
# The paths claude-code-action restores from the base branch before the model
# runs (SENSITIVE_PATHS in src/github/operations/restore-config.ts, read at
# pin ed670b4 on 2026-10-11; recheck when the action pin moves). post.sh holds
# the same list.
PROTECTED_RE='^(\.github/workflows/|(\.claude|\.mcp\.json|\.claude\.json|\.gitmodules|\.ripgreprc|CLAUDE\.md|CLAUDE\.local\.md|\.husky)(/|$))'

(($# == 4)) || die 'usage: prepare.sh <gated-head> <trusted-base-sha> <version-bump-script> <out-dir>'
head_arg=$1 base_arg=$2 bump=$3 out=$4

for v in GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL; do
  [[ -n ${!v:-} ]] || die "$v is not set; the step env supplies the lanes bot identity"
done
cap=${LOOP_NO_PROGRESS:-3}
[[ $cap =~ ^[1-9][0-9]*$ ]] || die "LOOP_NO_PROGRESS must be a positive integer, got '$cap'"
[[ -d .git ]] || die 'run from the root of a checkout whose .git is a directory'
[[ -f $bump ]] || die "version-bump script not found: $bump"

g cat-file -e "$base_arg^{commit}" 2>/dev/null || die "trusted base $base_arg is not a commit"
base=$(g rev-parse --verify "$base_arg^{commit}")
head=$(g rev-parse -q --verify "$head_arg^{commit}") || die "gated head $head_arg is not a commit"
[[ $(g rev-parse --verify HEAD) == "$head" ]] || die "HEAD is not the gated head $head"
[[ -z $(g status --porcelain --untracked-files=no) ]] || die 'the checkout has staged or unstaged changes'

mkdir -p "$out"
cp .git/config "$out/config"
printf 'config-sha256=%s\n' "$(sha256 "$out/config")"
if [[ -f .git/info/attributes ]]; then
  cp .git/info/attributes "$out/attributes"
  printf 'attributes-sha256=%s\n' "$(sha256 "$out/attributes")"
else
  printf 'attributes-sha256=absent\n'
fi

escalate() {
  printf 'merge-state=escalate\nescalation-reason=%s\n' "$1"
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

# The script runs its own git calls; GIT_CONFIG_COUNT gives them the same
# overrides g passes on the command line.
rc=0
GIT_CONFIG_COUNT=3 \
  GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=/dev/null \
  GIT_CONFIG_KEY_1=core.fsmonitor GIT_CONFIG_VALUE_1='' \
  GIT_CONFIG_KEY_2=diff.external GIT_CONFIG_VALUE_2='' \
  bash "$bump" >&2 || rc=$?
((rc <= 1)) || die "version-bump script exited $rc"
g rev-parse -q --verify MERGE_HEAD >/dev/null || die 'the version-bump script ended the merge'

g ls-files -s -z >"$out/index-snapshot"
printf 'snapshot-sha256=%s\n' "$(sha256 "$out/index-snapshot")"

declare -A seen=()
protected=0
: >"$out/unmerged-paths"
while IFS= read -r -d '' record; do
  path=${record#*$'\t'}
  [[ -z ${seen[$path]:-} ]] || continue
  seen[$path]=1
  printf '%s\0' "$path" >>"$out/unmerged-paths"
  if [[ $path =~ $PROTECTED_RE ]]; then protected=1; fi
done < <(g ls-files -u -z)

((protected == 0)) || escalate protected-path-conflict
if ((${#seen[@]})); then state=conflicted; else state=clean; fi
printf 'merge-state=%s\nescalation-reason=\n' "$state"
