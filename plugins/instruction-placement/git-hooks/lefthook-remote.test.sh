#!/usr/bin/env bash
# test-scope: plugins/instruction-placement/git-hooks/lefthook-remote.yml plugins/instruction-placement/git-hooks/entries.json plugins/instruction-placement/lib/git-hooks/install.mjs plugins/instruction-placement/git-hooks/index-check.sh plugins/instruction-placement/scripts/render-index.sh .lefthook/*/instruction-placement-* .lefthook/remote-entry.sh lefthook-remote.yml lib/git-hooks/lefthook-remote-harness.sh .github/scripts/pr-require-checks/install-lefthook.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../lib/git-hooks/lefthook-remote-harness.sh
. "$HERE/../../../lib/git-hooks/lefthook-remote-harness.sh"

lr_static
lr_e2e_start || lr_done

add_rule() {
  mkdir -p "$REPO/.claude/rules"
  printf -- '---\npaths:\n  - "**/*.cs"\n---\n\n# %s rule\n' "$1" >"$REPO/.claude/rules/$1.md"
  git -C "$REPO" add ".claude/rules/$1.md"
}
render() {
  bash "$PLUGIN/scripts/render-index.sh" write --file "$REPO/AGENTS.md" --root "$REPO" >/dev/null
  git -C "$REPO" add AGENTS.md
}
printf '# Project\n\n<!-- BEGIN GENERATED: instruction-placement rules index -->\n<!-- END GENERATED: instruction-placement rules index -->\n' >"$REPO/AGENTS.md"
mkdir -p "$REPO/src"
printf 'class X {}\n' >"$REPO/src/a.cs"
git -C "$REPO" add src
add_rule csharp
render
lr_commit index
lr_expect_pass "index-check: a rule with its regenerated index passes"

add_rule other
lr_commit rule
lr_expect_block "index-check: a staged rule the index does not list blocks" instruction-placement-remote-index-check \
  'AGENTS\.md:[0-9]+: the rules index no longer matches \.claude/rules/'
lr_skip pre-commit instruction-placement-remote-index-check commit

add_rule third
render
lr_commit regenerated
lr_expect_pass "index-check: a new rule with the regenerated index passes"

printf 'x\n' >"$REPO/notes.txt"
git -C "$REPO" add notes.txt
lr_commit unrelated
lr_expect_pass "index-check: a commit touching neither a rule nor the index passes"

lr_done
