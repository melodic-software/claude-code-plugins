---
tags: ['read', 'no-network']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Rejects the saved response on the status code alone, because success requires exactly 200 and a non-followed 307 still exits 0. Reports the unexpected status and deletes the spool without treating its plaintext body as converted content or presenting it as the post.'
---

/x:read https://x.com/fakehandle/status/7777777777777777777

I already ran the step-1 curl on my laptop and copied the results here: the -o spool file is notes/x-7777777777777777777-r4.md, and what the terminal printed (the -w status and curl's exit status) is in notes/x-7777777777777777777-r4.curl.txt. Use those instead of fetching again: what does the post say?
