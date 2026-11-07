#!/usr/bin/env bash
# A CSV stock importer that opens files as plain utf-8, so a file starting with a byte-order mark
# reads its first header as "﻿sku" and is rejected. samples/ holds the same rows with and
# without the BOM, and the README gives the command that imports one file: a ready loop.
set -euo pipefail
set -o noclobber
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
bash "${here}/../fixtures/repo-scaffold-guard.sh" .git .gitignore README.md importer samples tests
GIT_CEILING_DIRECTORIES="$(dirname "${PWD}")"
export GIT_CEILING_DIRECTORIES
g() {
  git -c core.hooksPath=/dev/null -c commit.gpgsign=false -c user.name=eval \
    -c user.email=eval@example.invalid "$@"
}
g -c init.defaultBranch=main init -q --template=
mkdir -p importer samples tests

cat >README.md <<'MD'
# stock-importer

Import one CSV file:

    python3 -m importer.csv_import samples/plain.csv

Exit 0 prints the rows imported; exit 2 prints why the file was rejected.

Tests: `python3 -m unittest discover -s tests`
MD

printf '__pycache__/\n' >.gitignore
: >importer/__init__.py

cat >importer/csv_import.py <<'PY'
import csv
import sys

EXPECTED_HEADER = ["sku", "name", "qty"]


class ImportRejected(Exception):
    pass


def read_rows(path):
    with open(path, encoding="utf-8", newline="") as handle:
        reader = csv.reader(handle)
        header = next(reader, [])
        if header != EXPECTED_HEADER:
            raise ImportRejected(f"unexpected header: {header!r}")
        return [dict(zip(header, row)) for row in reader]


def main(argv):
    try:
        rows = read_rows(argv[1])
    except ImportRejected as error:
        print(f"rejected {argv[1]}: {error}")
        return 2
    print(f"imported {len(rows)} rows from {argv[1]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
PY

printf 'sku,name,qty\r\nA-100,Hex bolt,40\r\nA-101,Washer,250\r\n' >samples/plain.csv
printf '\xef\xbb\xbfsku,name,qty\r\nA-100,Hex bolt,40\r\nA-101,Washer,250\r\n' >samples/with-bom.csv

cat >tests/test_csv_import.py <<'PY'
import unittest

from importer.csv_import import read_rows


class ReadRowsTest(unittest.TestCase):
    def test_plain_file(self):
        rows = read_rows("samples/plain.csv")
        self.assertEqual(rows[0]["sku"], "A-100")
PY

g add -A
g commit -q -m "feat: import stock CSV files"
