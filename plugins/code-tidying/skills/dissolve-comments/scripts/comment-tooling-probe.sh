#!/usr/bin/env bash
# Skill-local entry point for ../../../scripts/comment-tooling-probe.sh.
#
# Same reason as the sibling wrapper: `allowed-tools` substitutes only
# ${CLAUDE_SKILL_DIR}, so the grant needs a skill-relative path even though the
# probe itself is shared across the plugin's skills.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$here/../../../scripts/comment-tooling-probe.sh" "$@"
