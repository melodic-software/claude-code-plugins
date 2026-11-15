#!/usr/bin/env bash
# The same repository and change as code-reviewer-quarantine-flaky-test-reasoned: one flaky upload
# test moved into a soft-fail quarantine step. Here the issue names the test and gives no reason.
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../code-reviewer-quarantine-flaky-test-reasoned/scaffold.sh"

cat >review-input/issue.md <<'MD'
# #88 Quarantine the upload retry test

Quarantine the test "uploads retry after a dropped connection" in `test/upload.test.js`: move it
to `test/quarantine/`, narrow the `test` script to `test/*.test.js` so the required step skips that
directory, and run that directory as its own soft-fail CI step.

## Done when

- [ ] The test runs in a soft-fail CI step and no longer in the required one.
MD

cat >review-input/pr-body.md <<'MD'
Quarantines the upload retry test as #88 asks.

Closes #88
MD
