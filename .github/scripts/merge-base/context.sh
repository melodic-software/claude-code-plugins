#!/usr/bin/env bash
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
keep() {
  local file=$1 cap=$2 size
  shift 2
  if ((written >= TOTAL_CAP)); then
    omitted=true
    return
  fi
  "$@" | { head -c "$((cap + 1))" >"$file" && cat >/dev/null; }
  size=$(wc -c <"$file")
  if ((size > cap)); then
    head -c "$cap" "$file" >"$file.cut"
    mv "$file.cut" "$file"
    printf '\n[context.sh: cut at %d bytes]\n' "$cap" >>"$file"
    size=$(wc -c <"$file")
  fi
  written=$((written + size))
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
  done
  keep "$out/$name/head.log" "$LOG_CAP" "${log[@]}" "$base..$head" -- "$path"
  keep "$out/$name/base.log" "$LOG_CAP" "${log[@]}" "$head..$base" -- "$path"
  entries+=("$(jq -cn --arg path "$path" --arg dir "$name" --argjson omitted "$omitted" '{path: $path, dir: $dir, omitted: $omitted}')")
done

mapfile -t merge_bases < <(g merge-base --all "$head" "$base" || true)
printf '%s\n' "${entries[@]}" |
  jq -s --arg head "$head" --arg base "$base" --args \
    '{head: $head, base: $base, merge_bases: $ARGS.positional, paths: .}' "${merge_bases[@]}" >"$out/conflicts.json"
chmod -R a-w "$out"
