#!/usr/bin/env bash
# Skill-local entry point for ../../../scripts/changed-code-files.sh.
#
# The grant covering this script names ${CLAUDE_SKILL_DIR}. The docs say where
# ${CLAUDE_PLUGIN_ROOT} is substituted in
# <https://code.claude.com/docs/en/skills#available-string-substitutions>
# (as of 2026-10-11), but the docs do not establish that a plugin-root
# `allowed-tools` rule matches at runtime on every host, and this repo does not
# ship a grant on docs alone (plugins/discovery/reference/parent-contract.md).
# The skill-local path is the exercised shape; the implementation stays
# single-source at the plugin root. Recheck when that section changes where
# plugin variables are substituted, or documents that such a rule matches at
# runtime.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$here/../../../scripts/changed-code-files.sh" "$@"
