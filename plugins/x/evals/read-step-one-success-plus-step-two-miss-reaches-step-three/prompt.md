---
description: "Step 1 succeeds with a chain root and step 2 misses. SKILL.md Step 3: 'Reach this step whenever the requested content is still incomplete ... The common case is step 1 succeeding with a chain root and step 2 missing'; try the other sources first, then say what each step did and ask for the remaining URLs, never presenting the root as the whole chain. The eval sandbox blocks the network, so both converter responses are scaffolded: the xtomd /api/fetch JSON at notes/x-4444444444444444444-t9.json (isNoteTweet false, a root ending 1/) and the Thread Reader App response at notes/threadreader-4444444444444444444.html, a 200 whose first line records a final URL ending /error. The other sources are not scaffolded: their requests hit the blocked network and fail, which leaves the chain incomplete either way. reads-thread-page checks the run opened the step-2 response; says-truncated passes a reply calling the result partial, incomplete or truncated, or saying it holds only the root post. Slash-invoked, so no Skill grader. Needs --scaffold --allow-tools Bash WebFetch."
tags: ['read']
allowed_tools: [Read, Glob, Grep, Skill, Bash, WebFetch]
expected_outcome: 'Recognizes the thread is known-truncated even though step 1 succeeded: the saved Thread Reader App response ends in /error, so step 2 missed. Reaches step 3, reporting what each step did, saying the result is truncated, and asking for the remaining post URLs. Never presents the root alone as the complete thread.'
---

/x:read https://x.com/someone/status/4444444444444444444

I want the whole thread. Fetching doesn't work from here, so I ran the converters for this link on my laptop and saved what came back: the xtomd /api/fetch call (curl exited 0, HTTP 200) is in notes/x-4444444444444444444-t9.json, and the Thread Reader App response for that post id is in notes/threadreader-4444444444444444444.html. Use those files instead of fetching them again.
