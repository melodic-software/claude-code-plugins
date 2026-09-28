#!/usr/bin/env bash
# Resolve-only contract for scripts/gitleaks-scoped-scan.sh (#3599).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$ROOT/scripts/gitleaks-scoped-scan.sh"
zero="$(printf '0%.0s' {1..40})"
base="$(printf 'a%.0s' {1..40})"
head="$(printf 'b%.0s' {1..40})"

fail=0
assert_eq() {
  local want="$1" got="$2" label="$3"
  if [ "$want" != "$got" ]; then
    echo "FAIL $label: want <$want> got <$got>" >&2
    fail=1
  else
    echo "ok $label"
  fi
}

got="$(
  EVENT_NAME=pull_request PR_BASE_SHA="$base" PR_HEAD_SHA="$head" \
    bash "$SCRIPT" --resolve-only
)"
assert_eq "--no-merges --first-parent ${base}^..${head}" "$got" "pull_request range"

got="$(
  EVENT_NAME=push PUSH_BEFORE="$base" PUSH_AFTER="$head" \
    bash "$SCRIPT" --resolve-only
)"
assert_eq "--no-merges --first-parent ${base}^..${head}" "$got" "push range"

got="$(
  EVENT_NAME=push PUSH_BEFORE="$head" PUSH_AFTER="$head" \
    bash "$SCRIPT" --resolve-only
)"
assert_eq "-1" "$got" "push same-ref"

got="$(
  EVENT_NAME=workflow_dispatch bash "$SCRIPT" --resolve-only
)"
assert_eq "-1" "$got" "workflow_dispatch"

if EVENT_NAME=push PUSH_BEFORE="$zero" PUSH_AFTER="$head" bash "$SCRIPT" --resolve-only; then
  echo "FAIL push zero-before should exit 2" >&2
  fail=1
else
  echo "ok push zero-before refuses"
fi

if EVENT_NAME=schedule bash "$SCRIPT" --resolve-only; then
  echo "FAIL unsupported event should exit 2" >&2
  fail=1
else
  echo "ok unsupported event refuses"
fi

exit "$fail"
