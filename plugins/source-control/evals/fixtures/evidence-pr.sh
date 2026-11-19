#!/usr/bin/env bash
# Seeds an evidence-comment case: a repository whose feature branch is one commit ahead of main, an
# offline forge (gh-forge) serving open PR 412 with an `## Acceptance criteria` body, a CONFIRMED
# verifier verdict recorded for the head, and two /app-control:drive report.json files, one from
# the head (evidence/head) and one from the base (evidence/base), each listing one PNG per
# interaction in `publishable` under the same file name on both sides. Run it from a case's
# scaffold.sh in the workspace:
#   bash evidence-pr.sh <interactions> [--record-fields] [--e2e]
# <interactions> is the number of acceptance criteria and of driven entry points (one capture
# each per run). --record-fields commits `evidence_record_fields: true` to main's team config.
# --e2e writes each side's /testing:run-e2e e2e-summary.json in place of report.json; its flat
# `publishable` list maps no capture to an entry point.
set -euo pipefail

count="${1:?evidence-pr.sh needs an interaction count}"
record=0 e2e=0
for flag in "${@:2}"; do
  case "$flag" in
    --record-fields) record=1 ;;
    --e2e) e2e=1 ;;
    *) echo "evidence-pr.sh: unknown argument $flag" >&2; exit 2 ;;
  esac
done
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
plugin="$(cd "$here/../.." && pwd)"
png='iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=='
names=(cart checkout receipt orders profile)

git init -q -b main
git config user.name eval
git config user.email eval@example.invalid
mkdir -p docs/conventions src
printf 'export const total = (items) => items.length;\n' >src/cart.ts
printf 'pr_body_required_sections:\n  - Summary\n  - Verification\n' >docs/conventions/source-control.yaml
((record)) && printf 'evidence_record_fields: true\n' >>docs/conventions/source-control.yaml
printf 'evidence/\n' >.gitignore
git add docs src .gitignore
git commit -q -m "chore: seed"

git checkout -q -b feat/cart-totals
printf 'export const total = (items) => items.reduce((s, i) => s + i.price, 0);\n' >src/cart.ts
git add src/cart.ts
git commit -q -m "feat: show the cart total in currency"
head_sha="$(git rev-parse HEAD)"

bash "$here/gh-forge/install.sh" 412 feat/cart-totals main "feat: show the cart total in currency" --open
forge="$(git rev-parse --path-format=absolute --git-common-dir)/eval-forge"

criteria="" rows=()
for ((i = 0; i < count; i++)); do
  criteria+="- The ${names[i]} page shows the total in currency"$'\n'
  rows+=(--row "The ${names[i]} page shows the total in currency | src/cart.ts | drive: open ${names[i]} page | COMPLETE")
done
jq -n --arg body "## Summary"$'\n\n'"Show the cart total in currency."$'\n\n'"## Acceptance criteria"$'\n\n'"$criteria" \
  '{body: $body}' >"$forge/pr-overlay.json"

# One evidence file per side: one entry point and one screenshot per interaction.
for side in base head; do
  dir="evidence/$side"
  mkdir -p "$dir"
  steps='[]' artifacts='[]' publishable='[]'
  for ((i = 0; i < count; i++)); do
    file="${names[i]}.png"
    printf '%s' "$png" | base64 -d >"$dir/$file"
    steps=$(jq -c --arg ep "${names[i]} page" --arg f "$file" \
      '. + [{action: "open", entry_point: $ep, stated_result: null, observed: "page rendered", artifacts: [$f], outcome: "done"}]' <<<"$steps")
    artifacts=$(jq -c --arg f "$file" '. + [{path: $f, kind: "screenshot", mask: "none-declared", publishable: true}]' <<<"$artifacts")
    publishable=$(jq -c --arg f "$file" '. + [$f]' <<<"$publishable")
  done
  if ((e2e)); then
    jq -n --argjson steps "$steps" --argjson publishable "$publishable" \
      '{route: "drive", app: "shop", affected: ["cart"],
        capture: {status: "ran", reason: null, count: ($publishable | length)},
        entry_points: [$steps[] | "cart | \(.entry_point) | passed"], publishable: $publishable}' >"$dir/e2e-summary.json"
  else
    jq -n --argjson steps "$steps" --argjson artifacts "$artifacts" --argjson publishable "$publishable" \
      '{app: "shop", control_skill: null, fallback: "playwright", resolved: null, mode: "unattended",
        trusted_root: null, launch: [], steps: $steps, budgets: [], secrets_mark: [],
        capture_count: ($artifacts | length), artifacts: $artifacts, values_none: [],
        publishable: $publishable, capability_gaps: [], blocked: [], cleanup: []}' >"$dir/report.json"
  fi
done

bash "$plugin/skills/pull-request/scripts/confirm-verdict.sh" record --head "$head_sha" --verdict CONFIRMED "${rows[@]}"
