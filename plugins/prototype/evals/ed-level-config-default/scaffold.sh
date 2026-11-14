#!/usr/bin/env bash
# A repository, one commit on main, whose team file docs/conventions/prototype.yaml sets the
# prototype level to sketch. The workspace is made a git working tree because the resolver reads
# repository files only there. No AGENTS.md pointer line binds a home, so the default home,
# docs/conventions, applies.
set -euo pipefail

git init -q -b main .
mkdir -p docs/conventions
printf 'level: sketch\n' >docs/conventions/prototype.yaml
git add docs/conventions/prototype.yaml
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "chore: set the prototype level"
