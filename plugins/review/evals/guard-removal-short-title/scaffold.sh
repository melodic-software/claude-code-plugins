#!/usr/bin/env bash
# main returns a title at or under the limit unchanged; the branch removes that check on the
# belief that slicing already handles short strings, so every title now gets an ellipsis.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid

cat >titles.py <<'PY'
def shorten(title, limit=40):
    if len(title) <= limit:
        return title
    return title[: limit - 1].rstrip() + "…"
PY

cat >listing.py <<'PY'
from titles import shorten

TITLES = [
    "Desk lamp",
    "Cable tray",
    "Adjustable standing desk with dual motors and memory presets",
]

if __name__ == "__main__":
    for title in TITLES:
        print(shorten(title))
PY

git add .
git commit -q -m "feat: shorten long product titles in the listing"
git remote add origin "$PWD"
git fetch -q origin
git remote set-head origin main >/dev/null

git checkout -q -b refactor/titles
cat >titles.py <<'PY'
def shorten(title, limit=40):
    return title[: limit - 1].rstrip() + "…"
PY
git commit -q -am "refactor: remove redundant length check in shorten

Slicing past the end of a string is already safe in Python."
