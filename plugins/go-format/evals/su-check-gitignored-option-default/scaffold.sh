#!/usr/bin/env bash
# A git repository with a Go module where .gitignore covers .work/, with an untracked, unformatted
# .work/scratch.go, and this clone declined the pre-commit entry (setup SKILL.md check steps 6 and 9).
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config --local checks.go-format.goimports-format.declined true
printf 'module example.invalid/demo\n\ngo 1.22\n' >go.mod
printf 'package main\n\nfunc main() {}\n' >main.go
printf '.work/\n' >.gitignore
mkdir -p .work
printf 'package main\nimport "fmt"\nfunc  scratch(){fmt.Println("x")}\n' >.work/scratch.go
git add .
git commit -q -m "chore: init"
