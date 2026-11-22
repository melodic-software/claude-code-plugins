#!/usr/bin/env bash
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/seed-checkout-service.sh"

mkdir -p docs/conventions
cat > docs/conventions/improvement.yaml <<'CONFIG'
find_run_item_cap: 1
CONFIG

git init -q -b main
git add -A
git -c user.name=Checkout -c user.email=checkout@example.invalid -c commit.gpgsign=false \
  commit -q -m "Add checkout service"
