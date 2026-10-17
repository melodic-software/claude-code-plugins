#!/usr/bin/env bash
# Owns lib/git-hooks/install.test.mjs for the plugin test lane
# (scripts/run-outside-node-suites.sh treats a sibling .test.sh as the runner).
# test-scope: lib/git-hooks/install.mjs lib/git-hooks/check-lib.sh lib/prerequisites.mjs
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
node --test "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/install.test.mjs"
