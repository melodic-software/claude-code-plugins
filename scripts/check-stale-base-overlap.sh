#!/usr/bin/env bash
# Gate: refuse a PR whose merge-base is behind the target tip on overlapping paths.
#
#   scripts/check-stale-base-overlap.sh --check <base-ref>
#
# Why: squash-merging a PR cut from a stale base can silently drop commits that
# landed on the base after the PR branched — including the tests that would have
# caught the drop. CI stays green because the reverting squash deletes those
# tests in the same commit.
#
# SCOPE — the stale-BASE class only, and only that class. The
# claude-code-plugins#2691 audit surfaced two distinct classes; this gate covers
# the one where the merge-base is genuinely behind the target tip. It does NOT
# cover the 2026-08-15 incidents (#2633, #2639, #2641), which were stale in
# CONTENT while up to date in HISTORY: `git merge-base --is-ancestor f603880d
# refs/pull/2641/head` is true, yet that tree carried none of #2639's work. Run
# against those exact branches this check exits 0 ("fresh"). That class belongs
# to scripts/check-silent-revert.sh. The two cover disjoint classes and neither
# subsumes the other, so a green run here is not evidence about the other class.
#
# Agreement is established by comparing path lists only:
#   1. merge-base(HEAD, <base-ref>) == tip(<base-ref>) → fresh, exit 0.
#   2. Else intersect paths changed on base since the merge-base with paths
#      changed on HEAD since the merge-base.
#   3. Non-empty intersection → exit 1 with the overlapping paths.
#   4. Empty intersection → exit 0 (parallel work on disjoint files).
#
# Unrecognized git state is exit 2 (inconclusive), never a pass.
set -uo pipefail

# Operate on the caller's git work tree (CI checks out the PR and runs from its
# root; the self-test cds into a scratch repo before invoking). Never force-cd
# to the script's install location — that would always inspect this repository
# instead of the tree under test.
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "check-stale-base-overlap: not inside a git work tree" >&2
  exit 2
fi
cd "$(git rev-parse --show-toplevel)" || exit 2

usage() {
  echo "usage: $(basename "$0") --check <base-ref>" >&2
  exit 2
}

mode="${1:-}"
base_ref="${2:-}"
case "$mode" in
--check)
  [[ -n "$base_ref" ]] || usage
  ;;
*)
  usage
  ;;
esac

if ! git rev-parse --verify --quiet "${base_ref}^{commit}" >/dev/null; then
  echo "check-stale-base-overlap: base ref not resolvable: $base_ref" >&2
  exit 2
fi
if ! git rev-parse --verify --quiet "HEAD^{commit}" >/dev/null; then
  echo "check-stale-base-overlap: HEAD not resolvable" >&2
  exit 2
fi

merge_base="$(git merge-base HEAD "$base_ref" 2>/dev/null)" || {
  echo "check-stale-base-overlap: cannot compute merge-base of HEAD and $base_ref" >&2
  exit 2
}
base_tip="$(git rev-parse "${base_ref}^{commit}")" || exit 2

if [[ "$merge_base" == "$base_tip" ]]; then
  echo "check-stale-base-overlap: HEAD is up to date with $base_ref"
  exit 0
fi

# Name-status so renames/copies contribute BOTH the old and new path.
# --name-only alone would keep only the destination and miss overlaps on the
# pre-rename path when the other side still touches the old name.
list_paths() {
  local a="$1" b="$2"
  git diff --name-status --diff-filter=ACDMRTUXB "$a" "$b" | awk -F '	' '
    /^[CR][0-9]*/ { print $2; print $3; next }
    NF >= 2 { print $2 }
  ' | LC_ALL=C sort -u
}

base_paths="$(list_paths "$merge_base" "$base_tip")" || {
  echo "check-stale-base-overlap: cannot list paths changed on $base_ref since merge-base" >&2
  exit 2
}
head_paths="$(list_paths "$merge_base" HEAD)" || {
  echo "check-stale-base-overlap: cannot list paths changed on HEAD since merge-base" >&2
  exit 2
}

overlap="$(
  comm -12 <(printf '%s\n' "$base_paths") <(printf '%s\n' "$head_paths")
)"

behind_by="$(git rev-list --count "$merge_base..$base_tip" 2>/dev/null || echo '?')"

if [[ -z "$overlap" ]]; then
  echo "check-stale-base-overlap: HEAD is $behind_by commit(s) behind $base_ref but touches no overlapping paths"
  exit 0
fi

echo "check-stale-base-overlap: STALE BASE with overlapping paths" >&2
echo "  base:       $base_ref ($base_tip)" >&2
echo "  merge-base: $merge_base" >&2
echo "  behind_by:  $behind_by" >&2
echo "  overlapping paths (changed on both base and this PR since the merge-base):" >&2
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  printf '    %s\n' "$path" >&2
done <<<"$overlap"
echo >&2
echo "Refresh before merge: integrate origin/$base_ref (merge or update-branch)," >&2
echo "re-run CI, then merge. A stale-base squash can silently revert recently" >&2
echo "landed fixes on the overlapping paths (claude-code-plugins#2691)." >&2
echo "Scope: stale BASE only. A branch stale in content but current in history" >&2
echo "passes this check — that class is scripts/check-silent-revert.sh." >&2
exit 1
