#!/usr/bin/env bash
# Seeds the eval workspace with the webhook-sender repository, stripping the .txt suffix.
set -euo pipefail

src="$(dirname "${BASH_SOURCE[0]}")/../fixtures/webhook-sender"
(cd "$src" && find . -type f -name '*.txt') | while read -r f; do
  mkdir -p "$(dirname "$f")"
  cp "$src/$f" "${f%.txt}"
done
