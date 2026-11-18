#!/usr/bin/env bash
set -euo pipefail

mode="$1"
git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p textkit docs/policies
: >textkit/__init__.py
printf '.work/\n__pycache__/\n' >.gitignore

case "$mode" in
drift | no-work)
    printf '@AGENTS.md\n' >CLAUDE.md
    cat >AGENTS.md <<'MD'
# textkit

## Rules

- Every public function in textkit/ has a docstring that states what it returns.
- Before editing anything under textkit/, read docs/policies/textkit-style.md.
- Before any deployment work, read docs/policies/deploy.md.
MD
    cat >docs/policies/textkit-style.md <<'MD'
# textkit style

- Report a bad argument by raising ValueError, never by printing.
MD
    cat >docs/policies/deploy.md <<'MD'
# Deploys

- A deploy needs a green CI run on the commit it ships.
MD
    ;;
missing)
    cat >CLAUDE.md <<'MD'
@docs/team-rules.md

# textkit

- Every public function in textkit/ has a docstring that states what it returns.
MD
    ;;
none) ;;
*)
    printf 'unknown mode: %s (expected drift, no-work, missing or none)\n' "$mode" >&2
    exit 2
    ;;
esac

git add .
git commit -q -m "scaffold textkit"

if [[ "$mode" = drift ]]; then
    git checkout -q -b feat/trim
    cat >textkit/trim.py <<'PY'
def trim(text, width):
    if width < 0:
        print("width must not be negative")
        return text
    return text[:width]
PY
    git add textkit/trim.py
    git commit -q -m "feat: add trim"
fi
