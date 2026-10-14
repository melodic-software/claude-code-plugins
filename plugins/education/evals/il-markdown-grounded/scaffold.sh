#!/usr/bin/env bash
# Seeds the one module the illustrate cases draw: a retry policy with a hard attempt cap.
set -euo pipefail

mkdir -p src
cat >src/retry.js <<'JS'
// Decides whether a failed call to the billing API is tried again.
const MAX_ATTEMPTS = 4;
const BASE_DELAY_MS = 250;

function shouldRetry(status, attempt) {
  if (attempt >= MAX_ATTEMPTS) return false;
  if (status === 429) return true;
  if (status >= 400 && status < 500) return false;
  return status >= 500;
}

function delayFor(attempt) {
  return BASE_DELAY_MS * 2 ** attempt;
}

module.exports = { shouldRetry, delayFor, MAX_ATTEMPTS };
JS
