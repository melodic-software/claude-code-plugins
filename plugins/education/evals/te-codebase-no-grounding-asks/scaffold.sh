#!/usr/bin/env bash
# Seeds a small repository with guidance files and no authentication code anywhere.
set -euo pipefail

git init -q .
mkdir -p src tests
cat >AGENTS.md <<'EOF'
# csv-report

A command-line tool that turns CSV exports into Markdown reports. `src/cli.py` parses arguments,
`src/render.py` builds the tables. Run tests with `python -m pytest tests`.
EOF
cat >README.md <<'EOF'
# csv-report

Usage: `python -m src.cli orders.csv --out report.md`
EOF
cat >src/cli.py <<'EOF'
import argparse
from .render import render_table


def main():
    parser = argparse.ArgumentParser(prog="csv-report")
    parser.add_argument("csv")
    parser.add_argument("--out", default="report.md")
    args = parser.parse_args()
    with open(args.csv, encoding="utf-8") as src, open(args.out, "w", encoding="utf-8") as out:
        out.write(render_table(src.read()))
EOF
cat >src/render.py <<'EOF'
def render_table(text):
    rows = [line.split(",") for line in text.strip().splitlines()]
    header, body = rows[0], rows[1:]
    lines = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    lines += ["| " + " | ".join(row) + " |" for row in body]
    return "\n".join(lines) + "\n"
EOF
printf '%s\n' 'from src.render import render_table' '' '' 'def test_header():' '    assert render_table("a,b\n1,2").startswith("| a | b |")' >tests/test_render.py
