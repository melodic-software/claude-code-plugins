---
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Matches the post form, captures handle and id, and rebuilds https://x.com/jack/status/20 — sending no query string to the third party. The original input string is discarded rather than passed through.'
---

/x:read https://twitter.com/jack/status/20?s=20&t=AbCdEfGhIjKlMnOp
