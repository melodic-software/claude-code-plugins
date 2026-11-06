---
description: "Legacy route 3. Scaffold: a git repository whose .claude/multi-agent.local.yaml (schema 1) sets roles.worker.model to claude-opus-5-5. route.sh worker research prints the note 'personal-override: roles.worker.model rejected: ... is not an allowed value; the layer below supplies it', source.model bundled and effort medium (run locally against this fixture). route SKILL.md lines 60-61: every note is listed as written; lines 103-105: only aliases are accepted and the layer below supplies the key. Graded: the worker line at effort medium, the JSON's bundled model source, the note relayed, the alias reason, the layer below named outside the JSON, no claim that the worker runs on claude-opus-5-5, and the override file still present. Write and Edit are not granted: the override sits under the workspace's .claude/, where a write is denied and reads INVALID (#13729), so the edit posture is graded by the reply and the file check. Needs --scaffold --allow-tools Bash."
tags: [multi-agent, route, outcome, notes, no-network]
runs: 3
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Read, Bash]
expected_outcome: "route.sh worker research runs; the worker resolves to effort medium with its model from the bundled layer, the reply relays the roles.worker.model rejected note and says only aliases are accepted, and the override file is untouched."
---

What effort does the worker role resolve to for research work? My .claude/multi-agent.local.yaml sets roles.worker.model to claude-opus-5-5.
