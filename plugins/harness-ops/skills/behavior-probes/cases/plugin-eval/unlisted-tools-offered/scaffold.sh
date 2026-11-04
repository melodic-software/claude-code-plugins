#!/usr/bin/env bash
set -euo pipefail
work="${PROBE_WORKDIR:?set by probe.py}"
cp "${PROBE_LIB:?set by probe.py}/eval-tools-check.py" "$work/eval-tools-check.py"

plugin="$work/eval-tools-plugin"
mkdir -p "$plugin/.claude-plugin" "$plugin/skills/probe-skill" \
  "$plugin/evals/unlisted-tools/graders"

cat >"$plugin/.claude-plugin/plugin.json" <<'EOF'
{ "name": "eval-tools-probe", "version": "0.0.0", "description": "Fixture for the plugin-eval behavior probe" }
EOF

cat >"$plugin/skills/probe-skill/SKILL.md" <<'EOF'
---
description: Fixture skill for a tool-availability probe. Reply with the word loaded.
---

Reply with the word loaded.
EOF

# allowed_tools omits Skill and Task; the run passes no --allow-tools grant.
cat >"$plugin/evals/unlisted-tools/prompt.md" <<'EOF'
---
runs: 1
max_turns: 12
timeout_seconds: 300
allowed_tools: [Read, Glob, Grep]
---

This is a tool-availability test. Make each of these four tool calls once, in this order, and
continue to the next after any error or refusal. Skip a call only when that tool is not available
to you at all.

1. Skill, with skill `eval-tools-probe:probe-skill`.
2. Task (also called Agent), with description `probe` and prompt `Reply with the word done.`
3. TaskStop, with task_id `probe-none`.
4. ToolSearch, with query `select:Read`.

Then reply with the word finished.
EOF

cat >"$plugin/evals/unlisted-tools/graders/replied.md" <<'EOF'
---
type: regex
target: last_message
pattern: finished
---
EOF
