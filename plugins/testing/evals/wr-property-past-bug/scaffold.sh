#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main src tests pyproject.toml
mkdir -p src tests
printf '[project]\nname = "blog"\nversion = "0.1.0"\n\n[project.optional-dependencies]\ntest = ["pytest", "hypothesis"]\n\n[tool.pytest.ini_options]\npythonpath = ["."]\n' >pyproject.toml
cat >src/__init__.py <<'EOF'
EOF
cat >src/slug.py <<'EOF'
import re


def slugify(title: str) -> str:
    """URL slug for a post title: lowercase ASCII letters and digits joined by single hyphens.

    Never returns an empty string: a title with no letters or digits gets "untitled".
    """
    words = re.findall(r"[a-z0-9]+", title.lower())
    return "-".join(words) or "untitled"
EOF
g add -A
g commit -q -m "slugify"
