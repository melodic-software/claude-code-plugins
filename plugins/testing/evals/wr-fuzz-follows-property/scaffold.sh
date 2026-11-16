#!/usr/bin/env bash
# A Python package with a duration parser and formatter, Hypothesis already in the test extras, and
# no test for either.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main src tests pyproject.toml
mkdir -p src tests
printf '[project]\nname = "timers"\nversion = "0.1.0"\n\n[project.optional-dependencies]\ntest = ["pytest", "hypothesis"]\n\n[tool.pytest.ini_options]\npythonpath = ["."]\n' >pyproject.toml
cat >src/__init__.py <<'EOF'
EOF
cat >src/duration.py <<'EOF'
import re

_PART = re.compile(r"(\d+)([hms])")
_UNIT = {"h": 3600, "m": 60, "s": 1}


def parse_duration(text: str) -> int:
    """Seconds in a duration such as '1h30m' or '45s'.

    Malformed text raises ValueError; no other exception escapes.
    """
    if not text or _PART.sub("", text):
        raise ValueError(f"not a duration: {text!r}")
    return sum(int(n) * _UNIT[u] for n, u in _PART.findall(text))


def format_duration(seconds: int) -> str:
    """The shortest duration text for a non-negative number of seconds, such as '1h30m'."""
    if seconds < 0:
        raise ValueError("negative duration")
    h, rest = divmod(seconds, 3600)
    m, s = divmod(rest, 60)
    out = "".join(f"{n}{u}" for n, u in ((h, "h"), (m, "m"), (s, "s")) if n)
    return out or "0s"
EOF
g add -A
g commit -q -m "duration parsing"
