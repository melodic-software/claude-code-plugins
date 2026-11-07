#!/usr/bin/env bash
# A pytest.ini with --reruns 2 and no --fail-on-flaky, and one sound test.
set -euo pipefail
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/git-workspace.sh"
. "$(dirname "${BASH_SOURCE[0]}")/../fixtures/audit-workspace.sh"
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
ws_init main checkout.py pytest.ini test_checkout.py
au_copy retry-config/pytest/pytest.ini pytest.ini
au_copy retry-config/pytest/test_checkout.py test_checkout.py
printf 'def total(items, shipping=0):\n    return sum(items) + shipping\n' >checkout.py
au_commit
