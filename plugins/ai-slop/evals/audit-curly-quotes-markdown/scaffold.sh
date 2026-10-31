#!/usr/bin/env bash
# Seeds one markdown file with a curly apostrophe and curly double quotes.
set -euo pipefail

mkdir -p docs
cat > docs/upgrade.md <<'MD'
# Upgrade notes

Run the migration before you restart the workers. It’s safe to run twice.

The old flag was called “fast mode” and is now ignored.
MD
