#!/usr/bin/env bash
# Checks the run-tests.sh CLI surface only; the npm steps are CI's job.
set -euo pipefail

SCRIPT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/run-tests.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

out="$(bash "$SCRIPT" --help 2>/dev/null)" || fail "--help exited nonzero"
[[ "$out" == *"usage: run-tests.sh"* ]] || fail "--help printed no usage on stdout"
[[ "$out" == *"exit codes:"* ]] || fail "--help does not document exit codes"

rc=0
err="$(bash "$SCRIPT" bogus 2>&1 >/dev/null)" || rc=$?
[[ "$rc" -eq 2 ]] || fail "unknown subcommand exited $rc, expected 2"
[[ "$err" == *"unknown subcommand 'bogus'"* ]] || fail "error does not name the rejected argument on stderr"

echo "PASS: run-tests.sh CLI surface"
