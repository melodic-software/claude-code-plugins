#!/usr/bin/env python3
"""Redact every string value of each JSONL row on stdin and write the rows to stdout.

Uses redact.py with the vendored gitleaks rules. Writes nothing unless every row is redacted.
Exit: 0 ok; 1 the rules are unusable or redaction failed; 2 a line is not a JSON object.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from redact import load_redactor  # noqa: E402


def _walk(value, redactor):
    if isinstance(value, str):
        return redactor.redact(value)
    if isinstance(value, list):
        return [_walk(v, redactor) for v in value]
    if isinstance(value, dict):
        return {k: _walk(v, redactor) for k, v in value.items()}
    return value


def main() -> int:
    redactor = load_redactor()
    if redactor.fail_closed:
        print(
            f"redact_rows.py: redaction rules unusable ({redactor.skipped or 'none loaded'})",
            file=sys.stderr,
        )
        return 1
    try:
        text = sys.stdin.buffer.read().decode("utf-8")
    except UnicodeDecodeError:
        print("redact_rows.py: input is not UTF-8", file=sys.stderr)
        return 2
    out = []
    for n, line in enumerate(text.split("\n"), 1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except ValueError:
            row = None
        if not isinstance(row, dict):
            print(f"redact_rows.py: line {n} is not a JSON object", file=sys.stderr)
            return 2
        out.append(
            json.dumps(_walk(row, redactor), ensure_ascii=False, separators=(",", ":"))
        )
    sys.stdout.buffer.write("".join(f"{row}\n" for row in out).encode("utf-8"))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as exc:  # noqa: BLE001 - any failure must stop the append
        print(f"redact_rows.py: {type(exc).__name__}: {exc}", file=sys.stderr)
        sys.exit(1)
