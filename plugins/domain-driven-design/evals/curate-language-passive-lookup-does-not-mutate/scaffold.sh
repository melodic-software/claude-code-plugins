#!/usr/bin/env bash
# The glossary files the prompt names, under docs/language/.
set -euo pipefail
dir="$(dirname "${BASH_SOURCE[0]}")/../fixtures"
mkdir -p docs/language
cp "$dir/custom-terms.md" docs/language/custom-terms.md
