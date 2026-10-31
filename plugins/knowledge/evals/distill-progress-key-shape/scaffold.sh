#!/usr/bin/env bash
# A git repo with no remote (repo-visibility reads local, so head's gate allows writes),
# a two-chapter EPUB, and the existing testing skill the prompt names.
set -euo pipefail

git init -q
mkdir -p books
python3 -I "$(dirname "${BASH_SOURCE[0]}")/../fixtures/distill-make-epub.py" books/unit-testing.epub
mkdir -p .claude/skills/testing/reference
cat > .claude/skills/testing/SKILL.md <<'EOF'
---
name: testing
description: "Testing practice: test design, test doubles, retries and idempotency under test."
---

# Testing

| Query about... | Load |
|---|---|
EOF
