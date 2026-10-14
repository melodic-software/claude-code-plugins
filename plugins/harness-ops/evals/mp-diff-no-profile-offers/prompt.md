---
description: "Reaches SKILL.md 'Actions' (diff runs profile.sh diff; record writes only with --confirm after the operator's yes in that turn) and 'Where the profile lives' (a missing document reads as no profile for this machine and offers to produce one, with no fallback). The eval's plugin data dir starts empty, so diff exits 3. No scaffold. Needs --allow-tools Bash Write Edit."
tags: [harness-ops, machine-profile, outcome, missing-input]
max_turns: 12
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The skill runs profile.sh diff, reports that no profile is stored for this machine (not that nothing changed), offers to run the profile action to produce one, and records nothing: no record --confirm, and no hand-written profile.json."
---

/harness-ops:machine-profile diff
