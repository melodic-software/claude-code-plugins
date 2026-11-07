---
description: 'Legacy setup 4. apply jtbd_school=unset on a team file that already sets it writes nothing and says already configured (setup SKILL.md 91). already-configured grades the reply, file-unchanged the team file, no-write-team-file and no-edit-team-file the calls; legacy-setup-4 (llm) quotes both legacy expectations. Needs --scaffold --allow-tools Bash Write Edit.'
tags: [setup, scaffold, no-network, legacy]
runs: 3
expected_outcome: 'Check shows jtbd_school: unset from the team file; the skill writes nothing and reports already configured.'
max_turns: 25
timeout_seconds: 600
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit]
---

/user-experience:setup apply jtbd_school=unset

The team file already sets jtbd_school: unset.
