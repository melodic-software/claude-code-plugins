#!/usr/bin/env bash
# A git repository whose .claude/settings.json sets "disableWorkflows": true, a switch workflow-availability.sh reads.
set -euo pipefail
bash "$(dirname "${BASH_SOURCE[0]}")/../fixtures/workspace.sh" disabled
