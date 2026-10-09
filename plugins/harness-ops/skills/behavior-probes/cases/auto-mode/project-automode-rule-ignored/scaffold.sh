#!/usr/bin/env bash
set -euo pipefail
work="${PROBE_WORKDIR:?set by probe.py}"
mkdir -p "$work/.claude"
cp "${PROBE_CASE_DIR:?set by probe.py}/project-settings.json" "$work/.claude/settings.json"
