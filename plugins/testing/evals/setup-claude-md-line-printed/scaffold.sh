#!/usr/bin/env bash
# A Python repository with a root CLAUDE.md and one tracked pytest file.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main CLAUDE.md pyproject.toml tests
mkdir -p tests
cat >CLAUDE.md <<'EOF'
# Orders service

Run the tests with `pytest`.
EOF
printf '[project]\nname = "orders"\nversion = "0.1.0"\n\n[tool.ruff.lint]\nselect = ["E", "F", "PLR0124", "PT011"]\n' >pyproject.toml
printf 'def test_adds():\n    assert 1 + 1 == 2\n' >tests/test_math.py
g add -A
g commit -q -m "orders"
