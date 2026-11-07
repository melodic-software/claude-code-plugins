#!/usr/bin/env bash
# A Python price parser that fails on thousands separators, one existing test, and a docs/testing.md
# that sets the test location and naming.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main src tests docs pyproject.toml
mkdir -p src tests docs
printf '[project]\nname = "prices"\nversion = "0.1.0"\n' >pyproject.toml
cat >docs/testing.md <<'EOF'
# Testing

- Framework: pytest with plain `assert`.
- Tests live in `tests/test_<module>.py`; name each test `test_<function>_<behavior>`.
EOF
cat >src/__init__.py <<'EOF'
EOF
cat >src/parser.py <<'EOF'
from decimal import Decimal


def parse_price(text: str) -> Decimal:
    """Parses a dollar amount such as "$12.50" into a Decimal."""
    return Decimal(text.strip().lstrip("$"))
EOF
cat >tests/test_parser.py <<'EOF'
from decimal import Decimal

from src.parser import parse_price


def test_parse_price_reads_dollars_and_cents():
    assert parse_price("$12.50") == Decimal("12.50")
EOF
g add -A
g commit -q -m "price parser"
