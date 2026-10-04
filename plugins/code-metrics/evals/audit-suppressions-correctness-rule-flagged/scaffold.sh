#!/usr/bin/env bash
set -euo pipefail
git init -q
mkdir -p docs/conventions
printf '%s\n' 'suppressions:' '  correctness_rules: [no-floating-promises]' >docs/conventions/code-metrics.yaml
printf '%s\n' \
  'export function startNightlyExport(queue: Queue): void {' \
  '  // eslint-disable-next-line no-floating-promises -- the queue retries a failed export itself' \
  '  queue.push(exportLedger());' \
  '  // eslint-disable-next-line no-console -- operators read this line in the job log' \
  '  console.info("nightly export queued");' \
  '}' >export.ts
git add docs/conventions/code-metrics.yaml export.ts
git -c user.name=eval -c user.email=eval@example.invalid commit -q -m "add fixtures"
