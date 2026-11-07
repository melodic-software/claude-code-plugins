#!/usr/bin/env bash
# A git repository with no docs-naming layer at all.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fn-repo.sh" setup-empty
