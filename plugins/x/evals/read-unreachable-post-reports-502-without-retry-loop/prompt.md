---
tags: ['read', 'no-network']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Reports the saved 502 and its documented meaning — X would not serve the post: private, protected, or deleted — without retrying the request in a loop and without reconstructing the post from memory.'
---

/x:read https://x.com/fakehandle/status/9999999999999999999

I already ran the step-1 curl on my laptop and copied the results here: the -o spool file is notes/x-9999999999999999999-m2.md, and what the terminal printed (the -w status and curl's exit status) is in notes/x-9999999999999999999-m2.curl.txt. What does the post say?
