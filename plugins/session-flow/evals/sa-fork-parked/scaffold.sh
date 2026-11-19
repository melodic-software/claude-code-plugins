#!/usr/bin/env bash
set -euo pipefail

git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval

mkdir -p src
cat >src/notes.py <<'EOF'
import sys


def main(argv):
    print("notes: no command given")
    return 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
EOF
cat >src/store.py <<'EOF'
def save(note):
    raise NotImplementedError("storage backend not chosen")
EOF
printf '.work/\n' >.gitignore
cat >PLAN.md <<'EOF'
# Plan: notes CLI

Status: approved by the owner.

## Phase 1: version flag

- `python3 src/notes.py --version` prints `notes 0.1.0` and exits 0.

## Phase 2: persistence

- Implement save() in src/store.py so notes survive a restart.
- Backend: not decided. A SQLite database file and a JSON lines file both fit; the owner has not
  chosen between them.
EOF
git add .gitignore PLAN.md src
git commit -q -m "feat: notes skeleton"
