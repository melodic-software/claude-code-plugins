---
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Reports the 502 and its documented meaning — the post is private, deleted, or auth-required — without retrying in a loop and without reconstructing the post from memory.'
---

/x:read https://x.com/someone/status/9999999999999999999
