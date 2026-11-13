#!/usr/bin/env bash
# Seeds the eval workspace with the invoice-export interview ledger, stripping the .txt suffix.
set -euo pipefail

src="$(dirname "${BASH_SOURCE[0]}")/../fixtures/wayfind-charting/invoice-ledger"
mkdir -p .work/invoice-export
for name in interview-checklist.md; do
  cp "$src/$name.txt" ".work/invoice-export/$name"
done
