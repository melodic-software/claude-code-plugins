#!/usr/bin/env bash
# test-scope: plugins/playbooks/.claude-plugin/plugin.json plugins/playbooks/reference/repo-sweep-plan-page.html plugins/playbooks/reference/html-tokens.css plugins/playbooks/skills/repo-sweep/scripts/render.sh plugins/playbooks/skills/repo-sweep/scripts/apply-branding.mjs plugins/playbooks/lib/view-settings.mjs plugins/playbooks/lib/plugin-options.mjs
set -euo pipefail
exec node --test --test-concurrency=4 "$(dirname "${BASH_SOURCE[0]}")/render-branding.test.mjs"
