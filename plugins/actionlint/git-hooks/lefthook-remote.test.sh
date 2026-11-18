#!/usr/bin/env bash
# test-scope: plugins/actionlint/git-hooks/lefthook-remote.yml plugins/actionlint/git-hooks/entries.json plugins/actionlint/lib/git-hooks/install.mjs plugins/actionlint/git-hooks/lint.sh .lefthook/*/actionlint-* .lefthook/remote-entry.sh lefthook-remote.yml lib/git-hooks/lefthook-remote-harness.sh .github/scripts/pr-require-checks/install-lefthook.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/git-hooks/lefthook-remote-harness.sh
. "$HERE/../../../lib/git-hooks/lefthook-remote-harness.sh"

lr_static
lr_e2e_start || lr_done
lr_require_tools actionlint

mkdir -p "$REPO/.github/workflows"
printf "seed\n" >"$REPO/seed.txt"
git -C "$REPO" add -A
lr_commit config
lr_expect_pass "a commit of the opting-in config passes"

# shellcheck disable=SC2016 # a workflow expression, not a substitution
printf 'name: bad\non: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo "${{ steps.missing.outputs.x }}"\n' >"$REPO/.github/workflows/bad.yml"
git -C "$REPO" add .github/workflows/bad.yml
lr_commit lint
lr_expect_block "lint: a finding on an added line blocks" actionlint-remote-lint '\.github/workflows/bad\.yml:7: property "missing" is not defined'
lr_skip pre-commit actionlint-remote-lint commit

printf 'name: ok\non: push\njobs:\n  build:\n    runs-on: ubuntu-latest\n    steps:\n      - run: echo ok\n' >"$REPO/.github/workflows/ok.yml"
git -C "$REPO" add .github/workflows/ok.yml
lr_commit clean
lr_expect_pass "a clean file passes"

lr_done
