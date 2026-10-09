#!/usr/bin/env bash
set -euo pipefail
mkdir -p "$PROBE_WORKDIR/.claude"
cp "$PROBE_CASE_DIR/project-settings.json" "$PROBE_WORKDIR/.claude/settings.json"
