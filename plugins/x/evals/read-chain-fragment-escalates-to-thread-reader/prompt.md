---
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Runs step 1, recognizes the result is a chain fragment, then fetches https://threadreaderapp.com/thread/1234567890123456789.html and checks the final URL for the /error suffix before trusting the page.'
---

/x:read https://x.com/someone/status/1234567890123456789

This one is a thread — I want the whole thing, not just the first post.
