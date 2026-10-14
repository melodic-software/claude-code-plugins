#!/usr/bin/env bash
# Seed an EPUB whose archive carries a ../evil.txt entry.
set -euo pipefail

mkdir -p books
python3 -I "$(dirname "${BASH_SOURCE[0]}")/../fixtures/bd-make-epub.py" books/field-notes.epub --traversal
