---
description: "A request to file missing PDF export as a bug is recognized as a feature request and routed away, with no five-field report"
tags: [bugs, write, outcome, skip-condition]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Bash, Read, Glob, Grep]
expected_outcome: "The reply calls this a feature request (a missing capability, not a defect), emits no five-field bug report (no steps-to-reproduce section, no severity line), and recommends a feature-request or product-intake path."
---

/bugs:write File a bug: our export screen has no way to export to PDF, only CSV. Users keep asking for PDF export and we don't support it. Report this as a bug so we can fix it.
