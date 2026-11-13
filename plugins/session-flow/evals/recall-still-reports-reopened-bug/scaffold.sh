#!/usr/bin/env bash
# Seeds the eval workspace with a git repository whose fix for the SSO login redirect loop
# closed item #57. The tracker stand-in shows #57 closed and then reopened, with no comment or
# commit saying so, so only the item's state history shows the fix did not hold.
set -euo pipefail

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p src
printf 'export const callback = (req) => redirect("/login");\n' >src/sso.ts
git add src
git commit -q -m "feat(auth): SSO sign-in"

printf 'export const callback = (req) => redirect(req.session ? "/" : "/login");\n' >src/sso.ts
git commit -q -am "fix(auth): stop the login redirect loop after SSO sign-in" \
  -m "Fixes #57: the callback sent signed-in users back to /login."
