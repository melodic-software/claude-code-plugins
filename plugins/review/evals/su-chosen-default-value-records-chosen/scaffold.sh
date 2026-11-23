#!/usr/bin/env bash
set -euo pipefail

git init -q .
mkdir -p docs/standards

cat >docs/standards/README.md <<'MD'
---
standards-contract: 1.1.2
---

# Standards index

| Surface | Applies when | File |
|---|---|---|
| code-style | reviewing any code change | code-style.md |
MD

printf '%s\n' '# Code style' '' 'Name things for what they do.' >docs/standards/code-style.md
