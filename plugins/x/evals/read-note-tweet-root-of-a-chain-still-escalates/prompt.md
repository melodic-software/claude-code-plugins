---
description: "A chain that begins with a note tweet. SKILL.md Step 2: isNoteTweet 'does not say the post has no replies, and a chain can legitimately begin with a note tweet'; escalate on positive continuation evidence, such as the user asking for the thread or a 1/ marker, regardless of the flag. The eval sandbox blocks the network, so both responses are scaffolded: the xtomd /api/fetch JSON at notes/x-3333333333333333333-n6.json (isNoteTweet true, a long body ending 1/) and the Thread Reader App page at notes/threadreader-3333333333333333333.html, a hit whose first line records its final URL. reads-thread-page checks the run opened the step-2 page; reports-later-post passes only a reply carrying the cofferdam or Thornmouth, which appear only in post 3 of the unrolled page, never in the prompt or the root. Slash-invoked, so no Skill grader. Needs --scaffold --allow-tools Bash WebFetch."
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Escalates to step 2 despite isNoteTweet: true, because the explicit thread request and the 1/ marker are positive continuation evidence, and reports the whole chain from the saved Thread Reader App page, including the cofferdam borrowed from the Thornmouth harbour board in post 3.'
---

/x:read https://x.com/someone/status/3333333333333333333

I want the whole thread. Fetching doesn't work from here, so I ran the converters for this link on my laptop and saved what came back: the xtomd /api/fetch call (curl exited 0, HTTP 200) is in notes/x-3333333333333333333-n6.json, and the Thread Reader App page for that post id is in notes/threadreader-3333333333333333333.html. Use those files instead of fetching again.
