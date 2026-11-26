#!/usr/bin/env bash
set -euo pipefail
d="$1" window="$2" model_window="${3:-}"
mkdir -p "$d/.claude"
if [[ -z "$model_window" ]]; then
  printf '{\n  "autoCompactWindow": %s\n}\n' "$window" >"$d/.claude/settings.json"
else
  [[ "${PROBE_MODEL:?set by probe.py}" =~ ^[A-Za-z0-9._:-]+$ ]] || {
    echo "autocompact-project.sh: model id '$PROBE_MODEL' is not a plain model name" >&2
    exit 2
  }
  printf '{\n  "autoCompactWindow": %s,\n  "modelSettings": {\n    "%s": { "autoCompactWindow": %s }\n  }\n}\n' \
    "$window" "$PROBE_MODEL" "$model_window" >"$d/.claude/settings.json"
fi
