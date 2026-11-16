#!/usr/bin/env bash
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main src tests pyproject.toml
mkdir -p src tests
printf '[project]\nname = "billing"\nversion = "0.1.0"\n\n[project.optional-dependencies]\ntest = ["pytest", "hypothesis"]\n\n[tool.pytest.ini_options]\npythonpath = ["."]\n' >pyproject.toml
cat >src/__init__.py <<'EOF'
EOF
cat >src/invoice.py <<'EOF'
from dataclasses import dataclass


@dataclass(frozen=True)
class Line:
    sku: str
    amount_cents: int
    currency: str


@dataclass(frozen=True)
class Invoice:
    currency: str
    lines: tuple[Line, ...]


def invoice_total(invoice: Invoice) -> int:
    """Total of the invoice's lines in cents.

    Every line must be in the invoice's currency; a line in another currency raises ValueError.
    Amounts are non-negative.
    """
    for line in invoice.lines:
        if line.currency != invoice.currency:
            raise ValueError(f"line {line.sku} is in {line.currency}, not {invoice.currency}")
    return sum(line.amount_cents for line in invoice.lines)
EOF
g add -A
g commit -q -m "invoice totals"
