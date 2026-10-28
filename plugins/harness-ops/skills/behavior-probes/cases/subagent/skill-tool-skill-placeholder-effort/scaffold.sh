#!/usr/bin/env bash
set -euo pipefail
d="${PROBE_WORKDIR:?set by probe.py}"
bash "${PROBE_LIB:?set by probe.py}/effort-probe.sh" "$d"

# The shared agents preload print-effort, so a driver that picked one would measure
# the preloaded path. The only agent left has no skills key and loads it through
# the Skill tool.
rm "$d/.claude/agents/effort-probe.md" "$d/.claude/agents/effort-probe-unpinned.md"
cat >"$d/.claude/agents/effort-probe-skill-tool.md" <<'EOF'
---
name: effort-probe-skill-tool
description: Behavior-probe subagent that loads a skill through the Skill tool and prints its own effort level once.
tools: Bash, Skill
effort: low
---

Load the skill your task names with the Skill tool, then make exactly the one Bash call that skill
names, once, character for character, and report the tool result verbatim. Make no other tool call.
EOF
