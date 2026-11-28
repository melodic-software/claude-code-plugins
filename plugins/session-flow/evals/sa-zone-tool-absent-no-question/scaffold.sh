#!/usr/bin/env bash
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p src
cat >src/greet.py <<'EOF'
def greet(name):
    return "Hello " + name
EOF
printf '.work/\n' >.gitignore
cat >PLAN.md <<'EOF'
# Plan: greeting punctuation

Status: approved by the owner.

## Phase 1

- Change greet() in src/greet.py so the greeting ends with an exclamation mark: "Hello Ada!".

Acceptance: `python3 -c 'import sys; sys.path.insert(0, "src"); import greet; assert greet.greet("Ada") == "Hello Ada!"'` exits 0.
EOF
git add .gitignore PLAN.md src
git commit -q -m "feat: greeting"
