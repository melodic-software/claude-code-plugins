#!/usr/bin/env bash
# A Vitest test that reads a tracked component's source text, beside that component.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/audit-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main app test
au_copy corpus/js-vitest/bad/vitest-pitch-detail-source-order.test.ts.fixture test/pitch-detail.test.ts
mkdir -p app
printf 'export function PitchDetail() {\n  return (\n    <main>\n      <ContentPlan />\n      <Videos />\n    </main>\n  );\n}\n' >app/pitch-detail.tsx
au_commit
