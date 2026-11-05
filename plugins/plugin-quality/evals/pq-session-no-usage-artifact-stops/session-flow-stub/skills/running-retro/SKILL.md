---
description: "Mid-session retro checkpoint: a subagent files findings from the transcript so far into a running ledger, never applied; `arm` runs it after the session ends. Use when: 'running retro', 'checkpoint this session', 'watch this session in the background', or on a /loop."
argument-hint: "[topic|arm]"
user-invocable: true
disable-model-invocation: false
---

# Running retro (eval stand-in)

## Ledger

The ledger lives at `.work/running-retros/`. A session's ledger is the file matching
`*-running-retro-*.md` whose frontmatter `session_id` is that session. Its frontmatter key
`plugin_usage` is one line of JSON, `{"skills": {"<plugin>:<skill>": <count>}}`, stamped at each
checkpoint. The ledger frontmatter is the contract other plugins read (`/plugin-quality:audit
session` finds the ledger by `session_id` and reads `plugin_usage`).
