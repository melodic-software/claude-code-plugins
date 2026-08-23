#!/usr/bin/env bash
# Unit tests for check-queue-front-matter.sh.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-queue-front-matter.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

new_queue() {
  mktemp -d
}

run_check() (
  bash "$SCRIPT" "$1"
)

# --- valid item passes -------------------------------------------------------
q="$(new_queue)"
cat >"$q/20260812-sample.md" <<'EOF'
---
id: 20260812-sample
title: Sample item
status: unclaimed
created: 2026-08-12T12:00:00Z
producer: test-fixture
---
Body
EOF
if run_check "$q" >/dev/null 2>&1; then
  ok "valid item passes"
else
  fail "valid item should pass"
fi

# --- missing front matter fails ----------------------------------------------
q="$(new_queue)"
printf 'No front matter here\n' >"$q/20260812-bad.md"
if run_check "$q" >/dev/null 2>&1; then
  fail "missing front matter should fail"
else
  ok "missing front matter fails"
fi

# --- invalid status fails ----------------------------------------------------
q="$(new_queue)"
cat >"$q/20260812-open.md" <<'EOF'
---
id: 20260812-open
title: Bad status
status: open
created: 2026-08-12T12:00:00Z
producer: test-fixture
---
EOF
if run_check "$q" >/dev/null 2>&1; then
  fail "invalid status should fail"
else
  ok "invalid status fails"
fi

# --- id stem mismatch fails --------------------------------------------------
q="$(new_queue)"
cat >"$q/20260812-wrong.md" <<'EOF'
---
id: other-id
title: Mismatch
status: unclaimed
created: 2026-08-12T12:00:00Z
producer: test-fixture
---
EOF
if run_check "$q" >/dev/null 2>&1; then
  fail "id/filename mismatch should fail"
else
  ok "id stem mismatch fails"
fi

# --- README.md is ignored ----------------------------------------------------
q="$(new_queue)"
printf '# readme\n' >"$q/README.md"
cat >"$q/20260812-only.md" <<'EOF'
---
id: 20260812-only
title: Only item
status: done
created: 2026-08-12T12:00:00Z
producer: test-fixture
---
EOF
if run_check "$q" >/dev/null 2>&1; then
  ok "README.md ignored"
else
  fail "README should be ignored: valid sole item should pass"
fi

test_harness::report
