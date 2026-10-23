#!/usr/bin/env bash
# Gate tests that cannot fail: /testing:audit's deterministic scan in --check mode.
#
#   scripts/check-cant-fail-scan.sh           scan the whole tree
#   scripts/check-cant-fail-scan.sh <base>    scan only the files changed since <base>
#
# Exit codes and streams follow README.md, "The check-script contract".
#
# With a base, every added, copied, modified or renamed file goes through the
# scanner's `--check --file`. The scanner decides what a test file is: a file it
# reports `adapter: none` for (no adapter claims it, its adapter is off, or
# paths.exclude drops it) is skipped, and any other exit 2 fails the gate. The
# whole-tree walk prunes some directories that `--file` does not, so a file under
# one of them is skipped here too; PRUNED mirrors collect_files() in the scanner,
# and this script's suite fails when the two differ. A diff with no test file in
# it reports the gate not applicable.
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
    printf '%s\n' "$out" | tail -1
  else
    printf '%s\n' "$out" >&2
  fi
  exit "$rc"
fi

top="$(git rev-parse --show-toplevel)" || exit 2
changed="$(git -C "$top" diff --name-only --diff-filter=ACMR "$1...HEAD")" || {
  printf 'ERROR: cannot diff against %s\n' "$1" >&2
  exit 2
}

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
  printf '::notice::Not applicable: no test file changed since %s; the scheduled run scans the whole tree.\n' "$1"
  exit 0
fi
[[ $worst -eq 0 ]] && printf 'PASS: %d changed test file(s), no gating findings.\n' "$scanned"
exit "$worst"
