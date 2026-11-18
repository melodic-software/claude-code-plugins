#!/usr/bin/env bash
# test-scope: plugins/markdown-format/git-hooks/lefthook-remote.yml plugins/markdown-format/git-hooks/entries.json plugins/markdown-format/lib/git-hooks/install.mjs plugins/markdown-format/git-hooks/format.sh plugins/markdown-format/git-hooks/lint.sh .lefthook/*/markdown-format-* .lefthook/remote-entry.sh lefthook-remote.yml lib/git-hooks/lefthook-remote-harness.sh .github/scripts/pr-require-checks/install-lefthook.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/git-hooks/lefthook-remote-harness.sh
. "$HERE/../../../lib/git-hooks/lefthook-remote-harness.sh"

lr_static
lr_e2e_start || lr_done
lr_require_tools markdownlint-cli2

printf '{ "config": { "default": true, "MD013": false } }\n' >"$REPO/.markdownlint-cli2.jsonc"
git -C "$REPO" add -A
lr_commit config
lr_expect_pass "a commit of the opting-in config passes"

printf '# T\n\ntrailing   \n' >"$REPO/a.md"
git -C "$REPO" add a.md
lr_commit format
lr_expect_pass "format: a staged unformatted file commits"
expect "format: the committed file is the formatted one" $'# T\n\ntrailing' "$(git -C "$REPO" show HEAD:a.md)"
lr_skip_keeps markdown-format-remote-format b.md $'# T\n\ntrailing   \n' markdown-format-remote-lint

printf '# T\n\n<b>x</b>\n' >"$REPO/c.md"
git -C "$REPO" add c.md
lr_commit lint
lr_expect_block "lint: a finding on an added line blocks" markdown-format-remote-lint 'c\.md:3: MD033/no-inline-html'
lr_skip pre-commit markdown-format-remote-lint commit

printf '# D\n\ntext\n' >"$REPO/d.md"
git -C "$REPO" add d.md
lr_commit clean
lr_expect_pass "a clean file passes"

lr_done
