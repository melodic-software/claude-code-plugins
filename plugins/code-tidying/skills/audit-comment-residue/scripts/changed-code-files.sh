#!/usr/bin/env bash
# Skill-local entry point for ../../../scripts/changed-code-files.sh.
#
# A permission grant in `allowed-tools` can only name ${CLAUDE_SKILL_DIR};
# ${CLAUDE_PLUGIN_ROOT} is never substituted there, so a grant naming the shared
# path is inert and the injected command it guards aborts under default
# permissions. This exec gives the grant a path it can match while the
# implementation stays single-source at the plugin root.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$here/../../../scripts/changed-code-files.sh" "$@"
