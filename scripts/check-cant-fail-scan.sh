#!/usr/bin/env bash
# Gate tests that cannot fail: /testing:audit's deterministic scan in --check mode.
#
#   scripts/check-cant-fail-scan.sh           scan the whole tree
#   scripts/check-cant-fail-scan.sh <base>    scan only the files changed since <base>
#
# Exit codes and streams follow scripts/README.md, "The check-script contract".
#
# With a base, every added, copied, modified or renamed file goes through the
# scanner's `--check --file`. The scanner decides what a test file is: a file it
# reports `adapter: none` for (no adapter claims it, its adapter is off, or
# paths.exclude drops it) is skipped, and any other exit 2 fails the gate. The
# whole-tree walk prunes some directories that `--file` does not, so a file under
# one of them is skipped here too; PRUNED mirrors collect_files() in the scanner,
# and this script's suite fails when the two differ. A diff with no test file in
# it exits 0 and reports the gate not applicable with the count of files it
# looked at: a change that adds no test cannot add a test that cannot fail. An
# empty diff while HEAD is not the base exits 2, since it checked nothing, the
# rule scripts/check-affected.sh follows; HEAD at the base has no change and
# exits 0 (scripts/README.md, "The check-script contract").
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
SCAN="$SELF_DIR/../plugins/testing/skills/audit/scripts/cant-fail-scan.sh"
PRUNED='(^|/)(\.git|node_modules|vendor|dist|build|out|obj|bin|target|\.work|__pycache__|\.venv|venv)/|(^|/)evals/fixtures/'

[[ -f "$SCAN" ]] || {
  printf 'ERROR: scanner not found: %s\n' "$SCAN" >&2
  exit 2
}
[[ $# -le 1 ]] || {
  printf 'Usage: %s [<base-ref>]\n' "${0##*/}" >&2
  exit 2
}

if [[ -z "${1:-}" ]]; then
  out="$(bash "$SCAN" --check 2>&1)"
  rc=$?
  if [[ $rc -eq 0 ]]; then
    printf '%s\n' "${out##*$'\n'}"
  else
    printf '%s\n' "$out" >&2
  fi
  exit "$rc"
fi

top="$(git rev-parse --show-toplevel)" || exit 2
all="$(git -C "$top" diff --name-only "$1...HEAD")" || {
  printf 'ERROR: cannot diff against %s\n' "$1" >&2
  exit 2
}
if [[ -z "$all" ]]; then
  if [[ "$(git -C "$top" rev-list --count "$1...HEAD")" == 0 ]]; then
    printf '::notice::Not applicable: HEAD is %s, so there is no change to scan.\n' "$1"
    exit 0
  fi
  printf 'ERROR: no file changed since %s, yet HEAD is not %s, so there was nothing to check; pass no base to scan the whole tree.\n' "$1" "$1" >&2
  exit 2
fi
total="$(grep -c '' <<<"$all")"
changed="$(git -C "$top" diff --name-only --diff-filter=ACMR "$1...HEAD")" || exit 2

scanned=0
worst=0
while IFS= read -r path; do
  [[ -n "$path" && ! "$path" =~ $PRUNED ]] || continue
  out="$(bash "$SCAN" --check --file "$top/$path" 2>&1)"
  rc=$?
  if [[ $rc -eq 2 ]] && grep -q '^  adapter: none (' <<<"$out"; then
    continue
  fi
  scanned=$((scanned + 1))
  if [[ $rc -eq 0 ]]; then
    printf 'clean: %s\n' "$path"
    continue
  fi
  printf '%s\n' "$out" >&2
  if [[ $rc -eq 1 && $worst -ne 2 ]]; then worst=1; else worst=2; fi
done <<<"$changed"

if [[ $scanned -eq 0 ]]; then
  printf '::notice::Not applicable: %d file(s) changed since %s, none a test file the scan covers; check-tests scans the whole tree when there is no diff base.\n' "$total" "$1"
  exit 0
fi
[[ $worst -eq 0 ]] && printf 'PASS: %d changed test file(s), no gating findings.\n' "$scanned"
exit "$worst"
