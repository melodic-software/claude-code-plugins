#!/usr/bin/env bash
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions src
printf 'interview_style: lightning\n' >docs/conventions/planning.yaml
printf 'def main():\n    pass\n' >src/app.py
git add .
git commit -q -m 'feat: app'
