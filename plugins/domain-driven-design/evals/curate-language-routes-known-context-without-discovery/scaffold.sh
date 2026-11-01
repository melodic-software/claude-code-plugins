#!/usr/bin/env bash
# The glossary files the prompt names, under docs/language/.
set -euo pipefail
dir="$(dirname "${BASH_SOURCE[0]}")/../fixtures"
mkdir -p docs/language
cp "$dir/context-map.md" docs/language/context-map.md
cp "$dir/support-terms.md" docs/language/support-terms.md
cp "$dir/billing-terms.md" docs/language/billing-terms.md
