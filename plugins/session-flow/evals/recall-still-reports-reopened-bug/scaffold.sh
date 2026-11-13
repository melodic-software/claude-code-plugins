#!/usr/bin/env bash
# Seeds the eval workspace with a git repository whose fix for the SSO login redirect loop
# closed item #57. Whether the fix held is for the tracker stand-in to answer.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src
printf 'export const callback = (req) => redirect("/login");\n' >src/sso.ts
git add src
GIT_AUTHOR_DATE=2026-08-20T10:00:00Z GIT_COMMITTER_DATE=2026-08-20T10:00:00Z \
  git commit -q -m "feat(auth): SSO sign-in"

printf 'export const callback = (req) => redirect(req.session ? "/" : "/login");\n' >src/sso.ts
GIT_AUTHOR_DATE=2026-09-02T13:50:00Z GIT_COMMITTER_DATE=2026-09-02T13:50:00Z \
  git commit -q -am "fix(auth): stop the login redirect loop after SSO sign-in" \
  -m "Fixes #57: the callback sent signed-in users back to /login."
