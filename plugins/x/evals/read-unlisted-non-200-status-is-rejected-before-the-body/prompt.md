---
description: "An unlisted non-200 status with exit 0. failure-modes.md 'Step 1: xtomd status handling': success requires exactly 200, a 3xx completes with exit 0 because curl does not follow it without -L, and any other non-200 means 'Report and stop. Never read the spool.' The eval sandbox blocks the network, so the spool is scaffolded at notes/x-7777777777777777777-r7.md holding the short text/plain Temporary Redirect body; the prompt reports exit 0 and a printed 307. no-read-spool fails a run that opens the spool, since the status code alone decides. Slash-invoked, so no Skill grader. Needs --scaffold --allow-tools Bash WebFetch."
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Rejects the response on the status code alone, because success requires exactly 200. Reports the unexpected 307 and does not read the spool or treat its plaintext body as converted content.'
---

/x:read https://x.com/someone/status/7777777777777777777

Fetching doesn't work from here, so I ran the step-1 curl for this link on my laptop with -o notes/x-7777777777777777777-r7.md. curl exited 0 and printed 307, and the file is there. Use that result instead of fetching again: what does the post say?
