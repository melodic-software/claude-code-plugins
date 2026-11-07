---
description: "A report naming `paginaton()`, a likely misspelling of pagination, gets one clarifying question or an explicit possible-typo flag instead of a report silently written against the corrected name. write SKILL.md Gotchas: do not auto-fix typos in the description; ask one question."
tags: [bugs, write, outcome, no-network]
max_turns: 8
timeout_seconds: 300
allowed_tools: [Skill, Bash, Read, Glob, Grep]
expected_outcome: "The reply asks which symbol the user means, or flags `paginaton` as a possible typo, before finalizing any report; it does not emit a report against `pagination` as if that name were confirmed."
---

/bugs:write There's a bug in `paginaton()`: it skips the last row of each page when the page size is small. Report it.
