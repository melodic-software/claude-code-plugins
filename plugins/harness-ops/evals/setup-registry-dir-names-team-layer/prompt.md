---
description: "Explicit check in a git repository whose docs/conventions/harness-ops.yaml sets registry_dir: tools/registry. setup SKILL.md probe 1 resolves registry_dir through the bundled scripts/registry-dir.mjs and reports the layer that supplied it: here team, from docs/conventions/harness-ops.yaml, whatever the host's own registry_dir option renders, because the team file beats the option. ran-registry-resolver is a with-only indicator: the script ships only with the plugin. Needs --scaffold --allow-tools Bash Write Edit (Write and Edit are granted so the must-not graders can fail)."
tags: ['harness-ops', 'setup', 'check', 'config-cascade', 'read-only']
max_turns: 14
timeout_seconds: 360
allowed_tools: [Read, Glob, Grep, Skill, Bash, Write, Edit]
expected_outcome: 'Runs registry-dir.mjs and reports registry_dir from the team layer, docs/conventions/harness-ops.yaml, resolving to tools/registry; writes and edits nothing.'
---

/harness-ops:setup check
