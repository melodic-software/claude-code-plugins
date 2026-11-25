#!/usr/bin/env bash
# test-scope: .github/source-control-settings.json plugins/source-control/.claude-plugin/plugin.json
# test-scope: plugins/source-control/*.md plugins/source-control/scripts/babysit-*.sh
# test-scope: plugins/source-control/skills/babysit-prs/scripts/*.py plugins/source-control/skills/babysit-prs/scripts/babysit-python.sh plugins/source-control/skills/babysit-prs/scripts/engine-run.sh
# test-scope: plugins/*/hooks/* docs/conventions/source-control.yaml docs/conventions/pr-pipeline.yaml .github/actions/check-kill-switch/check-kill-switch.mjs .github/actions/check-trusted-trigger/check-trusted-trigger.mjs .github/scripts/lib/github-client.mjs .github/scripts/lib/trusted-actors.mjs .github/scripts/pr-merge/carry-run-cache.mjs .github/scripts/pr-merge/head-ref-map.mjs .github/scripts/pr-merge/rotation.mjs .github/scripts/pr-verify/resolve-pr.mjs plugins/source-control/lib/parse-concern-value.sh plugins/source-control/lib/yaml-subset.awk plugins/source-control/skills/babysit-loop/scripts/*.mjs plugins/source-control/skills/babysit-prs/scripts/tests/fixtures/*/*.json plugins/work-items/reference/escalation-marker.md
# test-scope: .github/workflows/*.yml .github/actions/log-api-budget/rate-limits.json plugins/source-control/skills/babysit-prs/scripts/tests/fixtures/postmerge/job-log-bash-ui-fail.txt
exec bash "$(dirname "${BASH_SOURCE[0]}")/engine-run.sh" c
