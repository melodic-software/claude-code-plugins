#!/usr/bin/env bash
# Part c of the babysit-prs engine's unittest suite: tests/test_babysit_postmerge*.py.
# engine-run.sh assigns the parts; engine.test.sh, engine-b.test.sh and
# engine-d.test.sh run the rest.
#   bash plugins/source-control/skills/babysit-prs/scripts/engine-c.test.sh
# test-scope: plugins/source-control/*.md plugins/source-control/scripts/babysit-*.sh
# test-scope: plugins/source-control/skills/babysit-prs/scripts/*.py plugins/source-control/skills/babysit-prs/scripts/babysit-python.sh plugins/source-control/skills/babysit-prs/scripts/engine-run.sh
# test-scope: plugins/*/hooks/* docs/conventions/source-control.yaml docs/conventions/pr-pipeline.yaml .github/actions/check-kill-switch/check-kill-switch.mjs .github/actions/check-trusted-trigger/check-trusted-trigger.mjs .github/scripts/pr-merge/carry-run-cache.mjs .github/scripts/pr-merge/head-ref-map.mjs .github/scripts/pr-merge/rotation.mjs .github/scripts/pr-verify/resolve-pr.mjs plugins/source-control/lib/parse-concern-value.sh plugins/source-control/lib/yaml-subset.awk plugins/source-control/skills/babysit-loop/scripts/*.mjs plugins/source-control/skills/babysit-prs/scripts/tests/fixtures/*/*.json plugins/work-items/reference/escalation-marker.md
exec bash "$(dirname "${BASH_SOURCE[0]}")/engine-run.sh" c
