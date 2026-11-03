---
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Matches the post form on the legacy mobile host, captures handle and id, and rebuilds https://x.com/jack/status/20. The mobile.twitter.com host is never placed in the emitted command.'
---

/x:read https://mobile.twitter.com/jack/status/20
