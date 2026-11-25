#!/usr/bin/env bash
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
