#!/usr/bin/env bash
# A Vitest test that compares a constant to its own literal, beside the module it imports.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/audit-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main src test
au_copy corpus/js-vitest/bad/vitest-post-limit-restated.test.ts.fixture test/post-limit.test.ts
mkdir -p src
printf 'export const X_POST_CHARACTER_LIMIT = 280;\n\nexport function validatePost(text: string) {\n  return { ok: text.length <= X_POST_CHARACTER_LIMIT };\n}\n' >src/post.ts
au_commit
