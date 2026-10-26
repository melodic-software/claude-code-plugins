#!/usr/bin/env bash
# autocompact-project.sh <dir> <window> [<model window>]: writes the project
# settings file <dir>/.claude/settings.json with a top-level autoCompactWindow
# and, when <model window> is given, a modelSettings entry for $PROBE_MODEL, the
# model the case runs. No case runs /autocompact with an argument, so none saves
# to the operator's user settings.
set -euo pipefail
d="$1" window="$2" model_window="${3:-}"
mkdir -p "$d/.claude"
if [[ -z "$model_window" ]]; then
  printf '{\n  "autoCompactWindow": %s\n}\n' "$window" >"$d/.claude/settings.json"
else
  # The id goes into a JSON key unescaped.
  [[ "${PROBE_MODEL:?set by probe.py}" =~ ^[A-Za-z0-9._:-]+$ ]] || {
    echo "autocompact-project.sh: model id '$PROBE_MODEL' is not a plain model name" >&2
    exit 2
  }
  printf '{\n  "autoCompactWindow": %s,\n  "modelSettings": {\n    "%s": { "autoCompactWindow": %s }\n  }\n}\n' \
    "$window" "${PROBE_MODEL:?set by probe.py}" "$model_window" >"$d/.claude/settings.json"
fi
