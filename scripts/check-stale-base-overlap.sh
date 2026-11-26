#!/usr/bin/env bash
set -uo pipefail

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "check-stale-base-overlap: not inside a git work tree" >&2
  exit 2
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
# shellcheck source=lib/changed-files.sh
. "$SCRIPT_DIR/lib/changed-files.sh" || exit 2
# shellcheck source=lib/gate-entry.sh
. "$SCRIPT_DIR/lib/gate-entry.sh" || exit 2
cd "$(git rev-parse --show-toplevel)" || exit 2

usage() {
  echo "usage: $(basename "$0") --check|--warn <base-ref>" >&2
  exit 2
}

GE_FLAGS=("--check:ref" "--warn:ref")
GE_BAD_REF_MSG="check-stale-base-overlap: base ref not resolvable: ${2-}"
# shellcheck disable=SC2310  # the non-zero return IS the handled case
gate_entry::classify "$@" || usage
base_ref="$GE_REF"
if ! changed_files::verify_base HEAD; then
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
  gate_entry::finish 0
fi

base_paths=()
# shellcheck disable=SC2310  # the non-zero return IS the handled case
if ! changed_files::into base_paths "$merge_base..$base_tip" --include-deleted --no-renames; then
  echo "check-stale-base-overlap: cannot list paths changed on $base_ref since merge-base" >&2
  exit 2
fi
head_paths=()
# shellcheck disable=SC2310  # the non-zero return IS the handled case
if ! changed_files::into head_paths "$merge_base..HEAD" --include-deleted --no-renames; then
  echo "check-stale-base-overlap: cannot list paths changed on HEAD since merge-base" >&2
  exit 2
fi

generated_paths=(docs/catalog.md docs/skill-cheat-sheet.md)
kept=()
for path in ${head_paths[@]+"${head_paths[@]}"}; do
  [[ " ${generated_paths[*]} " == *" $path "* ]] || kept+=("$path")
done
head_paths=(${kept[@]+"${kept[@]}"})

overlap="$(
  comm -12 \
    <(printf '%s\n' ${base_paths[@]+"${base_paths[@]}"} | LC_ALL=C sort -u) \
    <(printf '%s\n' ${head_paths[@]+"${head_paths[@]}"} | LC_ALL=C sort -u)
)"

behind_by="$(git rev-list --count "$merge_base..$base_tip" 2>/dev/null || echo '?')"

print_overlap() {
  local path
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    printf '    %s\n' "$path" >&2
  done <<<"$overlap"
}

if [[ -z "$overlap" ]]; then
  echo "check-stale-base-overlap: HEAD is $behind_by commit(s) behind $base_ref but touches no overlapping paths"
  gate_entry::finish 0
fi

if [[ "$GE_MODE" == --warn ]]; then
  echo "::warning title=Stale base::HEAD is $behind_by commit(s) behind $base_ref on overlapping paths: ${overlap//$'\n'/, }"
  gate_entry::finish 0
fi

release_notes_only=1
while IFS= read -r path; do
  [[ "$path" == CHANGELOG.md || "$path" == */CHANGELOG.md || "$path" == .changes/* ]] || release_notes_only=0
done <<<"$overlap"
if ((release_notes_only)); then
  echo "check-stale-base-overlap: WARNING: HEAD is $behind_by commit(s) behind $base_ref; the only overlapping paths are changelogs or changelog fragments:" >&2
  print_overlap
  echo "  Not refused: the merge queue tests this change on the current base." >&2
  gate_entry::finish 0
fi

echo "check-stale-base-overlap: STALE BASE with overlapping paths" >&2
echo "  base:       $base_ref ($base_tip)" >&2
echo "  merge-base: $merge_base" >&2
echo "  behind_by:  $behind_by" >&2
echo "  overlapping paths (changed on both base and this PR since the merge-base):" >&2
print_overlap
echo >&2
echo "Refresh before merge: integrate $base_ref (merge or update-branch)," >&2
echo "re-run CI, then merge. A stale-base squash can silently revert recently" >&2
echo "landed fixes on the overlapping paths (claude-code-plugins#2691)." >&2
echo "Scope: stale BASE only. A branch stale in content but current in history" >&2
echo "passes this check — that class is scripts/check-silent-revert.sh." >&2
gate_entry::finish 1
