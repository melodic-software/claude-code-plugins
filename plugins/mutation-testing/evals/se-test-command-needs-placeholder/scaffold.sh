#!/usr/bin/env bash
# A configured Python repo whose test-command lacks {tests}.
set -euo pipefail
fixtures="$(cd "$(dirname "${BASH_SOURCE[0]}")/../fixtures" && pwd)"
bash "${fixtures}/seed-shipping.sh" configured
sed -i "s|^test-command:.*|test-command: python -m pytest tests/|" docs/conventions/mutation-testing.yaml
git commit -q -am "chore: pytest test command"
