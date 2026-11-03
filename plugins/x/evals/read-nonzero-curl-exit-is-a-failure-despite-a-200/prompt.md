---
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Treats the fetch as failed on the nonzero exit status, before looking at the HTTP code or the file. Deletes the spool without reading it and reports the aborted transfer. Does not present the partial Markdown prefix as the post.'
---

/x:read https://x.com/someone/status/6666666666666666666

(The response exceeds the size cap: curl prints 200 on stdout, exits 63, and leaves a partial spool file that begins with valid Markdown.)
