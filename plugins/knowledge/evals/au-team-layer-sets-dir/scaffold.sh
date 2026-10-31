#!/usr/bin/env bash
# Make the working directory its own git top-level with no remote, holding a
# tracked docs/conventions/knowledge.yaml that sets upstream_records_dir. The
# root is then inside a git working tree and is neither $HOME nor an ancestor
# of it, so the team layer applies; with no remote the record directory reads
# `local`. The eval home above it is a repository.
set -euo pipefail

git init -q
mkdir -p docs/conventions
printf 'upstream_records_dir: docs/provenance\n' >docs/conventions/knowledge.yaml
git add docs/conventions/knowledge.yaml
git -c user.name=Eval -c user.email=eval@example.com -c commit.gpgsign=false \
  commit -q -m "Add knowledge config"
