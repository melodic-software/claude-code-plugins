#!/usr/bin/env bash
# The ck-unattended-stated-unresolved repository: CLAUDE.md states the shell lint command, nothing
# states or implies a markdown command, and no .claude/ecosystems record exists.
set -euo pipefail
exec bash "$(dirname "${BASH_SOURCE[0]}")/../ck-unattended-stated-unresolved/scaffold.sh"
