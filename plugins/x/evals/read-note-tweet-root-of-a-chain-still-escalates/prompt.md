---
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Escalates to step 2. isNoteTweet: true describes the post''s long-form representation, not the absence of replies — a chain can begin with a note tweet, and the explicit thread request plus the 1/ marker are positive continuation evidence.'
---

/x:read https://x.com/someone/status/3333333333333333333

I want the whole thread.

(The /api/fetch response carries isNoteTweet: true and a long body ending with the marker 1/.)
