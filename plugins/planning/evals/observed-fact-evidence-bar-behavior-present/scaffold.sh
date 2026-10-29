#!/usr/bin/env bash
# Seeds the eval workspace with the nightly-etl repository, stripping the .txt suffix.
set -euo pipefail

src="$(dirname "${BASH_SOURCE[0]}")/../fixtures/nightly-etl"
(cd "$src" && find . -type f -name '*.txt') | while read -r f; do
  mkdir -p "$(dirname "$f")"
  cp "$src/$f" "${f%.txt}"
done
