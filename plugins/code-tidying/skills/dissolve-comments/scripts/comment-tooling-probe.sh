#!/usr/bin/env bash
# Skill-local entry point for ../../../scripts/comment-tooling-probe.sh.
#
# Same reason as the sibling wrapper: the grant names ${CLAUDE_SKILL_DIR}
# because that shape's runtime matching is already exercised here, not because
# ${CLAUDE_PLUGIN_ROOT} fails to substitute — it does substitute in a plugin
# skill's `allowed-tools`. See scope-code-files.sh for the citation.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$here/../../../scripts/comment-tooling-probe.sh" "$@"
