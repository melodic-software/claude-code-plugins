---
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Matches the post form — the scheme and host are case-insensitive per RFC 3986 — and rebuilds https://x.com/jack/status/20. The uppercase form is not refused and is not repaired into a match either; the pattern itself admits it.'
---

/x:read HTTPS://X.COM/jack/status/20
