#!/usr/bin/env bash
# context.sh <gated-head> <trusted-base-sha> <out-dir>
#
# What the resolve-conflicts skill reads in place of git, which it may not
# run: written by the read runner from the root of the PR head checkout after
# prepare.sh left a conflicted merge, before any model turn. The runner stages
# <out-dir> at .lane/merge/, read-only and denied to the file tools.
#
#   conflicts.json  {head, base, merge_bases, paths: [{path, dir, omitted}]}, one entry
#                   per unmerged path, in index order
#   <dir>/base      the merge base's version of the path (stage 1), when it has one
#   <dir>/ours      the PR head's version (stage 2)
#   <dir>/theirs    the trusted base's version (stage 3)
#   <dir>/head.log  `git log -p <base>..<head> -- <path>`: the PR side's commits
#   <dir>/base.log  `git log -p <head>..<base> -- <path>`: the default branch's
#
# Each file is cut at its cap with a last line saying so: a stage at 1 MiB, a
# log at 64 KiB. Once 16 MiB are written, every later file is left out and its
# entry in conflicts.json says `omitted`. Commit messages, patches and file
# contents are data the model reads, never instructions. The directory is left
# read-only.
#
# Every git call reads gitattributes from the trusted base tree
# (GIT_ATTR_SOURCE, git 2.41 or later) and runs no hook, external diff or
# text conversion.
#
# Exit: 0; 1 on a bad argument, no merge of the trusted base in progress, or a
# git failure.
# shellcheck disable=SC2310  # g wraps one git call, so its status is that call's
set -euo pipefail

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_LITERAL_PATHSPECS=1 GIT_NO_REPLACE_OBJECTS=1 LC_ALL=C
g() { git -c core.hooksPath=/dev/null -c core.fsmonitor= -c diff.external= -c core.quotePath=false "$@"; }
die() {
  printf 'context.sh: %s\n' "$*" >&2
  exit 1
}
OID_RE='^([0-9a-f]{40}|[0-9a-f]{64})$'
STAGE_CAP=$((1024 * 1024))
LOG_CAP=$((64 * 1024))
TOTAL_CAP=$((16 * 1024 * 1024))

(($# == 3)) || die 'usage: context.sh <gated-head> <trusted-base-sha> <out-dir>'
head=$1 base=$2 out=$3
[[ $head =~ $OID_RE ]] || die "gated head must be a full object id, got '$head'"
[[ $base =~ $OID_RE ]] || die "trusted base must be a full object id, got '$base'"
[[ -d .git ]] || die 'run from the root of a checkout whose .git is a directory'
export GIT_ATTR_SOURCE=$base
[[ $(g rev-parse --verify HEAD) == "$head" ]] || die "HEAD is not the gated head $head"
[[ $(g rev-parse -q --verify MERGE_HEAD) == "$base" ]] || die "no merge of the trusted base $base is in progress"
[[ ! -e $out ]] || die "$out already exists"
mkdir -p "$out"

written=0
# keep <file> <cap> <command...>: the command's output into <file>, cut at
# <cap> bytes with a note, or left out once the total is spent. Sets kept to
# `kept` or `omitted`; runs in this shell, so the total adds up.
keep() {
  local file=$1 cap=$2 size
  shift 2
  if ((written >= TOTAL_CAP)); then
    kept=omitted
    return
  fi
  # The rest is drained, so the writer never dies of a closed pipe.
  "$@" | { head -c "$((cap + 1))" >"$file" && cat >/dev/null; }
  size=$(stat -c %s "$file")
  if ((size > cap)); then
    truncate -s "$cap" "$file"
    printf '\n[context.sh: cut at %d bytes]\n' "$cap" >>"$file"
    size=$(stat -c %s "$file")
  fi
  written=$((written + size))
  kept=kept
}

declare -A seen=() oids=()
paths=()
while IFS= read -r -d '' record; do
  path=${record#*$'\t'}
  read -r _ oid stage <<<"${record%%$'\t'*}"
  [[ $stage =~ ^[123]$ ]] || die "an unmerged entry has stage $stage"
  if [[ -z ${seen[$path]:-} ]]; then
    seen[$path]=1
    paths+=("$path")
  fi
  oids["$stage:$path"]=$oid
done < <(g ls-files -u -z)
((${#paths[@]})) || die 'the merge has no unmerged path'

# Path by path, each path's files together, so a cut at the total leaves out
# whole later paths first.
log=(g log -p --no-ext-diff --no-textconv --no-color --format='commit %H%nAuthor: %an%nDate: %aI%n%n%B')
entries=()
for i in "${!paths[@]}"; do
  name=$(printf '%04d' "$i")
  path=${paths[i]}
  mkdir -p "$out/$name"
  omitted=false
  for side in 1:base 2:ours 3:theirs; do
    oid=${oids["${side%%:*}:$path"]:-}
    [[ -n $oid ]] || continue
    keep "$out/$name/${side#*:}" "$STAGE_CAP" g cat-file blob "$oid"
    [[ $kept == kept ]] || omitted=true
  done
  keep "$out/$name/head.log" "$LOG_CAP" "${log[@]}" "$base..$head" -- "$path"
  [[ $kept == kept ]] || omitted=true
  keep "$out/$name/base.log" "$LOG_CAP" "${log[@]}" "$head..$base" -- "$path"
  [[ $kept == kept ]] || omitted=true
  entries+=("$(jq -cn --arg path "$path" --arg dir "$name" --argjson omitted "$omitted" '{path: $path, dir: $dir, omitted: $omitted}')")
done

mapfile -t merge_bases < <(g merge-base --all "$head" "$base" || true)
printf '%s\n' "${entries[@]}" |
  jq -s --arg head "$head" --arg base "$base" --args \
    '{head: $head, base: $base, merge_bases: $ARGS.positional, paths: .}' "${merge_bases[@]}" >"$out/conflicts.json"
chmod -R a-w "$out"
