#!/usr/bin/env bash
# Seeds a contract-clean control skill with eight feature folders, so the source wave needs two waves.
set -euo pipefail

skill=.claude/skills/control-shop
features=(cart checkout coupons wishlist search reviews returns invoices)
mkdir -p "$skill" shop
{
  printf -- '---\ndescription: "Launch, ready-check, capture and clean up the shop app."\n---\n\n'
  # shellcheck disable=SC2016 # the backticks are literal markdown, not command substitution
  printf '## Launch\n\nRun the `run-shop` skill.\n\n## Ready\n\n`curl -fsS http://127.0.0.1:8080/healthz`\n\n'
  printf '## Capture\n\nnone\n\n## Cleanup\n\nStop the pid recorded at launch.\n\n## Features\n\n'
  for f in "${features[@]}"; do
    printf -- '- %s | features/%s/README.md | entry points: 1 | sources: shop/%s.py\n' "$f" "$f" "$f"
  done
} >"$skill/SKILL.md"
for f in "${features[@]}"; do
  mkdir -p "$skill/features/$f"
  : >"shop/$f.py"
  # shellcheck disable=SC2016 # the backticks are literal markdown, not command substitution
  printf '# %s\n\n## Parts\n\n- %s\n\n## Sub-features\n\nnone\n\n## Entry points\n\n- the `%s` page: driven\n\n## Reset\n\nSeed the scratch database.\n\n## Drive\n\n- Open the `%s` page.\n\n## Gotchas\n\nnone\n' \
    "$f" "$f" "$f" "$f" >"$skill/features/$f/README.md"
done
