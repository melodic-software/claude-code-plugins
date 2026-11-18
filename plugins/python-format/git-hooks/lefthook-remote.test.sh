#!/usr/bin/env bash
# test-scope: plugins/python-format/git-hooks/lefthook-remote.yml plugins/python-format/git-hooks/entries.json plugins/python-format/lib/git-hooks/install.mjs plugins/python-format/git-hooks/format.sh plugins/python-format/git-hooks/lint.sh .lefthook/*/python-format-* .lefthook/remote-entry.sh lefthook-remote.yml lib/git-hooks/lefthook-remote-harness.sh .github/scripts/pr-require-checks/install-lefthook.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/git-hooks/lefthook-remote-harness.sh
. "$HERE/../../../lib/git-hooks/lefthook-remote-harness.sh"

lr_static
lr_e2e_start || lr_done
lr_require_tools ruff

printf 'line-length = 88\n' >"$REPO/ruff.toml"
git -C "$REPO" add -A
lr_commit config
lr_expect_pass "a commit of the opting-in config passes"

printf 'x=1\n' >"$REPO/a.py"
git -C "$REPO" add a.py
lr_commit format
lr_expect_pass "format: a staged unformatted file commits"
expect "format: the committed file is the formatted one" $'x = 1' "$(git -C "$REPO" show HEAD:a.py)"
lr_skip_keeps python-format-remote-format b.py $'x=1\n'

printf 'print(undefined_name)\n' >"$REPO/c.py"
git -C "$REPO" add c.py
lr_commit lint
lr_expect_block "lint: a finding on an added line blocks" python-format-remote-lint 'c\.py:1: F821'
lr_skip pre-commit python-format-remote-lint commit

printf 'print(1)\n' >"$REPO/d.py"
git -C "$REPO" add d.py
lr_commit clean
lr_expect_pass "a clean file passes"

lr_done
