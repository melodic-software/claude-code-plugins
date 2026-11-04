---
tags: ['read', 'no-network']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Matches the handle-less post form and rebuilds https://x.com/i/web/status/1234567890123456789, then reads the saved conversion. No handle is invented for the rebuilt URL, and the converter-echoed URL is not used; the author handle in the attribution comes from the converted body.'
---

/x:read https://x.com/i/web/status/1234567890123456789

I already ran the xtomd step on my laptop without the Accept header (curl exited 0, HTTP 200) and saved the JSON it returned to notes/xtomd-1234567890123456789.json. Use that file instead of fetching again: what does the post say, and who posted it?
