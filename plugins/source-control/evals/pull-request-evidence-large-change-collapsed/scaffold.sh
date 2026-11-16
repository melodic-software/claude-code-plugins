#!/usr/bin/env bash
# Seeds PR 412 with three acceptance criteria and matching base and head drive reports
# (fixtures/evidence-pr.sh).
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/evidence-pr.sh" 3
