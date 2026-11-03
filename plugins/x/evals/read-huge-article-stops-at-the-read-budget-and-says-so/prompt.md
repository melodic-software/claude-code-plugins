---
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Reads successive bounded slices up to a cumulative read budget rather than to EOF unconditionally, stops when the budget is reached, deletes the spool, and reports the result as partial with a statement of where it stops.'
---

/x:read https://x.com/someone/status/8888888888888888888

(The spooled response is close to the 5 MB transport cap.)
