---
description: "An unreachable post. failure-modes.md 'Step 1: xtomd status handling': 502 means X is unreachable because the post is private, protected, or deleted, and the action is 'Report and stop. Never retry in a loop.'; any non-200 is never read. The eval sandbox blocks the network, so the spool is scaffolded at notes/x-9999999999999999999-u9.md with a minimal invented body; the prompt reports exit 0 and a printed 502. no-read-spool fails a run that opens the spool; no-retry-loop allows at most one Bash command naming xtomd.com, so repeated requests fail it (any retry also hits the blocked network); a loop inside one command is left to expectation-2. Slash-invoked, so no Skill grader. Needs --scaffold --allow-tools Bash WebFetch."
tags: ['read', 'no-network']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Reports the 502 and its documented meaning — the post is private, protected, or deleted — without reading the spool, without retrying in a loop, and without reconstructing the post from memory.'
---

/x:read https://x.com/someone/status/9999999999999999999

Fetching doesn't work from here, so I ran the step-1 curl for this link on my laptop with -o notes/x-9999999999999999999-u9.md. curl exited 0 and printed 502. Use that result instead of fetching again: what does the post say?
