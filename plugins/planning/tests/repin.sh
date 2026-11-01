#!/usr/bin/env bash
# Re-pin one or more digest pins of interview-defenses.test.sh, then run the test.
#
#   repin.sh [--test-file <path>] <pin-label>... <justification>
#
# scripts/repin-digests.sh does the re-pin from the files alone, with the same arguments: its
# header has the label and justification rules and what it prints. This script then runs the
# test once and prints PASS or FAIL. It runs the test file, so it is for a host session; the
# issue lane runs scripts/repin-digests.sh, which runs nothing from the checkout.
#
# Exit: 0 re-pinned and the test passes; 1 re-pinned but the test still fails; otherwise
# repin-digests.sh's own exit (2 usage, an unreadable test file or no digest tool; 3 a label
# that names no one pin; 4 nothing changed), with the file unchanged.
set -uo pipefail

self="$(basename "$0")"
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
test_file="$here/interview-defenses.test.sh"

if [[ "${1:-}" == "--test-file" ]]; then
  [[ $# -ge 2 ]] || {
    echo "usage: $self [--test-file <path>] <pin-label>... <justification>" >&2
    exit 2
  }
  test_file="$2"
  shift 2
fi
# repin-digests.sh reads only under the current directory, so run it from the test's plugin.
test_dir="$(cd "$(dirname "$test_file")" && pwd)" || exit 2
test_file="$test_dir/$(basename "$test_file")"
cd "$test_dir/.." || exit 2

bash "$here/../scripts/repin-digests.sh" --test-file "$test_file" "$@" || exit

if bash "$test_file" >/dev/null 2>&1; then
  echo "PASS"
  exit 0
fi
echo "FAIL: ${test_file##*/} still fails after the re-pin; run it for the failing pins." >&2
exit 1
