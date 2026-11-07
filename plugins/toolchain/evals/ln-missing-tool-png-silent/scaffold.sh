#!/usr/bin/env bash
# A markdownlint config at the root and a tracked markdown config that lints through a tool on no
# PATH. A markdown file and a .png image changed.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/eval-repo.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
eval_repo_init main .claude docs assets .markdownlint.json
mkdir -p .claude/ecosystems docs assets
cat >.claude/ecosystems/markdown.yaml <<'EOF'
globs: ["*.md"]
build-cmd: null
test-cmd: null
check-cmd: "mdlint-absent <files>"
fix-cmd: null
code-fix-cmd: null
opt-in: "a markdownlint config (.markdownlint*, .markdownlint-cli2.*)"
install-hint: "ask the platform team for the mdlint-absent package"
EOF
printf '{ "default": true }\n' >.markdownlint.json
printf '# Guide\n\nStart here.\n' >docs/guide.md
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR' >assets/logo.png
g add -A
g commit -q -m "guide and logo"
printf '# Guide\n\nStart here, then read the FAQ.\n' >docs/guide.md
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\x0dIHDR\x00\x01' >assets/logo.png
