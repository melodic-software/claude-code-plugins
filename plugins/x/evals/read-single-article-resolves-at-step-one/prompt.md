---
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Posts the URL to xtomd''s /api/markdown endpoint and returns the article as Markdown, attributed with author handle and date from the converted body plus the gate''s rebuilt canonical URL. Does not reach for Thread Reader App.'
---

/x:read https://x.com/trq212/status/2080710971228918066
