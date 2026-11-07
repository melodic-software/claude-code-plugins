#!/usr/bin/env bash
# A Python-only repository (pyproject.toml and pytest, no package.json, no .csproj) with a
# normalize_tags function and no tests for it.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main src tests pyproject.toml
mkdir -p src tests
printf '[project]\nname = "tags"\nversion = "0.1.0"\n\n[project.optional-dependencies]\ntest = ["pytest", "hypothesis"]\n' >pyproject.toml
cat >src/__init__.py <<'EOF'
EOF
cat >src/tags.py <<'EOF'
def normalize_tags(tags: list[str]) -> list[str]:
    """Lowercases, deduplicates and sorts a list of tags."""
    return sorted({tag.strip().lower() for tag in tags if tag.strip()})
EOF
cat >tests/test_smoke.py <<'EOF'
def test_imports():
    import src.tags  # noqa: F401
EOF
g add -A
g commit -q -m "tags"
