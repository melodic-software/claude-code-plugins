#!/usr/bin/env bash
set -euo pipefail

mkdir -p src
cat >src/utils.ts <<'TS'
// Returns the trimmed, lowrcased form of a user-entered email address.
export function normalizeEmail(input: string): string {
  return input.trim().toLowerCase();
}
TS
