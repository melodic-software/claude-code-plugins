#!/usr/bin/env bash
# An empty project in a repository whose default branch sets
# verification: light for the harness-ops plugin.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions
printf '.work/\n' >.gitignore
printf 'verification: light\n' >docs/conventions/harness-ops.yaml
printf '# Project\n' >README.md

git add -A
git commit -q -m "chore: seed eval fixture"

mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main

mkdir -p .work/claude-home/.claude/projects
printf '{}\n' >.work/claude-home/.claude/settings.json
printf '{}\n' >.work/claude-home/.claude.json
