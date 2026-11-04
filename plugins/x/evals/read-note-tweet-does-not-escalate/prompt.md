---
tags: ['read', 'no-network']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Returns the full note tweet from the saved step-1 result alone, without escalating to Thread Reader App because the post is long, is a note tweet, or has many replies.'
---

/x:read https://x.com/fakehandle/status/2015883857489522876

I already ran step 1 against xtomd's /api/fetch on my laptop (curl exited 0, HTTP 200) and saved the JSON it returned to notes/xtomd-fetch-2015883857489522876.json. Use that file instead of re-running step 1.
