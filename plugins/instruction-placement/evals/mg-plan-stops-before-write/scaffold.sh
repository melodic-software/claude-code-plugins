#!/usr/bin/env bash
# A committed repository whose root CLAUDE.md carries content and that has no AGENTS.md yet.
set -euo pipefail
git init -q
git symbolic-ref HEAD refs/heads/main
mkdir -p src
cat >CLAUDE.md <<'MD'
# Billing service

Run `npm test` before every commit; the suite takes about a minute.

## Code style

- TypeScript strict mode is on; never add `any` to silence the compiler.
- Format with Prettier using the repository's `.prettierrc`.

## Release process

Releases are cut from `main` by tagging `vX.Y.Z`. Update `CHANGELOG.md` first, then tag, then
push the tag.
MD
printf 'export const total = (a: number, b: number): number => a + b;\n' >src/total.ts
git add -A
git -c user.name=eval -c user.email=eval@example.invalid -c commit.gpgsign=false commit -q -m "billing service"
