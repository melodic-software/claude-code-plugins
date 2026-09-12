#!/usr/bin/env bash
# Unit tests for check-queue-front-matter.sh.
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SELF_DIR/check-queue-front-matter.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

# The builder assigns through a nameref, which shellcheck cannot follow;
# declaring the out-var here is what tells it (SC2154) the name is written.
q=""

new_queue() { # <out-var>
  fixture_tree::build "$1" --label queue
}

run_check() (
  bash "$SCRIPT" "$1"
)

# --- valid item passes -------------------------------------------------------
new_queue q
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
new_queue q
printf 'No front matter here\n' >"$q/20260812-bad.md"
if run_check "$q" >/dev/null 2>&1; then
  fail "missing front matter should fail"
else
  ok "missing front matter fails"
fi

# --- invalid status fails ----------------------------------------------------
new_queue q
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
new_queue q
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
new_queue q
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
