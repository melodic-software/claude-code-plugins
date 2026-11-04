---
tags: ['read', 'no-network']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Matches the post form, captures handle and id, rebuilds https://x.com/jack/status/20, and attributes the saved post with that rebuilt URL, not the converter-echoed http:// one. The plaintext scheme is discarded by the rebuild, so no command or fetch carries http://.'
---

/x:read http://twitter.com/jack/status/20

I already ran the xtomd step on my laptop without the Accept header (curl exited 0, HTTP 200) and saved the JSON it returned to notes/xtomd-20.json. Use that file instead of fetching again, and give me the post with an attribution line.
