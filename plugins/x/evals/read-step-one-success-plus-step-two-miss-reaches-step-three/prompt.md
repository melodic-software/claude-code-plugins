---
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Recognizes the thread is known-truncated even though step 1 succeeded, and reaches step 3 — reporting what each step did and asking for the remaining post URLs. Never presents the root alone as the complete thread.'
---

/x:read https://x.com/someone/status/4444444444444444444

(Step 1 succeeds and returns a chain root with isNoteTweet: false; the Thread Reader App page for that id redirects to /error.)
