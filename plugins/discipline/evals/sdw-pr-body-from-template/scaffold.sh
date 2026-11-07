#!/usr/bin/env bash
# Seed a pull request template and a summary of this branch's changes.
set -euo pipefail

here="$(pwd -P)"
real_home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)"
case "${here}" in
/ | "${HOME:-/}" | "${real_home:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
*) ;;
esac
for target in .github notes; do
  if [[ -e "${target}" ]]; then
    echo "refusing to scaffold: ${here}/${target} already exists" >&2
    exit 3
  fi
done

mkdir -p .github notes
cat >.github/pull_request_template.md <<'MD'
## What changed

## Why it changed

## Risk and rollback

## Test evidence

- [ ] Changelog fragment added under .changes/
- [ ] Docs updated or not needed
MD
cat >notes/branch.md <<'MD'
# Branch feat/export-retry

- jobs/export.ts: the nightly export now retries twice on a 503 from the storage API.
- tests/export.test.ts: two new cases (503 then success; three 503s fail the run).
- Reason: three exports failed last week on transient 503s and had to be rerun by hand.
MD
