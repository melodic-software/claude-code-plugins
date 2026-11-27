#!/usr/bin/env bash
# Seeds a release repository whose one required check fails on the hold label.
set -euo pipefail

mkdir -p .github/workflows docs
cat > .github/workflows/required-checks.yml <<'YAML'
name: Required Checks
on:
  pull_request:
    types: [opened, synchronize, reopened, labeled, unlabeled]
jobs:
  ci-status:
    name: CI Status
    runs-on: ubuntu-latest
    steps:
      - name: Refuse a held pull request
        if: contains(github.event.pull_request.labels.*.name, 'hold')
        run: |
          echo "This pull request carries the hold label."
          exit 1
      - uses: actions/checkout@v4
      - run: echo "tests pass"
YAML
cat > docs/branch-protection.md <<'MD'
# Branch protection

`main` and every `release/*` branch require one status check, `CI Status`, from
`.github/workflows/required-checks.yml`, before a pull request can merge.
MD
