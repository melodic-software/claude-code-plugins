---
description: "Reaches SKILL.md 'Run it' (print the script's output verbatim, never re-query a section by hand; on unreadable sections say which were lost and why, then stop) and 'Degraded sections' (UNREADABLE is never 'none' or clear). Fixture flags keep the run offline; the PR list is a GitHub error document, so merge-ready renders UNREADABLE. Needs --scaffold --allow-tools Bash Write Edit."
tags: [harness-ops, morning-brief, outcome, degraded-section]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash, Write, Edit]
expected_outcome: "The skill runs morning-brief.sh once with the fixture flags, prints its brief (the RECOMMENDED line for #412 and the STALE babysit lane included), says the merge-ready section was lost because the PR list could not be parsed, never reports merge-ready as none or clear, and does not rebuild the section with gh or by parsing brief/prs.json itself."
---

/harness-ops:morning-brief --now 2026-07-20T08:00Z --counts-json brief/counts.json --repo-labels-json brief/labels.json --pr-json brief/prs.json --decisions-json brief/decisions.json --telemetry-json brief/telemetry.json --merged-json brief/merged.json
