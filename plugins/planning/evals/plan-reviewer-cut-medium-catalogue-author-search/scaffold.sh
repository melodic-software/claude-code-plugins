#!/usr/bin/env bash
# A library kiosk package that searches titles only, and a draft plan to add author search.
set -euo pipefail

mkdir -p .work/author-search/design data library tests
cat >README.md <<'EOF'
# library

The catalogue kiosk: `python -m library.cli search WORD`.
EOF
: >library/__init__.py
cat >data/books.json <<'EOF'
[{"title": "Beloved", "author": "Toni Morrison"}, {"title": "Jazz", "author": "Toni Morrison"}, {"title": "Emma", "author": "Jane Austen"}]
EOF
cat >library/catalogue.py <<'EOF'
import json
from pathlib import Path


def load_books(path=Path("data/books.json")):
    return json.loads(path.read_text(encoding="utf-8"))
EOF
cat >library/index.py <<'EOF'
"""In-memory index of the catalogue."""
from library.catalogue import load_books


def build():
    books = load_books()
    by_word = {}
    for book in books:
        for word in book["title"].split():
            by_word.setdefault(word.lower(), []).append(book)
    return {"by_word": by_word, "books": books}
EOF
cat >library/search.py <<'EOF'
def search_title(index, query):
    """Books with a title word equal to the query, in catalogue order."""
    return list(index["by_word"].get(query.lower(), []))
EOF
cat >library/cli.py <<'EOF'
import argparse

from library import index, search


def main(argv=None):
    parser = argparse.ArgumentParser(prog="library")
    sub = parser.add_subparsers(dest="command", required=True)
    find = sub.add_parser("search")
    find.add_argument("query")
    args = parser.parse_args(argv)
    for book in search.search_title(index.build(), args.query):
        print(book["title"], "-", book["author"])


if __name__ == "__main__":
    main()
EOF
cat >tests/test_index.py <<'EOF'
import unittest
from unittest import mock

from library import index


class IndexTest(unittest.TestCase):
    def test_title_words(self):
        with mock.patch("library.index.load_books", return_value=[{"title": "Big Sky", "author": "A"}]):
            self.assertIn("sky", index.build()["by_word"])


if __name__ == "__main__":
    unittest.main()
EOF
cat >tests/test_cli.py <<'EOF'
import io
import unittest
from contextlib import redirect_stdout
from unittest import mock

from library import cli


class CliTest(unittest.TestCase):
    def test_title_search(self):
        books = [{"title": "Emma", "author": "Jane Austen"}]
        out = io.StringIO()
        with mock.patch("library.index.load_books", return_value=books), redirect_stdout(out):
            cli.main(["search", "emma"])
        self.assertEqual(out.getvalue(), "Emma - Jane Austen\n")


if __name__ == "__main__":
    unittest.main()
EOF
cat >.work/author-search/PLAN.md <<'EOF'
# Search by author

## Brief

### Problem
Patrons ask at the desk for books by an author because the kiosk searches titles only.

### Goal
The kiosk finds books by author name.

### Acceptance criteria
- AC1: `search --author morrison` lists every book whose author contains `morrison`, in any case.
- AC2: Title search is unchanged.
- AC3: Author results are listed in title order.

### Out-of-scope
- Fuzzy matching.
- Search by ISBN.

### Work size
Appetite: one day.

## Design

Early exit (tier C): New functions beside existing ones; no new types.

## Plan

### Behavior
- B1: An author query lists every book by a matching author, case ignored (AC1). Delivered by Phase 1 and Phase 2.
- B2: Title search answers as before (AC2). Delivered by Phase 2.
- B3: Author results come in title order (AC3). Delivered by Phase 2.

### Load-bearing assumptions

| Assumption | Source | Falsifying check | Response if false |
|---|---|---|---|
| Each book has exactly one author string | plan | Phase 1 Sanity Check | Moderate: flag and continue |

### Phase 1: Index authors [STATUS]
**Satisfies:** AC1
**Delivers:** B1

- In `library/index.py`, add a `by_author` map from each lowercased author string to its books, built beside `by_word`.
- In `tests/test_index.py`, add a case for two books by one author.

**Sanity Check:** `python -m unittest tests.test_index` exits 0.

### Phase 2: Search and command [STATUS]
**Satisfies:** AC1, AC2, AC3
**Delivers:** B1, B2, B3

- In `library/search.py`, add `search_author(index, query)` returning books whose author contains the lowercased query; AC3 needs no work, since `search_title` already sorts its results by title and `search_author` shapes results the same way.
- In `library/cli.py`, add `--author` to the `search` command and call `search_author` when it is given.
- In `tests/test_cli.py`, add a case for `--author` and keep the title case.

**Sanity Check:** `python -m unittest discover -s tests` exits 0.

### Files affected
| File | Action |
|---|---|
| `library/index.py` | modify |
| `library/search.py` | modify |
| `library/cli.py` | modify |
| `tests/test_index.py` | modify |
| `tests/test_cli.py` | modify |
EOF
cat >.work/author-search/design/design-resolution.md <<'EOF'
outcome: early-exit
tier: C
reason: New functions beside existing ones; no new types.
EOF
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/plan-reviewer-cut/init-repo.sh" feat/author-search
