#!/usr/bin/env bash
# Skill-local entry point for ../../../scripts/change-shape.py.
#
# The grant that covers this script names ${CLAUDE_SKILL_DIR}, not the shared
# plugin-root path. Where ${CLAUDE_PLUGIN_ROOT} is substituted is the skills
# page's "Available string substitutions" section:
# <https://code.claude.com/docs/en/skills#available-string-substitutions>
# (as of 2026-10-11; recheck when that section changes where plugin variables
# are substituted, or documents that a plugin-root `allowed-tools` rule matches
# at runtime). What the docs do not establish is that a plugin-root
# `allowed-tools` rule matches at runtime on every host,
# and this repo's standing position is not to ship a grant on docs alone
# (plugins/discovery/reference/parent-contract.md). The skill-local path is the
# shape whose matching is already exercised here, so it is what the grant names,
# while the implementation stays single-source at the plugin root: one file to
# change, and no copy to drift.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$here/../../../scripts/change-shape.py" "$@"
