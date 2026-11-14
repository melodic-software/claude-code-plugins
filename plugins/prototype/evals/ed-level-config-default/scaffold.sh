#!/usr/bin/env bash
# A repository whose team file, docs/conventions/prototype.yaml, sets the prototype level to sketch.
# The workspace is a git working tree because the resolver reads repository files only there.
# No AGENTS.md pointer line binds a home, so the default home, docs/conventions, applies.
set -euo pipefail

git init -q .
mkdir -p docs/conventions
cat >docs/conventions/prototype.yaml <<'YAML'
level: sketch
YAML
