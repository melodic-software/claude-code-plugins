#!/usr/bin/env bash
# cwd-probe-agent.sh <dir>: after hub-layout.sh <dir>, a project subagent cwd-probe in
# <dir>/repos/github.com/acme/hub/.claude/agents/ that holds only Bash and runs the
# one command its task names.
set -euo pipefail
d="${1:?usage: cwd-probe-agent.sh <dir>}"
hub="$d/repos/github.com/acme/hub"
[[ -d "$hub/.git" ]] || { echo "cwd-probe-agent.sh: run hub-layout.sh $d first" >&2; exit 2; }
mkdir -p "$hub/.claude/agents"
cat >"$hub/.claude/agents/cwd-probe.md" <<'EOF'
---
name: cwd-probe
description: Behavior-probe subagent that prints its working directory once.
tools: Bash
---

Make exactly the one Bash call your task names, once, character for character,
then report the tool result verbatim. Make no other tool call.
EOF
