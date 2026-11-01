#!/usr/bin/env bash
# A docs repository for a fictional build tool with three verification stamps: one ISO stamp far
# past the 180-day default, one ISO stamp dated the day the scaffold runs, and one month-name stamp
# the stamp parser declines. Every file is tracked.
set -euo pipefail
today="$(date +%Y-%m-%d)"
git init -q -b main .
mkdir -p docs
cat >docs/retry-policy.md <<'MD'
# Retry policy

Our pipeline retries a failed Widget Runner step with the `linear` strategy, because our failures
cluster rather than spread and exponential backoff would leave the agents idle.

**Verification record.** Claim: the runner's `retry` key accepts `none`, `linear` and `exponential`.
Basis: https://docs.example.invalid/widget-runner/retry. Verified 2024-03-04. Recheck trigger: the
runner's major version changes.
MD
cat >docs/cache-layout.md <<MD
# Cache layout

The Widget Runner cache stays under the workspace root. We have not needed to move it.

**Verification record.** Claim: the runner keeps its cache under the workspace root unless told
otherwise. Basis: https://docs.example.invalid/widget-runner/cache. Verified ${today}. Recheck
trigger: the runner's major version changes.
MD
cat >docs/release-notes.md <<'MD'
# Release notes

We pin Widget Runner to the 4.x line and read its changelog before each upgrade.

Verified March 2024 against the vendor changelog.
MD
git add -A
git -c user.name=eval -c user.email=eval@example.invalid commit -qm seed
