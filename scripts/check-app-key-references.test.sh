#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT_SRC="$SCRIPT_DIR/check-app-key-references.sh"

# shellcheck source=lib/test-harness.sh
. "$SCRIPT_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SCRIPT_DIR/lib/fixture-tree.sh"

WORKFLOW=.github/workflows/pr-refine.yml
ACTION=.github/actions/do-thing/action.yml

mk_tree() {
  local dir
  fixture_tree::build "$1" --sut "$SUT_SRC" --label app-key-references || return 1
  dir="${!1}"
  mkdir -p "$dir/.github/workflows" "$dir/.github/actions/do-thing" "$dir/docs"
  cat >"$dir/$WORKFLOW" <<'EOF'
on: pull_request
jobs:
  simplify:
    permissions:
      id-token: write
    uses: ./.github/workflows/pr-run-activity-write.yml
EOF
  cat >"$dir/$ACTION" <<'EOF'
runs:
  using: composite
  steps:
    - run: echo hi
      shell: bash
EOF
  cat >"$dir/.github/workflows/release.yml" <<'EOF'
on: push
jobs:
  publish:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/create-github-app-token@v3
        with:
          client-id: ${{ vars.PLUGIN_RELEASE_APP_CLIENT_ID }}
          private-key: ${{ secrets.PLUGIN_RELEASE_APP_PRIVATE_KEY }}
EOF
  printf 'AUTOMATION_LANES_APP_PRIVATE_KEY, app-private-key, AUTOMATION_LANES_APP_CLIENT_ID\n' >"$dir/docs/adr.md"
}

run_case() { test_harness::check_case mk_tree check-app-key-references.sh "$@"; }

MSG="references the lanes App key or client id"

run_case "no lanes key or client id passes; another App's private-key: mint and docs are out of scope" 0 ":" \
  "no workflow or action references the lanes App key or client id"

# shellcheck disable=SC2016  # literal workflow expressions, never expanded
run_case "the lanes key secret name in a workflow fails" 1 \
  "printf '    secrets:\n      key: \${{ secrets.AUTOMATION_LANES_APP_PRIVATE_KEY }}\n' >>$WORKFLOW" \
  "$WORKFLOW:8: $MSG"

run_case "a lower-case lanes key secret name fails" 1 \
  "printf '    # secrets.automation_lanes_app_private_key\n' >>$WORKFLOW" \
  "$WORKFLOW:7: $MSG"

run_case "an app-private-key secret pass in a workflow fails" 1 \
  "printf '    secrets:\n      app-private-key: x\n' >>$WORKFLOW" \
  "$WORKFLOW:8: $MSG"

run_case "an app-private-key input in an action fails" 1 \
  "printf 'inputs:\n  app-private-key:\n    required: true\n' >>$ACTION" \
  "$ACTION:7: $MSG"

# shellcheck disable=SC2016  # literal workflow expressions, never expanded
run_case "a lanes App client id in a workflow mint fails" 1 \
  "printf '  mint:\n    runs-on: ubuntu-24.04\n    steps:\n      - uses: actions/create-github-app-token@v3\n        with:\n          client-id: \${{ vars.AUTOMATION_LANES_APP_CLIENT_ID }}\n          private-key: \${{ secrets.OTHER_KEY }}\n' >>$WORKFLOW" \
  "$WORKFLOW:12: $MSG"

run_case "a lanes App client id in an action fails" 1 \
  "printf '      env:\n        ID: \${{ vars.automation_lanes_app_client_id }}\n' >>$ACTION" \
  "$ACTION:7: $MSG"

tree=""
if mk_tree tree; then
  printf '      app-private-key: x\n' >>"$tree/$ACTION"
  test_harness::assert_discover_quiet "$tree/scripts/check-app-key-references.sh"
else
  fail "discover mode: fixture build failed"
fi

test_harness::assert_unknown_mode "$SUT_SRC"

test_harness::report
