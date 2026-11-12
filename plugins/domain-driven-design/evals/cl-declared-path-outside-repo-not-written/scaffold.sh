#!/usr/bin/env bash
# A claims repository with a local glossary whose AGENTS.md also declares a glossary in a sibling
# repository that does not exist.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs

cat >AGENTS.md <<'MD'
# claims-service

Terms shared by every service live in ../platform-docs/docs/glossary.md.
MD

cat >docs/glossary.md <<'MD'
# Claims glossary

**Policyholder**

The party that owns the insurance contract.

Avoid: account owner
MD

git add -A
git commit -q -m "Claims service with a glossary"
