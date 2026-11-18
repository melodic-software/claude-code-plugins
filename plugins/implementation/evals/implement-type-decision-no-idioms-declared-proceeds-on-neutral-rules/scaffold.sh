#!/usr/bin/env bash
set -euo pipefail

src="$(dirname "${BASH_SOURCE[0]}")/../../skills/implement/evals/fixtures/max-batch-repo"
dest=evals/fixtures/max-batch-repo

mkdir -p "$dest"
cp "$src/pyproject.toml" "$src/worker.py" "$src/CONTRIBUTING.md" "$dest/"

git -C "$dest" init -q -b main
git -C "$dest" config user.name eval
git -C "$dest" config user.email eval@example.invalid
git -C "$dest" add -A
git -C "$dest" commit -q -m "chore: initial state"
git -C "$dest" checkout -q -b fix/max-batch
printf '.work/\n' >>"$dest/.git/info/exclude"
