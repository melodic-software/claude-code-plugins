#!/usr/bin/env bash
# The quay repo with one rule on each enforcement-ladder tier.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/quay-repo.sh" ladder
