---
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Emits the -o target and the delete with the concrete path in single quotes, so the $user segment is passed through literally rather than expanded by the shell. The file written and the file read are the same path.'
---

/x:read https://x.com/jack/status/20

(The resolved plugin data directory is /c/Users/dev$user/.claude/plugin-data/x.)
