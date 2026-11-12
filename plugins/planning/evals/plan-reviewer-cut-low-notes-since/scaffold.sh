#!/usr/bin/env bash
# A notes CLI whose list command has no date filter, and a draft plan to add --since.
set -euo pipefail

mkdir -p .work/notes-since/design notes tests
cat >README.md <<'EOF'
# notes

A small notes CLI: `python -m notes.cli list`.
EOF
: >notes/__init__.py
cat >notes/store.py <<'EOF'
"""Notes kept in notes.json as a list of {"created": "YYYY-MM-DD", "text": ...}."""
import json
from pathlib import Path

STORE = Path("notes.json")


def list_notes(path=STORE):
    if not path.exists():
        return []
    return json.loads(path.read_text(encoding="utf-8"))
EOF
cat >notes/cli.py <<'EOF'
import argparse

from notes import store


def main(argv=None):
    parser = argparse.ArgumentParser(prog="notes")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("list")
    args = parser.parse_args(argv)
    if args.command == "list":
        for note in store.list_notes():
            print(note["created"], note["text"])


if __name__ == "__main__":
    main()
EOF
cat >tests/test_cli.py <<'EOF'
import io
import unittest
from contextlib import redirect_stdout
from unittest import mock

from notes import cli


class ListTest(unittest.TestCase):
    def test_lists_all(self):
        notes = [{"created": "2026-03-01", "text": "a"}]
        out = io.StringIO()
        with mock.patch("notes.store.list_notes", return_value=notes), redirect_stdout(out):
            cli.main(["list"])
        self.assertEqual(out.getvalue(), "2026-03-01 a\n")


if __name__ == "__main__":
    unittest.main()
EOF
cat >.work/notes-since/PLAN.md <<'EOF'
# notes list --since

## Brief

### Problem
`notes list` prints every note ever written, so people with hundreds of notes scroll to find this week's.

### Goal
`notes list --since DATE` shows only notes created on or after DATE.

### Acceptance criteria
- AC1: `notes list` without `--since` prints what it prints today.
- AC2: `notes list --since 2026-03-01` prints only notes created on or after that date.
- AC3: An unparsable `--since` value exits with status 2 and an error naming the flag.

### Out-of-scope
- Relative dates such as "last week".
- An `--until` flag.

### Work size
Appetite: half a day.

### Captured assumptions
- Every note's `created` value is an ISO 8601 date (YYYY-MM-DD): revisit if a note file from the old mobile app shows another format.

## Design

Early exit (tier C): One flag on an existing subcommand; no new types.

## Plan

### Behavior
- B1: Without the flag the listing is unchanged (AC1). Delivered by Phase 1.
- B2: The flag hides notes created before the given date (AC2). Delivered by Phase 1.
- B3: A bad date is refused with a usage error naming the flag (AC3). Delivered by Phase 1.

### Load-bearing assumptions

| Assumption | Source | Falsifying check | Response if false |
|---|---|---|---|
| argparse reports a `type=` conversion error with exit status 2 | plan | Phase 1 Sanity Check | Minor: proceed and note |

### Phase 1: Add --since [STATUS]
**Satisfies:** AC1, AC2, AC3
**Delivers:** B1, B2, B3

- In `notes/cli.py`, add `--since` to the `list` subparser with `type=date.fromisoformat`, so argparse reports a bad value as a usage error naming `--since`.
- Keep only notes whose `date.fromisoformat(note["created"])` is on or after the value.
- In `tests/test_cli.py`, add one case per criterion.

**Sanity Check:** `python -m unittest discover -s tests` exits 0.

### Files affected
| File | Action |
|---|---|
| `notes/cli.py` | modify |
| `tests/test_cli.py` | modify |
EOF
cat >.work/notes-since/design/design-resolution.md <<'EOF'
outcome: early-exit
tier: C
reason: One flag on an existing subcommand; no new types.
EOF
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/plan-reviewer-cut/init-repo.sh" feat/notes-since
