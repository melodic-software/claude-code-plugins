#!/usr/bin/env bash
# test-scope: plugins/javascript-format/git-hooks/lefthook-remote.yml plugins/javascript-format/git-hooks/entries.json plugins/javascript-format/lib/git-hooks/install.mjs plugins/javascript-format/git-hooks/format.sh plugins/javascript-format/git-hooks/lint.sh .lefthook/*/javascript-format-* .lefthook/remote-entry.sh lefthook-remote.yml lib/git-hooks/lefthook-remote-harness.sh .github/scripts/pr-require-checks/install-lefthook.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/git-hooks/lefthook-remote-harness.sh
. "$HERE/../../../lib/git-hooks/lefthook-remote-harness.sh"

lr_static
lr_e2e_start || lr_done
lr_require_tools biome

printf '{}\n' >"$REPO/biome.json"
git -C "$REPO" add -A
lr_commit config
lr_expect_pass "a commit of the opting-in config passes"

printf 'export const a=1\n' >"$REPO/a.ts"
git -C "$REPO" add a.ts
lr_commit format
lr_expect_pass "format: a staged unformatted file commits"
expect "format: the committed file is the formatted one" $'export const a = 1;' "$(git -C "$REPO" show HEAD:a.ts)"
lr_skip_keeps javascript-format-remote-format b.ts $'export const a=1\n'

printf 'export const c = 1;\n\nconst unusedVar = 1;\n' >"$REPO/c.ts"
git -C "$REPO" add c.ts
lr_commit lint
lr_expect_block "lint: a finding on an added line blocks" javascript-format-remote-lint 'c\.ts:3: lint/correctness/noUnusedVariables'
lr_skip pre-commit javascript-format-remote-lint commit

printf 'export const d = 1;\n' >"$REPO/d.ts"
git -C "$REPO" add d.ts
lr_commit clean
lr_expect_pass "a clean file passes"

lr_done
