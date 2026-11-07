#!/usr/bin/env bash
# Three offending doc names cited across the current, historical and released tiers; no plan yet.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fn-repo.sh" audit-tree
