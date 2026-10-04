#!/usr/bin/env bash
# Black-box contract test for check-read-caller-keys.sh.
#
# Self-contained and cwd-independent: builds a throwaway tree with fixture
# workflows, runs the checker against it, and asserts on exit code and output.
# Mutates only its own mktemp dir. The SUT resolves the repository root
# relative to its own location, so the fixture tree carries a copy of it under
# scripts/.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-read-caller-keys.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

# mk_tree <out-var>: a key-free read workflow, a write workflow that takes the
# key, a read-only lane caller and a write-only lane caller.
mk_tree() {
  local dir
  fixture_tree::build "$1" --sut "$SUT_SRC" --label read-caller-keys || return 1
  dir="${!1}"
  mkdir -p "$dir/.github/workflows"
  cat >"$dir/.github/workflows/pr-run-activity-read.yml" <<'EOF'
on:
  workflow_call:
    secrets:
      claude-code-oauth-token:
        required: false
jobs:
  run:
    permissions:
      contents: read
      pull-requests: read
    runs-on: ubuntu-24.04
    steps:
      - run: echo read
EOF
  cat >"$dir/.github/workflows/pr-run-activity-write.yml" <<'EOF'
on:
  workflow_call:
    secrets:
      app-private-key:
        required: true
jobs:
  run:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/create-github-app-token@bcd2ba49218906704ab6c1aa796996da409d3eb1 # v3.2.0
        with:
          private-key: ${{ secrets.app-private-key }}
EOF
  cat >"$dir/.github/workflows/pr-review.yml" <<'EOF'
on: pull_request
jobs:
  claude:
    # A caller of this file must not pass app-private-key.
    uses: ./.github/workflows/pr-run-activity-read.yml
    with:
      lane: pr-review
      activity: claude
    secrets:
      claude-code-oauth-token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
EOF
  cat >"$dir/.github/workflows/pr-refine.yml" <<'EOF'
on: pull_request
jobs:
  simplify:
    uses: ./.github/workflows/pr-run-activity-write.yml
    secrets:
      app-private-key: ${{ secrets.AUTOMATION_LANES_APP_PRIVATE_KEY }}
EOF
}

# run_case <label> <expected-rc> <setup> [<must-name>...]
# <setup> runs inside the fixture root; each <must-name> must appear in the
# output of the run.
run_case() {
  local label="$1" expected="$2" setup="$3"
  shift 3
  local tree out rc s
  mk_tree tree || {
    fail "$label: fixture build failed"
    return
  }
  (cd "$tree" && eval "$setup") || {
    fail "$label: setup failed"
    return
  }
  out="$(bash "$tree/scripts/check-read-caller-keys.sh" --check 2>&1)"
  rc=$?
  if [[ $rc -ne $expected ]]; then
    fail "$label: expected rc=$expected, got rc=$rc: $out"
    return
  fi
  for s in "$@"; do
    if ! grep -qF -- "$s" <<<"$out"; then
      fail "$label: '$s' not named in output: $out"
      return
    fi
  done
  ok "$label"
}

CALLER=.github/workflows/pr-review.yml

run_case "a read caller passing only the OAuth token passes" 0 ":" "(1 caller(s))"

run_case "a read caller that passes the App key fails" 1 \
  "printf '      app-private-key: \${{ secrets.AUTOMATION_LANES_APP_PRIVATE_KEY }}\n' >>$CALLER" \
  "$CALLER:11: calls .github/workflows/pr-run-activity-read.yml and references the App key"

run_case "a read caller that mints from the key secret itself fails" 1 \
  "printf '  mint:\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: actions/create-github-app-token@v3\n        with:\n          private-key: \${{ secrets.KEY }}\n' >>$CALLER" \
  "$CALLER:16: calls"

run_case "a lane mixing read and write activities in one caller fails" 1 \
  "printf '  simplify:\n    uses: ./.github/workflows/pr-run-activity-write.yml\n    secrets:\n      app-private-key: \${{ secrets.AUTOMATION_LANES_APP_PRIVATE_KEY }}\n' >>$CALLER" \
  "$CALLER:14: calls" \
  ".github/workflows/pr-run-activity-write.yml:4: references the App key in the run of $CALLER"

run_case "a key reached through a nested local reusable workflow fails" 1 \
  "printf 'on: workflow_call\njobs:\n  write:\n    uses: \"./.github/workflows/pr-run-activity-write.yml\"\n' >.github/workflows/helper.yml &&
   printf '  helper:\n    uses: ./.github/workflows/helper.yml\n' >>$CALLER" \
  ".github/workflows/pr-run-activity-write.yml:12: references the App key in the run of $CALLER"

run_case "a quoted read workflow reference is still a caller" 1 \
  "printf 'on: push\njobs:\n  a:\n    uses: \"./.github/workflows/pr-run-activity-read.yml\"\n    secrets:\n      app-private-key: x\n' >.github/workflows/quoted.yml" \
  ".github/workflows/quoted.yml:6: calls"

run_case "a read workflow that names id-token fails" 1 \
  "printf '      id-token: write\n' >>.github/workflows/pr-run-activity-read.yml" \
  ".github/workflows/pr-run-activity-read.yml:14: the read workflow names id-token"

run_case "a read workflow that references the key fails through its caller" 1 \
  "printf '      app-private-key:\n        required: true\n' >>.github/workflows/pr-run-activity-read.yml" \
  ".github/workflows/pr-run-activity-read.yml:14: references the App key in the run of $CALLER"

run_case "a missing read workflow fails" 1 \
  "rm .github/workflows/pr-run-activity-read.yml" \
  ".github/workflows/pr-run-activity-read.yml: missing"

run_case "a write-only caller may pass the key" 0 \
  "rm $CALLER" "(0 caller(s))"

# Findings on stderr only; the clean statement on stdout only.
tree=""
if mk_tree tree; then
  printf '      app-private-key: x\n' >>"$tree/$CALLER"
  stdout="$(bash "$tree/scripts/check-read-caller-keys.sh" 2>/dev/null)"
  rc=$?
  if [[ $rc -eq 1 && -z "$stdout" ]]; then
    ok "discover mode exits 1 with nothing on stdout"
  else
    fail "discover mode should exit 1 with an empty stdout (rc=$rc): $stdout"
  fi
else
  fail "discover mode: fixture build failed"
fi

bash "$SUT_SRC" --bogus >/dev/null 2>&1
rc=$?
if [[ $rc -eq 2 ]]; then
  ok "unknown mode exits 2"
else
  fail "unknown mode should exit 2 (rc=$rc)"
fi

test_harness::report
