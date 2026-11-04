#!/usr/bin/env bash
# A committed eol=lf rule for Markdown, and one untracked Markdown file it governs.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/repo.sh" '*.md text eol=lf'
mkdir -p notes
printf 'draft\n' >notes/draft.md
