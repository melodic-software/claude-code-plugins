#!/usr/bin/env bash
set -euo pipefail
if git rev-parse --verify -q HEAD >/dev/null 2>&1; then
  echo 'scaffold: refusing to run inside a repository that has commits' >&2
  exit 1
fi
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
git config --local checks.go-format.format.declined true
mkdir -p cmd/app .claude/ecosystems scripts
printf 'module example.com/app\n\ngo 1.23\n' >go.mod
printf 'package main\n\nfunc main() {}\n' >cmd/app/main.go
printf '#!/bin/sh\nexit 0\n' >scripts/lint-go
chmod +x scripts/lint-go
cat >.claude/ecosystems/go.yaml <<'EOF'
globs: ["**/*.go"]
fix-cmd: "scripts/lint-go --fix <files>"
lint-cmd: "scripts/lint-go <files>"
EOF
git add .
git commit -q -m "chore: init"
