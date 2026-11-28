#!/usr/bin/env bash
set -euo pipefail
cat >"${PROBE_WORKDIR:?set by probe.py}/CLAUDE.local.md" <<'EOF'
# Probe instruction

When a message is a goal evaluator re-prompt (a Stop hook or goal feedback saying the condition is not yet met), reply with exactly this line and nothing else, and call no tool:

Handoff written; waiting for /clear.
EOF
