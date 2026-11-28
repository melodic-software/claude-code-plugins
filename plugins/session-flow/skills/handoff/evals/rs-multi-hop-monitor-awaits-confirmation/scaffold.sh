#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
git init -q -b main .
git config user.email eval@example.invalid
git config user.name eval
printf '.work/\ndeploy.log\n' >.gitignore
printf 'staging: pending\n' >STATUS.md
git add -A
git commit -q -m "chore: starting point"
printf 'deploy started\n' >deploy.log
mkdir -p .work
printf '*\n' >.work/.gitignore
cp -R "$here/fixtures/handoffs" .work/handoffs
