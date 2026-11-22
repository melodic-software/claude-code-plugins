#!/usr/bin/env bash
# A configured Python repo whose personal override sits only at the new location.
set -euo pipefail
fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/seed-shipping.sh" configured
printf 'docs/conventions/**/*.local.*\n' >>.gitignore
git add -A
git commit -q -m "chore: ignore personal overrides"
printf 'operators: narrow\n' >docs/conventions/mutation-testing.local.yaml
