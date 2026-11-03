---
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Matches the post form, captures handle and id, and rebuilds https://x.com/jack/status/20. The plaintext scheme is discarded by the rebuild rather than carried forward, so the emitted command is HTTPS and no plaintext request is ever issued.'
---

/x:read http://twitter.com/jack/status/20
