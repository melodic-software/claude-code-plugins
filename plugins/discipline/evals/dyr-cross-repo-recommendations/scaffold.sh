#!/usr/bin/env bash
# Seed three checked-out repos, the shared lint action, and the pending recommendations note.
set -euo pipefail

here="$(pwd -P)"
run_home="$(cd "${HOME:?}" && pwd -P)"
real_home="$(getent passwd "$(id -u)" 2>/dev/null | cut -d: -f6 || true)"
case "${here}" in
/ | "${run_home}" | "${real_home:-/}") echo "refusing to scaffold in ${here}" >&2 && exit 3 ;;
*) ;;
esac
if [[ -n "${real_home}" && "${run_home}" == "$(cd "${real_home}" 2>/dev/null && pwd -P)" ]]; then
  echo "refusing to scaffold: HOME is the real home" >&2 && exit 3
fi
case "${here}/" in
"${run_home}"/*) ;;
*) echo "refusing to scaffold outside HOME: ${here}" >&2 && exit 3 ;;
esac
for target in repos notes; do
  if [[ -e "${target}" ]]; then
    echo "refusing to scaffold: ${here}/${target} already exists" >&2 && exit 3
  fi
done

mkdir -p notes repos/billing-api/.github/workflows repos/web-portal/.github/workflows repos/ops-tools/.github/workflows repos/shared-lint-action
cat >notes/recommendations.md <<'MD'
# Pending recommendations (not yet acted on)

1. Pin acme/shared-lint-action to v3 in every repo that uses it.
2. Make the action's new cache step the default (`cache: true`).
MD
cat >repos/billing-api/.github/workflows/lint.yml <<'YAML'
name: lint
on: [pull_request]
jobs:
  lint:
    runs-on: ubuntu-20.04
    steps:
      - uses: actions/checkout@v4
      - uses: acme/shared-lint-action@v2
YAML
cat >repos/web-portal/.github/workflows/lint.yml <<'YAML'
name: lint
on: [pull_request]
jobs:
  lint:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4
      - uses: acme/shared-lint-action@v2
        with:
          paths: src
YAML
cat >repos/ops-tools/.github/workflows/ci.yml <<'YAML'
name: ci
on: [push]
jobs:
  test:
    runs-on: ubuntu-22.04
    steps:
      - uses: actions/checkout@v4
      - run: make test
YAML
cat >repos/shared-lint-action/CHANGELOG.md <<'MD'
# Changelog

## v3.0.0 (2026-09-14)

- Runs on node24. Requires ubuntu-22.04 or later runners; ubuntu-20.04 jobs fail at setup.
- Adds the `cache` input (default false).

## v2.6.0 (2026-03-02)

- Adds the `paths` input.
MD
cat >repos/shared-lint-action/README.md <<'MD'
# shared-lint-action

## Inputs

- `paths`: directories to lint.
- `cache` (experimental): caches lint results keyed on the lockfile only, so a lint config change can serve stale results until the lockfile changes.
MD
