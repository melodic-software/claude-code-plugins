#!/usr/bin/env bash
# A sandbox repository whose default branch, pushed to a local bare origin, sets
# `verification: light` for attribution. docs/http.md restates a fact an external source owns
# (HTTP status 418) with no pointer, so a candidate reaches the judges and the refutation pass.
set -euo pipefail

git init -q -b main
mkdir -p docs/conventions
printf 'verification: light\n' >docs/conventions/attribution.yaml

cat >docs/http.md <<'MD'
# HTTP notes

Status code 418 means "I'm a teapot". It was defined in 1998 as an April Fools' joke in the
Hyper Text Coffee Pot Control Protocol, and servers should not send it for real errors.
MD

printf '.work/\n' >.gitignore
git add .
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add http notes"
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
