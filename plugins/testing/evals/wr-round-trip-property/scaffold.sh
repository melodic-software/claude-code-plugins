#!/usr/bin/env bash
# A Python config loader with format_duration and parse_duration, a reverse pair, and no tests yet.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main src tests docs pyproject.toml
mkdir -p src tests docs
printf '[project]\nname = "loader"\nversion = "0.1.0"\n\n[project.optional-dependencies]\ntest = ["pytest", "hypothesis"]\n' >pyproject.toml
cat >docs/testing.md <<'EOF'
# Testing

- Framework: pytest, with hypothesis for property tests.
- Tests live in `tests/test_<module>.py`.
EOF
cat >src/__init__.py <<'EOF'
EOF
cat >src/durations.py <<'EOF'
import re


def format_duration(seconds: int) -> str:
    hours, rest = divmod(seconds, 3600)
    minutes, secs = divmod(rest, 60)
    parts = [f"{hours}h" if hours else "", f"{minutes}m" if minutes else "", f"{secs}s" if secs else ""]
    return "".join(parts) or "0s"


def parse_duration(text: str) -> int:
    match = re.fullmatch(r"(?:(\d+)h)?(?:(\d+)m)?(?:(\d+)s)?", text)
    if not match or not text:
        raise ValueError(text)
    hours, minutes, secs = (int(group or 0) for group in match.groups())
    return hours * 3600 + minutes * 60 + secs
EOF
g add -A
g commit -q -m "duration helpers"
