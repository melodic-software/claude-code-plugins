---
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Treats the 200 as a failed fetch because the response carries no converted content, and reports it as such. Does not present the HTML or an empty result as the post.'
---

/x:read https://x.com/someone/status/5555555555555555555

(The endpoint returns HTTP 200 with an HTML bot-challenge body and no markdown field.)
