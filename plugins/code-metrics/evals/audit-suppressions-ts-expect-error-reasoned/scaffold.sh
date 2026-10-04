#!/usr/bin/env bash
set -euo pipefail
git init -q
printf '%s\n' \
  'import { readLegacy } from "./legacy";' \
  'export function invoiceTotal(raw: string): number {' \
  '  // @ts-expect-error readLegacy is typed for numbers but the export feed sends strings' \
  '  const parsed = readLegacy(raw);' \
  '  // @ts-ignore' \
  '  return parsed.total;' \
  '}' >invoice.ts
git add invoice.ts
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add fixtures"
