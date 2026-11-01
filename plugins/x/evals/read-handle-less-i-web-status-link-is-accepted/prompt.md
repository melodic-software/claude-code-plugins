---
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Matches the handle-less post form, captures the numeric id, and rebuilds https://x.com/i/web/status/1234567890123456789. No handle is invented for the rebuilt URL; the author handle in the attribution comes from the converted body as always.'
---

/x:read https://x.com/i/web/status/1234567890123456789
