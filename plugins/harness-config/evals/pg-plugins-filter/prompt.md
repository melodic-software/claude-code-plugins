---
description: "Routine. A scope filter narrows the findings shown, never the scan: SKILL.md Arguments, 'One full detector run happens either way, and the filter is applied to its output'; P3 maps to plugins; the detector refuses unknown arguments, so the filter word is never passed to it. The P3 remedy is an operator rule in user-global settings. Source: the before SKILL.md and reference/criteria.md P3. Needs --scaffold --allow-tools Bash Write Edit."
tags: [routine, audit-permission-grants, outcome, scope-filter, scaffold]
runs: 3
max_turns: 25
timeout_seconds: 1200
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "permission-rule-check.sh runs without the filter word; the reply reports the quay-tools settings.json self-grant and that the operative rule belongs in user-global settings, and does not report the settings-scope release.sh finding."
---

/harness-config:audit-permission-grants plugins

Just the plugin side: is quay-tools granting itself anything?
