#!/usr/bin/env bash
# The pending plan, then docs/Release_Notes.md moved under docs/guides/ and committed.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/fn-repo.sh" plan-moved
