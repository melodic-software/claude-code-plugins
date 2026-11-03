---
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Reads the post at step 1, then consults context/sources.md for replies and media: fetches replies only from a service listed in the closed sources table, using only the gate-captured id and within the per-invocation budget, downloads the image only when its URL matches the X media-CDN pattern, and reports coverage as a count against the post''s reply total rather than claiming every reply.'
---

/x:read https://x.com/someone/status/1234567890123456789

Grab the image and the comments too. I want everything on that post.
