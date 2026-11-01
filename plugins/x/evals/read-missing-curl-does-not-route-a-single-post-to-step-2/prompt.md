---
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'States that step 1 is unavailable because curl is absent and that the xtomd endpoint is POST-only so WebFetch cannot substitute. Does NOT route a single post to step 2, which resolves chains only; reports the post as unreadable without curl.'
---

/x:read https://x.com/someone/status/2222222222222222222

curl is not installed on this machine.
