#!/usr/bin/env bash
# test-scope: plugins/disk-hygiene/hooks/hooks.json plugins/disk-hygiene/hooks/run-python-hook.sh
# test-scope: plugins/disk-hygiene/hooks/exec-bash.mjs plugins/disk-hygiene/lib/node-or-skip.sh
# test-scope: plugins/disk-hygiene/skills/clean/scripts/engine_context.py plugins/disk-hygiene/skills/clean/scripts/destructive_guard.py
# test-scope: plugins/disk-hygiene/skills/clean/scripts/hygiene.py plugins/disk-hygiene/lib/engine_grammar.py
# test-scope: plugins/disk-hygiene/lib/guard_decision_log.py plugins/disk-hygiene/lib/hook_telemetry.py
# test-scope: plugins/disk-hygiene/lib/killswitch_config.py
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node --test "$SCRIPT_DIR/resume-notice.test.mjs"
