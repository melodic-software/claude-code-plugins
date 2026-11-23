#!/usr/bin/env bash
# test-scope: lib/cdn-pins/package.json lib/cdn-pins/package-lock.json lib/cdn-pins/pins.json plugins/architecture/scripts/deepening-report.mjs plugins/architecture/scripts/deepening-report.test.mjs plugins/architecture/skills/improve/research/deepening/html-report.md plugins/architecture/evals/deepening-report-on-chrome-with-counts/samples/csp-pins-mermaid.json plugins/architecture/evals/deepening-report-on-chrome-with-counts/samples/csp-pins-tailwind.json lib/cdn-pins/fixtures/fake-fetch.mjs .github/actions/resolve-config/patch-rules.json .github/scripts/apply-patch/cdn-paths.mjs
set -euo pipefail
exec node --test "$(dirname "${BASH_SOURCE[0]}")/sync.test.mjs"
