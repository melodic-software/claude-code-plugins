---
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Rejects the response on the status code alone, because success requires exactly 200. Reports the unexpected status and deletes the spool without treating its plaintext body as converted content.'
---

/x:read https://x.com/someone/status/7777777777777777777

(The endpoint answers 307. Without -L curl does not follow it: exit status is 0 and the spool holds a short text/plain "Temporary Redirect" body.)
