#!/usr/bin/env bash
# test-scope: .github/standards/runner-policy/package.json
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
permissions: {}
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

run_case "a read caller passing the pr-unblock role's Claude Code OAuth token passes" 0 \
  "printf '      other: \${{ secrets.PR_UNBLOCK_CLAUDE_CODE_OAUTH_TOKEN }}\n' >>$CALLER"

run_case "a read caller passing the pr-unblock role's Claude API key passes" 0 \
  "printf '      claude-api-key: \${{ secrets.PR_UNBLOCK_CLAUDE_API_KEY }}\n' >>$CALLER"

run_case "a read caller passing the maintenance role's Claude API key fails" 1 \
  "printf '      claude-api-key: \${{ secrets.MAINTENANCE_CLAUDE_API_KEY }}\n' >>$CALLER" \
  "$CALLER:11: reads secrets.MAINTENANCE_CLAUDE_API_KEY, which is not on the read-run allowlist"

run_case "a read caller passing another role's Claude API key fails" 1 \
  "printf '      claude-api-key: \${{ secrets.ISSUE_LANE_CLAUDE_API_KEY }}\n' >>$CALLER" \
  "$CALLER:11: reads secrets.ISSUE_LANE_CLAUDE_API_KEY, which is not on the read-run allowlist"

run_case "secrets: inherit in a read caller fails" 1 \
  "sed 's/^    secrets:\$/    secrets: inherit/; /claude-code-oauth-token/d' $CALLER >$CALLER.new && mv $CALLER.new $CALLER" \
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

# append_check_job <job> <ref>: appends to the read workflow, from line 15, a
# job holding id-token: write whose checkout step (line 20) checks out <ref>.
append_check_job() {
  printf '  %s:\n    permissions:\n      id-token: write\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: actions/checkout@v7\n        with:\n          ref: %s\n' \
    "$1" "$2" >>"$READ"
}
# rewrite <command...>: filters the read workflow through <command> in place.
rewrite() {
  "$@" <"$READ" >"$READ.tmp" && mv "$READ.tmp" "$READ"
}
# shellcheck disable=SC2016  # literal workflow expressions, never expanded
TIP='${{ github.event.repository.default_branch }}'
# shellcheck disable=SC2016
HEAD_REF='${{ github.event.pull_request.head.sha }}'

run_case "a read workflow that names id-token fails" 1 \
  "printf '      id-token: write\n' >>$READ" \
  "$READ:15: the read workflow names id-token outside its broker-check job"

run_case "id-token in the broker-check job that checks out the default branch tip passes" 0 \
  "append_check_job broker-check '$TIP'" "(1 caller(s))"

run_case "id-token in the run job still fails beside a broker-check job" 1 \
  "append_check_job broker-check '$TIP' && rewrite awk '{ print } NR == 11 { print \"      id-token: write\" }'" \
  "$READ:12: the read workflow names id-token outside its broker-check job"

run_case "id-token in a job with another name fails" 1 \
  "append_check_job broker-check-2 '$TIP'" \
  "$READ:17: the read workflow names id-token outside its broker-check job"

run_case "a broker-check job that checks out the PR head fails" 1 \
  "append_check_job broker-check '$HEAD_REF'" \
  "$READ:20: the broker-check job checks out something other than this repository's default branch tip"

run_case "a broker-check checkout of another repository fails" 1 \
  "append_check_job broker-check '$TIP' && printf '          repository: other/repo\n' >>$READ" \
  "$READ:20: the broker-check job checks out something other than this repository's default branch tip"

run_case "a broker-check job that is a reusable-workflow call fails" 1 \
  "printf '  broker-check:\n    permissions:\n      id-token: write\n    uses: ./.github/workflows/other.yml\n' >>$READ" \
  "$READ:16: the broker-check job must be steps, not a reusable-workflow call"

run_case "write-all on the read workflow's run job fails" 1 \
  "rewrite awk 'NR == 9 { print \"    permissions: write-all\" } NR < 9 || NR > 11'" \
  "$READ:9: grants permissions: write-all in a run that reaches $READ"

run_case "a read workflow with no top-level permissions fails" 1 \
  "rewrite grep -v '^permissions: {}\$'" \
  "$READ:1: the read workflow's top-level permissions is not {}"

run_case "a read workflow job with no permissions map fails" 1 \
  "rewrite awk 'NR < 9 || NR > 11'" \
  "$READ:8: job run has no explicit permissions map"

# append_scan_job [<environment>] [<private-key value>]: appends to the read
# workflow, from line 15, a scan job whose environment is on line 16 and whose
# open-lane-output step's private-key input is on line 23.
append_scan_job() {
  printf '  scan:\n    environment: %s\n    permissions:\n      contents: read\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: ./.base/.github/actions/open-lane-output\n        with:\n          private-key: %s\n' \
    "${1:-pr-pipeline-scan-carrier}" "${2:-\${{ secrets.scan-carrier-private-key \}\}}" >>"$READ"
}
# shellcheck disable=SC2016  # literal workflow expressions, never expanded
CARRIER='${{ secrets.scan-carrier-private-key }}'
# shellcheck disable=SC2016
PASS='${{ secrets.SCAN_CARRIER_PRIVATE_KEY }}'

run_case "the scan job's open step may take the scan-carrier key, under its environment" 0 \
  "append_scan_job" "(1 caller(s))"

run_case "a read caller may pass the scan-carrier key by name in its secrets map" 0 \
  "printf '      scan-carrier-private-key: %s\n' '$PASS' >>$CALLER && append_scan_job" "(1 caller(s))"

run_case "a read caller passing the scan-carrier key under another name fails" 1 \
  "printf '      other: %s\n' '$PASS' >>$CALLER && append_scan_job" \
  "$CALLER:11: reads secrets.SCAN_CARRIER_PRIVATE_KEY outside"

run_case "the scan-carrier key in a caller job that does not call the read workflow fails" 1 \
  "printf '  other:\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo hi\n        env:\n          K: %s\n' '$PASS' >>$CALLER && append_scan_job" \
  "$CALLER:16: reads secrets.SCAN_CARRIER_PRIVATE_KEY outside"

run_case "the scan-carrier key passed to the write workflow fails" 1 \
  "printf '  simplify:\n    uses: ./$WRITE\n    secrets:\n      scan-carrier-private-key: %s\n' '$PASS' >>$CALLER && append_scan_job" \
  "$CALLER:14: reads secrets.SCAN_CARRIER_PRIVATE_KEY outside"

run_case "the scan-carrier key in the read workflow's run job fails" 1 \
  "printf '        env:\n          K: %s\n' '$CARRIER' >>$READ && append_scan_job" \
  "$READ:16: reads secrets.scan-carrier-private-key outside"

run_case "the scan-carrier key in a second scan-job step fails" 1 \
  "append_scan_job && printf '      - run: echo hi\n        env:\n          K: %s\n' '$CARRIER' >>$READ" \
  "$READ:26: reads secrets.scan-carrier-private-key outside"

run_case "the open step reading the environment secret's own name, not the declared input, fails" 1 \
  "append_scan_job '' '$PASS'" \
  "$READ:23: references the App key" "$READ:23: reads secrets.SCAN_CARRIER_PRIVATE_KEY outside"

run_case "any other secret as the open step's private-key fails" 1 \
  "append_scan_job '' '\${{ secrets.DEPLOY_KEY }}'" \
  "$READ:23: references the App key" "$READ:23: reads secrets.DEPLOY_KEY, which is not on the read-run allowlist"

run_case "another environment on the scan job fails" 1 \
  "append_scan_job other-env" \
  "$READ:16: names an environment other than pr-pipeline-scan-carrier on the read workflow's scan job"

run_case "the carrier environment on any other job fails" 1 \
  "rewrite awk '{ print } NR == 8 { print \"    environment: pr-pipeline-scan-carrier\" }' && append_scan_job" \
  "$READ:9: names an environment other than pr-pipeline-scan-carrier"

run_case "an environment in a read caller fails" 1 \
  "printf '  deploy:\n    environment: pr-pipeline-scan-carrier\n    runs-on: ubuntu-24.04\n    steps:\n      - run: echo hi\n' >>$CALLER" \
  "$CALLER:12: names an environment other than pr-pipeline-scan-carrier"

run_case "a read workflow that references the key fails" 1 \
  "printf '      app-private-key:\n        required: true\n' >>$READ" \
  "$READ:15: references the App key"

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
