#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2
# shellcheck source=lib/changed-files.sh
. "$SCRIPT_DIR/lib/changed-files.sh" || exit 2
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2

emit() {
  printf 'docs_only=%s\n' "$1"
  [[ -z "${GITHUB_OUTPUT:-}" ]] || printf 'docs_only=%s\n' "$1" >>"$GITHUB_OUTPUT"
}

run_full() {
  echo "check-docs-only: $1 — running full suite" >&2
  emit false
  exit 0
}

BASE="${1:?usage: check-docs-only.sh <base-ref>}"
ALLOWLIST="${DOCS_ONLY_ALLOWLIST:-scripts/docs-only-paths.txt}"

if [[ ! -f "$ALLOWLIST" ]]; then
  run_full "allowlist not found ($ALLOWLIST)"
fi

if ! changed_files::verify_base "$BASE"; then
  run_full "base ref '$BASE' is not a resolvable commit"
fi

prefixes=()
if ! read_list::into prefixes "$ALLOWLIST" --comments inline; then
  run_full "could not read the allowlist ($ALLOWLIST)"
fi

if [[ ${#prefixes[@]} -eq 0 ]]; then
  run_full "allowlist has no active entries"
fi

changed=()
if ! changed_files::into changed "$BASE" --include-deleted --; then
  run_full "could not resolve paths changed vs '$BASE'"
fi

if [[ ${#changed[@]} -eq 0 ]]; then
  run_full "no changed paths vs '$BASE'"
fi

for path in "${changed[@]}"; do
  for prefix in "${prefixes[@]}"; do
    [[ "$path" == "$prefix"* ]] && continue 2
  done
  run_full "'$path' is outside the docs-only allowlist"
done

echo "check-docs-only: all ${#changed[@]} changed path(s) within the docs-only allowlist" >&2
emit true
exit 0
