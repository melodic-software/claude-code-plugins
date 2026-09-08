#!/usr/bin/env bash
# Skill-local entry point for ../../../scripts/changed-code-files.sh.
#
# The grant covering this script names ${CLAUDE_SKILL_DIR}. ${CLAUDE_PLUGIN_ROOT}
# does substitute in a plugin skill's `allowed-tools` Bash rules
# (<https://code.claude.com/docs/en/skills>, fetched 2026-09-07), but the docs do
# not establish that such a rule matches at runtime on every host, and this
# repo does not ship a grant on docs alone
# (plugins/discovery/reference/parent-contract.md). The skill-local path is the
# exercised shape; the implementation stays single-source at the plugin root.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$here/../../../scripts/changed-code-files.sh" "$@"
