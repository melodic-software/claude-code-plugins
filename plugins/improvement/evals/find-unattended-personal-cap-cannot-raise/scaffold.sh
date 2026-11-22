#!/usr/bin/env bash
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-checkout-service.sh"

mkdir -p docs/conventions
cat > docs/conventions/improvement.local.yaml <<'CONFIG'
find_open_item_cap: 9
CONFIG
cat > .gitignore <<'IGNORE'
docs/conventions/**/*.local.*
IGNORE

git init -q -b main
git add -A
git -c user.name=Checkout -c user.email=checkout@example.invalid -c commit.gpgsign=false \
  commit -q -m "Add checkout service"
