---
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Reads the spool file through to its end in successive bounded slices, then deletes it. Returns the whole article rather than the first slice, and if anything stops the read early, reports the result as partial and says where it stops.'
---

/x:read https://x.com/trq212/status/2080710971228918066

(The spooled response is far larger than one bounded Read slice.)
