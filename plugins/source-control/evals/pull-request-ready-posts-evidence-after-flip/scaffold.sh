#!/usr/bin/env bash
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin="$(cd "$here/../.." && pwd)"

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions src
printf 'export const total = (items) => items.length;\n' >src/cart.ts
printf 'pre_ready:\n  - step: code-review\n    enabled: false\n  - step: security-review\n    enabled: false\n' \
  >docs/conventions/source-control.yaml
printf 'evidence/\n' >.gitignore
git add docs src .gitignore
git commit -q -m "chore: seed"

git checkout -q -b feat/cart-total
printf 'export const total = (items) => items.reduce((s, i) => s + i.price, 0);\n' >src/cart.ts
git commit -q -am "feat: show the cart total"
head_sha="$(git rev-parse HEAD)"

bash "$here/../fixtures/gh-forge/install.sh" 655 feat/cart-total main "feat: show the cart total"

gate="$(git rev-parse --path-format=absolute --git-common-dir)/ready-verify"
mkdir -p "$gate"
printf 'pass\n' >"$gate/$head_sha"
bash "$plugin/skills/pull-request/scripts/confirm-verdict.sh" record --head "$head_sha" --verdict CONFIRMED

mkdir -p evidence
printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==' |
  base64 -d >evidence/cart.png
jq -n '{route: "drive", app: "shop", affected: ["cart"],
  capture: {status: "ran", reason: null, count: 1},
  entry_points: ["cart | cart page | passed"], publishable: ["cart.png"]}' >evidence/e2e-summary.json
