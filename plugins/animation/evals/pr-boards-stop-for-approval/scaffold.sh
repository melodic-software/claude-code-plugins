#!/usr/bin/env bash
# A production directory whose boards are complete and pass produce.py boards, not yet approved.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/pr-production.sh"
