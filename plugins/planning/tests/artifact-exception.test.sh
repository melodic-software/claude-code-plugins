#!/usr/bin/env bash
# Contract test: the rendered-views contract names the brainstorm, design and
# plan views as the planning Artifact exception and keeps the PRD and interview
# views out of it, and the planning rendered-view reference reports the
# session-written views as `file`, never as the lane's publishing default.
set -uo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_DIR="$(cd "$PLUGIN_DIR/../.." && pwd)"
CONTRACT="$REPO_DIR/docs/contracts/rendered-views/README.md"
REFERENCE="$PLUGIN_DIR/reference/rendered-view.md"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

if grep -q "The planning views are the third exception: the brainstorm, design and plan views" "$CONTRACT"; then
  ok "the contract names the brainstorm, design and plan views as the Artifact exception"
else
  fail "the contract no longer names the brainstorm, design and plan views as the Artifact exception"
fi

if grep -q "PRD and interview views are not part of this exception" "$CONTRACT"; then
  ok "the contract keeps the PRD and interview views out of the exception"
else
  fail "the contract no longer keeps the PRD and interview views out of the exception"
fi

if grep -qF "the report line with \`file\` in place of the medium" "$REFERENCE" \
  && grep -qF "\`view: file (plugin default)\`" "$REFERENCE"; then
  ok "the reference reports a published-default session-written view as file"
else
  fail "the reference does not report a session-written view as file when the medium publishes"
fi

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]
