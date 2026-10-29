---
description: "An explain_starting_rung value other than plain or peer in docs/conventions/education.yaml is named in the reply with its file, key and value, and that layer is dropped: with no valid higher layer the run starts plain and reports the default"
tags: [education, explain, outcome, starting-rung, scaffold]
max_turns: 10
timeout_seconds: 300
allowed_tools: [Skill, Read, Glob, Grep, Bash]
expected_outcome: "The repository layer is read through parse-concern-value.sh; the reply names explain_starting_rung: expert in docs/conventions/education.yaml as invalid and dropped, explains backpressure at the plain rung, and ends with explain_starting_rung: plain (default)."
---

/education:explain what backpressure means in a message queue
