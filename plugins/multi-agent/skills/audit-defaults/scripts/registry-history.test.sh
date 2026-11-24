#!/usr/bin/env bash
# test-scope: plugins/multi-agent/skills/audit-defaults/scripts/registry-history.mjs plugins/multi-agent/skills/route/scripts/lib/trials.mjs plugins/multi-agent/scripts/resolve-roles.sh plugins/multi-agent/reference/defaults.yaml
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "SKIP: node not installed" >&2
  exit 0
fi

exec node --test "$SCRIPT_DIR/registry-history.test.mjs"
