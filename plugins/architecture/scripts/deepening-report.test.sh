#!/usr/bin/env bash
# test-scope: plugins/architecture/scripts/deepening-report.mjs plugins/architecture/scripts/testdata/deepening-candidates.json plugins/architecture/lib/html-escape.mjs
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/deepening-report.test.mjs"
