---
description: "The audit lists a record whose decided thing no longer exists in the code as a retire candidate, with evidence, and changes nothing"
tags: [architecture, record-decision, outcome, scaffold]
max_turns: 25
timeout_seconds: 600
allowed_tools: [Skill, Bash, Read, Glob, Grep, Write, Edit]
expected_outcome: "The final reply lists ADR 0001 (Redis sessions) as a retire candidate because Redis no longer exists in the code, citing the commit or search that shows it, and does not list ADR 0002 as gone. No Write or Edit call is made and no shell command removes, moves or writes a file."
---

/architecture:record-decision audit
