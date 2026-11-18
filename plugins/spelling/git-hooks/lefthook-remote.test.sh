#!/usr/bin/env bash
# test-scope: plugins/spelling/git-hooks/lefthook-remote.yml plugins/spelling/git-hooks/entries.json plugins/spelling/lib/git-hooks/install.mjs plugins/spelling/git-hooks/lint.sh plugins/spelling/config/default-typos.toml .lefthook/*/spelling-* .lefthook/remote-entry.sh lefthook-remote.yml lib/git-hooks/lefthook-remote-harness.sh .github/scripts/pr-require-checks/install-lefthook.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/git-hooks/lefthook-remote-harness.sh
. "$HERE/../../../lib/git-hooks/lefthook-remote-harness.sh"

lr_static
lr_e2e_start || lr_done
lr_require_tools typos

printf '[files]\n' >"$REPO/_typos.toml"
git -C "$REPO" add -A
lr_commit config
lr_expect_pass "a commit of the opting-in config passes"

printf 'an old teh line\n' >"$REPO/c.md" # spellchecker:disable-line
git -C "$REPO" add c.md
lr_commit lint
lr_expect_block "lint: a finding on an added line blocks" spelling-remote-lint 'c\.md:1: .*teh' # spellchecker:disable-line
lr_skip pre-commit spelling-remote-lint commit

printf 'a clean line\n' >"$REPO/d.md"
git -C "$REPO" add d.md
lr_commit clean
lr_expect_pass "a clean file passes"

lr_done
