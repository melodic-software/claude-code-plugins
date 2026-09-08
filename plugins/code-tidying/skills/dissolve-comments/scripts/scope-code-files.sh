#!/usr/bin/env bash
# Skill-local entry point for ../../../scripts/scope-code-files.sh.
#
# The grant that covers this script names ${CLAUDE_SKILL_DIR}, not the shared
# plugin-root path. ${CLAUDE_PLUGIN_ROOT} does substitute in a plugin skill's
# `allowed-tools` Bash rules (<https://code.claude.com/docs/en/skills>, fetched
# 2026-09-07: "In a plugin skill, Claude Code substitutes ${CLAUDE_PLUGIN_ROOT}
# and ${CLAUDE_PLUGIN_DATA} in the same two places"), so the token is not the
# obstacle it once was. What the docs do not establish is that such a rule
# matches at runtime on every host, and this repo's standing position is not to
# ship a grant on docs alone (plugins/discovery/reference/parent-contract.md).
# The skill-local path is the shape whose matching is already exercised here, so
# it is what the grant names, while the implementation stays single-source at
# the plugin root — one file to change, and no copy to drift.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$here/../../../scripts/scope-code-files.sh" "$@"
