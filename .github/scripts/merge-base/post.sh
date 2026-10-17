#!/usr/bin/env bash
# post.sh <out-dir>
#
# The post half of the write runner's merge-base mode, run from the root of the
# PR head checkout after the model turn, on the <out-dir> prepare.sh wrote.
# These checks guard against model mistakes and hostile head content, not
# against a hostile model on the same runner: the lane token is model-reachable
# by design.
#
# 1. Check the saved .git/config and .git/info/attributes copies and the index
#    snapshot against the hashes prepare.sh printed, failing closed on any
#    mismatch before writing anything; then overwrite the live files from the
#    copies (claude-code-action rewrites .git/config during the run). Then fail
#    unless HEAD is still the gated head and MERGE_HEAD the trusted base, so an
#    aborted, reset or committed merge is never taken for a resolution.
# 2. Sensitive-path repair: claude-code-action resets the index entries of the
#    paths it restores from the base, which during a merge drops the merged
#    content. Remove every such entry from the index and re-apply the
#    snapshot's entries for them.
# 3. Checks, first match wins:
#    unresolved-conflict  an unmerged entry remains, or an entry staged since
#                         the snapshot (a resolution, wherever the model put
#                         it) holds a conflict-marker sequence;
#    workflow-staged      an index entry under .github/workflows/ was added,
#                         removed, or changed in mode or blob since the
#                         snapshot, or differs from the gated head's tree (a
#                         workflow change merged in from the base: the lane
#                         token cannot push one).
#
# 4. With no reason, write the validated index as a tree; tree-entries.sh
#    takes that tree, so nothing staged after this check reaches the commit.
#
# Every git call reads gitattributes from the trusted base tree
# (GIT_ATTR_SOURCE, git 2.41 or later).
#
# Environment: CONFIG_SHA256, ATTRIBUTES_SHA256 (`absent` when prepare found no
# attributes file) and SNAPSHOT_SHA256, prepare.sh's step outputs; GATED_HEAD
# and TRUSTED_BASE, the full object ids prepare.sh was given.
#
# Stdout: escalation-reason=<reason>, empty when the staged merge may be
# committed, and then tree=<oid>. Exit: 0 with a reason; 1 on a hash mismatch,
# a moved HEAD or MERGE_HEAD, or a git failure.
# shellcheck disable=SC2310  # g wraps one git call, so its status is that call's
set -euo pipefail

export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 GIT_LITERAL_PATHSPECS=1
g() { git -c core.hooksPath=/dev/null -c core.fsmonitor= -c diff.external= "$@"; }
die() {
  printf 'post.sh: %s\n' "$*" >&2
  exit 1
}
verify() {
  local s
  s=$(sha256sum <"$1")
  [[ ${s%% *} == "$2" ]] || die "$1 does not match its recorded SHA-256"
}

# The paths claude-code-action restores from the base branch (SENSITIVE_PATHS
# in src/github/operations/restore-config.ts, read at pin ed670b4 on
# 2026-10-11; recheck when the action pin moves). prepare.sh holds the same list.
SENSITIVE_RE='^(\.claude|\.mcp\.json|\.claude\.json|\.gitmodules|\.ripgreprc|CLAUDE\.md|CLAUDE\.local\.md|\.husky)(/|$)'
WORKFLOW_RE='^\.github/workflows/'

OID_RE='^([0-9a-f]{40}|[0-9a-f]{64})$'

(($# == 1)) || die 'usage: post.sh <out-dir>'
out=$1
version=$(git version)
version=${version#git version }
IFS=. read -r major minor _ <<<"$version"
if ! [[ $major =~ ^[0-9]+$ && $minor =~ ^[0-9]+$ ]] || ((major < 2 || (major == 2 && minor < 41))); then
  die "git $version cannot read attributes from a tree (GIT_ATTR_SOURCE); git 2.41 or later is required"
fi
for v in CONFIG_SHA256 ATTRIBUTES_SHA256 SNAPSHOT_SHA256 GATED_HEAD TRUSTED_BASE; do
  [[ -n ${!v:-} ]] || die "$v is not set; pass prepare.sh's step output"
done
attributes_sha=${ATTRIBUTES_SHA256:-}
head=${GATED_HEAD:-} base=${TRUSTED_BASE:-}
[[ $head =~ $OID_RE ]] || die "GATED_HEAD must be a full object id, got '$head'"
[[ $base =~ $OID_RE ]] || die "TRUSTED_BASE must be a full object id, got '$base'"
[[ -d .git ]] || die 'run from the root of a checkout whose .git is a directory'

verify "$out/config" "${CONFIG_SHA256:-}"
[[ $attributes_sha == absent ]] || verify "$out/attributes" "$attributes_sha"
verify "$out/index-snapshot" "${SNAPSHOT_SHA256:-}"

rm -f .git/config .git/info/attributes
cp "$out/config" .git/config
if [[ $attributes_sha != absent ]]; then
  mkdir -p .git/info
  cp "$out/attributes" .git/info/attributes
fi

g cat-file -e "$base^{commit}" 2>/dev/null || die "trusted base $base is not a commit"
export GIT_ATTR_SOURCE=$base
[[ $(g rev-parse --verify HEAD) == "$head" ]] || die "HEAD is not the gated head $head"
merge_head=$(g rev-parse -q --verify MERGE_HEAD) || die 'no merge in progress'
[[ $merge_head == "$base" ]] || die "MERGE_HEAD $merge_head is not the trusted base $base"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

case $(g rev-parse --show-object-format) in
  sha1) null_oid=$(printf '%040d' 0) ;;
  sha256) null_oid=$(printf '%064d' 0) ;;
  *) die 'unknown object format' ;;
esac

# --index-info must be update-index's last option, so it reads lines, not
# NUL-terminated records: every path goes in C-quoted.
cquote() {
  local q=${1//\\/\\\\}
  q=${q//\"/\\\"}
  q=${q//$'\n'/\\n}
  q=${q//$'\t'/\\t}
  q=${q//$'\r'/\\r}
  printf '"%s"' "$q"
}
# Mode 0 removes a path at every stage; the snapshot lines re-add the entries.
g ls-files -s -z >"$tmp/index"
while IFS= read -r -d '' record; do
  path=${record#*$'\t'}
  if [[ $path =~ $SENSITIVE_RE ]]; then printf '0 %s\t%s\n' "$null_oid" "$(cquote "$path")"; fi
done <"$tmp/index" >"$tmp/repair"
while IFS= read -r -d '' record; do
  path=${record#*$'\t'}
  if [[ $path =~ $SENSITIVE_RE ]]; then printf '%s\t%s\n' "${record%%$'\t'*}" "$(cquote "$path")"; fi
done <"$out/index-snapshot" >>"$tmp/repair"
g update-index --index-info <"$tmp/repair"

reason() {
  printf 'escalation-reason=%s\n' "$1"
  exit 0
}

[[ -z $(g ls-files -u) ]] || reason unresolved-conflict

# Entries the snapshot already held at stage 0 are the merge's own; every
# other entry, a conflict's resolution or a path the model added, moved or
# changed, is scanned.
declare -A merged=()
while IFS= read -r -d '' record; do
  read -r _ _ stage <<<"${record%%$'\t'*}"
  if [[ $stage == 0 ]]; then merged[$record]=1; fi
done <"$out/index-snapshot"

# Marker lines in order, any length from seven (conflict-marker-size): a run of
# <, then a run of =, then a run of >, the outer two followed by a space or the
# line end. prepare.sh holds the same program.
# shellcheck disable=SC2016  # an awk program, expanded by awk
marker_awk='
  s == 0 && (/^<<<<<<<+$/ || /^<<<<<<<+ /) { s = 1; next }
  s == 1 && /^=======+$/ { s = 2; next }
  s == 2 && (/^>>>>>>>+$/ || /^>>>>>>>+ /) { s = 3 }
  END { print (s == 3) }'
g ls-files -s -z >"$tmp/index"
while IFS= read -r -d '' record; do
  [[ -z ${merged[$record]:-} ]] || continue
  read -r mode oid _ <<<"${record%%$'\t'*}"
  [[ $mode != 160000 ]] || continue
  found=$(g cat-file blob "$oid" | tr -d '\r' | LC_ALL=C awk "$marker_awk")
  [[ $found == 0 ]] || reason unresolved-conflict
done <"$tmp/index"

filter_workflows() {
  while IFS= read -r -d '' record; do
    if [[ ${record#*$'\t'} =~ $WORKFLOW_RE ]]; then printf '%s\0' "$record"; fi
  done <"$1"
}
filter_workflows "$out/index-snapshot" >"$tmp/workflows-before"
filter_workflows "$tmp/index" >"$tmp/workflows-after"
cmp -s "$tmp/workflows-before" "$tmp/workflows-after" || reason workflow-staged
g ls-tree -r -z --full-tree --format='%(objectmode) %(objectname) 0%x09%(path)' "$head" -- .github/workflows >"$tmp/head-tree"
filter_workflows "$tmp/head-tree" >"$tmp/workflows-head"
cmp -s "$tmp/workflows-head" "$tmp/workflows-after" || reason workflow-staged

tree=$(g write-tree)
printf 'escalation-reason=\ntree=%s\n' "$tree"
