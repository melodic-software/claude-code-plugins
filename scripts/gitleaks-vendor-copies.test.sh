#!/usr/bin/env bash
# test-scope: plugins/session-flow/vendor/gitleaks/* plugins/corrections/tools/findings-buffer/vendor/gitleaks/* plugins/explainer-video/vendor/gitleaks/* plugins/evals/vendor/gitleaks/*
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SELF_DIR/.." && pwd)"
CANON="$REPO/plugins/session-flow/vendor/gitleaks"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

for copy in corrections/tools/findings-buffer explainer-video evals; do
  for f in gitleaks-rules.json LICENSE-gitleaks; do
    if cmp -s "$CANON/$f" "$REPO/plugins/$copy/vendor/gitleaks/$f"; then
      ok "$copy $f matches the session-flow copy"
    else
      fail "$copy $f differs from the session-flow copy"
    fi
  done
done

test_harness::report
