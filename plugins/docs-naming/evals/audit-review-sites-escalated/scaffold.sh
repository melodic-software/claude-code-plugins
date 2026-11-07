#!/usr/bin/env bash
# The audit tree with six bare CATALOG stems across five files, and a plan whose FN-c5a4747f marks all six review.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fn-repo.sh" plan-six-review
