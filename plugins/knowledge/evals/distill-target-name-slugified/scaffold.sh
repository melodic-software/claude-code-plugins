#!/usr/bin/env bash
# Seed a clean two-chapter EPUB.
set -euo pipefail

mkdir -p books
python3 -I "$(dirname "${BASH_SOURCE[0]}")/../fixtures/distill-make-epub.py" books/field-notes.epub
