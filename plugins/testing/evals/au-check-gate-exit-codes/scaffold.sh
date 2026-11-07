#!/usr/bin/env bash
# One assertion-free JS test, so the gate has a finding to report.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/audit-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main test
au_copy sanity/one-assertion-free.test.js test/payment.test.js
au_commit
