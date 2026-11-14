#!/usr/bin/env bash
# The gitleaks rules each carrier vendors match the session-flow copy vendor_gitleaks_rules.py writes, byte for
# byte. The check lives here because no plugin may cite another's private files.
# test-scope: plugins/session-flow/skills/audit-sessions/vendor/gitleaks/* plugins/corrections/tools/findings-buffer/vendor/gitleaks/* plugins/explainer-video/vendor/gitleaks/*
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SELF_DIR/.." && pwd)"
CANON="$REPO/plugins/session-flow/skills/audit-sessions/vendor/gitleaks"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

for copy in corrections/tools/findings-buffer explainer-video; do
  for f in gitleaks-rules.json LICENSE-gitleaks; do
    if cmp -s "$CANON/$f" "$REPO/plugins/$copy/vendor/gitleaks/$f"; then
      ok "$copy $f matches the session-flow copy"
    else
      fail "$copy $f differs from the session-flow copy"
    fi
  done
done

test_harness::report
