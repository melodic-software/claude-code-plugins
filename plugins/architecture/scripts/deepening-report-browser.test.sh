#!/usr/bin/env bash
# test-scope: plugins/architecture/scripts/deepening-report.mjs plugins/architecture/scripts/build-view.mjs plugins/architecture/scripts/testdata/deepening-candidates.json plugins/architecture/reference/html-chrome.html
set -euo pipefail
exec node "$(dirname "${BASH_SOURCE[0]}")/deepening-report-browser.test.mjs"
