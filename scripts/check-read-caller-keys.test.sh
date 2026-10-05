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
SUT_MJS="$SCRIPT_DIR/check-read-caller-keys.mjs"
POLICY_DIR="$SCRIPT_DIR/../.github/standards/runner-policy"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

# mk_tree <out-var>: a key-free read workflow, a write workflow that takes the
# key, a read-only lane caller and a write-only lane caller.
mk_tree() {
  local dir
  fixture_tree::build "$1" --sut "$SUT_SRC" --sut "$SUT_MJS" --label read-caller-keys || return 1
  dir="${!1}"
  mkdir -p "$dir/.github/workflows" "$dir/.github/standards/runner-policy"
  cp "$POLICY_DIR/package.json" "$dir/.github/standards/runner-policy/"
  ln -s "$POLICY_DIR/node_modules" "$dir/.github/standards/runner-policy/node_modules"
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
READ=.github/workflows/pr-run-activity-read.yml
WRITE=.github/workflows/pr-run-activity-write.yml
# shellcheck disable=SC2016  # a literal workflow expression, never expanded
KEY_LINE='      app-private-key: ${{ secrets.AUTOMATION_LANES_APP_PRIVATE_KEY }}'

run_case "a read caller passing only the OAuth token passes" 0 ":" "(1 caller(s))"

run_case "a read caller that passes the App key fails" 1 \
  "printf '%s\n' '$KEY_LINE' >>$CALLER" \
  "$CALLER:11: references the App key in a run that reaches $READ"

run_case "a read caller that mints from the key secret itself fails" 1 \
  "printf '  mint:\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: actions/create-github-app-token@v3\n        with:\n          private-key: \${{ secrets.KEY }}\n' >>$CALLER" \
  "$CALLER:16: references the App key"

run_case "a lane mixing read and write activities in one caller fails" 1 \
  "printf '  simplify:\n    uses: ./$WRITE\n    secrets:\n%s\n' '$KEY_LINE' >>$CALLER" \
  "$CALLER:14: references the App key" "$WRITE:4: references the App key"

run_case "a key reached through a nested local reusable workflow fails" 1 \
  "printf 'on: workflow_call\njobs:\n  write:\n    uses: \"./$WRITE\"\n' >.github/workflows/helper.yml &&
   printf '  helper:\n    uses: ./.github/workflows/helper.yml\n' >>$CALLER" \
  "$WRITE:12: references the App key in a run that reaches $READ"

run_case "a parent that calls the write workflow and a reusable reaching the read one fails" 1 \
  "printf 'on: workflow_call\njobs:\n  review:\n    uses: ./$CALLER\n' >.github/workflows/middle.yml &&
   printf 'on: pull_request\njobs:\n  middle:\n    uses: ./.github/workflows/middle.yml\n  write:\n    uses: ./$WRITE\n    secrets:\n%s\n' '$KEY_LINE' >.github/workflows/top.yml" \
  ".github/workflows/top.yml:8: references the App key"

run_case "a folded uses path to the read workflow is still a caller" 1 \
  "printf 'on: push\njobs:\n  a:\n    uses: >-\n      ./$READ\n    secrets:\n%s\n' '$KEY_LINE' >.github/workflows/folded.yml" \
  ".github/workflows/folded.yml:7: references the App key"

run_case "a quoted read workflow reference is still a caller" 1 \
  "printf 'on: push\njobs:\n  a:\n    uses: \"./$READ\"\n    secrets:\n      app-private-key: x\n' >.github/workflows/quoted.yml" \
  ".github/workflows/quoted.yml:6: references the App key"

run_case "a lower-case App key secret name fails" 1 \
  "printf '      other: \${{ secrets.automation_lanes_app_private_key }}\n' >>$CALLER" \
  "$CALLER:11: references the App key"

run_case "a secret expression on a shell comment line of a run block fails" 1 \
  "printf '  echo:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: |\n          echo hi\n          # \${{ secrets.AUTOMATION_LANES_APP_PRIVATE_KEY }}\n' >>$CALLER" \
  "$CALLER:16: references the App key"

run_case "a full-path call to the read workflow is a caller, in any case" 1 \
  "printf 'on: push\njobs:\n  a:\n    uses: Melodic-Software/Claude-Code-Plugins/$READ@main\n    secrets:\n      app-private-key: x\n' >.github/workflows/full.yml" \
  ".github/workflows/full.yml:6: references the App key"

run_case "a quoted or spaced private-key input key fails" 1 \
  "printf '      \"private-key\": x\n  mint:\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: actions/create-github-app-token@v3\n        with:\n          private-key : y\n' >>$CALLER" \
  "$CALLER:11: references the App key" "$CALLER:17: references the App key"

run_case "a read caller passing a secret off the allowlist fails" 1 \
  "printf '      other: \${{ secrets.DEPLOY_TOKEN }}\n' >>$CALLER" \
  "$CALLER:11: reads secrets.DEPLOY_TOKEN, which is not on the read-run allowlist"

run_case "secrets: inherit in a read caller fails" 1 \
  "sed -i 's/^    secrets:\$/    secrets: inherit/; /claude-code-oauth-token/d' $CALLER" \
  "$CALLER:9: passes secrets: inherit"

run_case "toJSON(secrets) in a read caller's run fails" 1 \
  "printf '  dump:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo \"\${{ toJSON(secrets) }}\"\n' >>$CALLER" \
  "$CALLER:14: reads every secret through toJSON(secrets)"

run_case "a computed secret name in a read caller's run fails" 1 \
  "printf '  pick:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo \"\${{ secrets[format(\\\"{0}_KEY\\\", vars.P)] }}\"\n' >>$CALLER" \
  "$CALLER:14: reads a secret by a computed name"

run_case "a workflow that does not parse fails" 1 \
  "printf 'jobs: [unclosed\n' >.github/workflows/broken.yml" \
  ".github/workflows/broken.yml: does not parse as YAML"

run_case "a read workflow that names id-token fails" 1 \
  "printf '      id-token: write\n' >>$READ" \
  "$READ:14: the read workflow names id-token"

run_case "a read workflow that references the key fails" 1 \
  "printf '      app-private-key:\n        required: true\n' >>$READ" \
  "$READ:14: references the App key"

run_case "a missing read workflow fails" 1 \
  "rm $READ" "$READ: missing"

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
