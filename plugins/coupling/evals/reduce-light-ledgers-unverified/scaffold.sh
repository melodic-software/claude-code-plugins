#!/usr/bin/env bash
# The magic-string repository of reduce-full-pass-splits-lanes-and-ledgers, with
# verification: light on the default branch.
set -euo pipefail
here="$(dirname "${BASH_SOURCE[0]}")"
bash "$here/../fixtures/repo.sh"
mkdir -p src/orders docs/conventions
for name in list show cancel refund exportOrder archive restore notify invoice report audit; do
  printf 'export const %s = (order: { status: string }) => order.status === "archived" ? null : order;\n' "$name" >"src/orders/$name.ts"
done
printf 'verification: light\n' >docs/conventions/coupling.yaml
printf '.work/\n' >.gitignore
git add . && git commit -q -m "feat: add order handlers"
# The level is read from the default branch on origin, so push main to a local bare origin.
mkdir -p .work/origin.git
git init -q --bare -b main .work/origin.git
git remote add origin "$PWD/.work/origin.git"
git push -q origin main
