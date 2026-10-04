#!/usr/bin/env bash
# Seeds an eval workspace: the checkout-app tree with its .txt suffix stripped, plus
# the analyze-profile skill's fixture profiles under profiles/ and heap/.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
app="$here/checkout-app"
skill_fixtures="$here/../../skills/analyze-profile/scripts/fixtures"

(cd "$app" && find . -type f -name '*.txt') | while read -r f; do
  mkdir -p "$(dirname "$f")"
  cp "$app/$f" "${f%.txt}"
done
mkdir -p profiles heap
cp "$skill_fixtures/checkout.cpuprofile" profiles/checkout.cpuprofile
cp "$skill_fixtures/session-cache.heapsnapshot" heap/api.heapsnapshot
