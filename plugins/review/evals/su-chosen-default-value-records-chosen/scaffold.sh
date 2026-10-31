#!/usr/bin/env bash
# A git working tree with a conforming standards index and no docs/conventions/review.yaml, so the
# settings writer takes its create path and writes on the first call.
set -euo pipefail

git init -q .
mkdir -p docs/standards

cat >docs/standards/README.md <<'MD'
---
standards-contract: 1.1.1
---

# Standards index

| Surface | Applies when | File |
|---|---|---|
| code-style | reviewing any code change | code-style.md |
MD

printf '%s\n' '# Code style' '' 'Name things for what they do.' >docs/standards/code-style.md
