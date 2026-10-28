#!/usr/bin/env bash
# Seeds the shop control skill and a checkout of the identity repository with its own control skill;
# both apps are the two-process identity fixture. Each is its own repository with its config committed,
# and the shop's committed config pins the identity checkout's HEAD commit.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
skill=.claude/skills/control-shop
mkdir -p "$skill/features/orders/history" "$skill/config" shop
cp "$here/fixtures/control-shop.md" "$skill/SKILL.md"
cp "$here/fixtures/history-README.md" "$skill/features/orders/history/README.md"
cp "$here/fixtures/history-steps.yaml" "$skill/features/orders/history/steps.yaml"
cp "$here/fixtures/defaults.json" "$skill/config/defaults.json"
cp "$here/fixtures/local.json" "$skill/config/local.json"
printf 'local.json\n' >"$skill/config/.gitignore"
fixture="$here/../../skills/map/evals/fixtures/identity/serve.py"
idp=checkouts/identity/.claude/skills/control-identity
mkdir -p "$idp/steps" "$idp/config" "$idp/cli"
cp "$fixture" shop/serve.py
cp "$fixture" checkouts/identity/serve.py
cp "$here/fixtures/control-identity.md" "$idp/SKILL.md"
cp "$here/fixtures/sign-in-steps.yaml" "$idp/steps/sign-in.yaml"
cp "$here/fixtures/identity-defaults.json" "$idp/config/defaults.json"
cp "$here/fixtures/identity-cli-README.md" "$idp/cli/README.md"
commit() {
  git -C "$1" config user.name eval
  git -C "$1" config user.email eval@example.invalid
  git -C "$1" add -A
  GIT_AUTHOR_DATE=2026-10-01T09:00:00Z GIT_COMMITTER_DATE=2026-10-01T09:00:00Z \
    git -C "$1" commit -q -m "$2"
}
git init -q -b main checkouts/identity
commit checkouts/identity "Identity server with its control skill"
sha="$(git -C checkouts/identity rev-parse HEAD)"
sed "s/@IDENTITY_SHA@/$sha/" "$here/fixtures/defaults.json" >"$skill/config/defaults.json"
if [[ "$(git rev-parse --show-toplevel 2>/dev/null || true)" != "$(pwd -P)" ]]; then
  git init -q -b main
fi
printf '/checkouts/\n' >>.gitignore
commit . "Shop with its control skill"
