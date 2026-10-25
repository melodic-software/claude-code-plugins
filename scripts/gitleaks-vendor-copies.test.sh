#!/usr/bin/env bash
# The gitleaks rules corrections' findings buffer vendors match the session-flow
# copy vendor_gitleaks_rules.py writes, byte for byte. The check lives here
# because neither plugin may cite the other's private files.
# test-scope: plugins/session-flow/skills/audit-sessions/vendor/gitleaks/* plugins/corrections/tools/findings-buffer/vendor/gitleaks/*
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$SELF_DIR/.." && pwd)"
CANON="$REPO/plugins/session-flow/skills/audit-sessions/vendor/gitleaks"
COPY="$REPO/plugins/corrections/tools/findings-buffer/vendor/gitleaks"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

for f in gitleaks-rules.json LICENSE-gitleaks; do
  if cmp -s "$CANON/$f" "$COPY/$f"; then
    ok "corrections $f matches the session-flow copy"
  else
    fail "corrections $f differs from the session-flow copy"
  fi
done

test_harness::report
