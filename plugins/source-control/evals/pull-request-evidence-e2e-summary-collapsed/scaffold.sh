#!/usr/bin/env bash
# Seeds PR 412 with one acceptance criterion and base and head e2e-summary.json files whose flat
# publishable lists map no capture to an entry point (fixtures/evidence-pr.sh).
set -euo pipefail

bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/evidence-pr.sh" 1 --e2e
