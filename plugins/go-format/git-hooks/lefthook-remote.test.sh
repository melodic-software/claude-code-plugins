#!/usr/bin/env bash
# test-scope: plugins/go-format/git-hooks/lefthook-remote.yml plugins/go-format/git-hooks/entries.json plugins/go-format/lib/git-hooks/install.mjs plugins/go-format/git-hooks/format.sh .lefthook/*/go-format-* .lefthook/remote-entry.sh lefthook-remote.yml lib/git-hooks/lefthook-remote-harness.sh .github/scripts/pr-require-checks/install-lefthook.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/git-hooks/lefthook-remote-harness.sh
. "$HERE/../../../lib/git-hooks/lefthook-remote-harness.sh"

lr_static
lr_e2e_start || lr_done
lr_require_tools goimports

printf 'package main\n\nimport (\n\t"os"\n\t"fmt"\n)\n\nfunc main() {  fmt.Println("hi", os.Args) }\n' >"$REPO/a.go"
git -C "$REPO" add a.go
lr_commit format
lr_expect_pass "format: a staged unformatted file commits"
expect "format: the committed file is the formatted one" \
  $'package main\n\nimport (\n\t"fmt"\n\t"os"\n)\n\nfunc main() { fmt.Println("hi", os.Args) }' "$(git -C "$REPO" show HEAD:a.go)"
lr_skip_keeps go-format-remote-format b.go $'package main\n\nfunc  b() {}\n'

printf 'package main\n\nfunc main() {\n\tfmt.Println("hi"\n}\n' >"$REPO/bad.go"
git -C "$REPO" add bad.go
lr_commit broken
lr_expect_block "format: a file goimports cannot parse blocks, naming its line" go-format-remote-format "bad\.go:4: missing ','"
lr_skip pre-commit go-format-remote-format commit

printf 'package main\n\nfunc c() {}\n' >"$REPO/c.go"
git -C "$REPO" add c.go
lr_commit clean
lr_expect_pass "a formatted file passes"

lr_done
